// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {IOnReToken} from "../IOnReToken.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    BufferAlreadyExistsError,
    BufferNotFoundError,
    BufferSupplyMismatchError,
    InvalidAmountError,
    InvalidBasisPointsError,
    InvalidBufferAprError,
    InvalidBufferControllerError,
    KilledError,
    NoChangeError
} from "../types/OnReAppErrors.sol";
import {
    BufferAccrued,
    BufferFeeConfigUpdated,
    BufferGrossAprUpdated,
    BufferInitialized,
    BufferSupplyChangeRecorded
} from "../types/OnReAppEvents.sol";
import {BufferState, ConfigurableVaultKind, Pricer, PricingVector} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {LibOnReVault} from "./LibOnReVault.sol";
import {OnReIds} from "./OnReIds.sol";

/// @notice Per-token reserve growth that settles before every tracked supply change.
library LibOnReBuffer {
    uint256 internal constant APR_SCALE = 1_000_000;
    uint256 internal constant MAX_GROSS_APR = 1_000_000;
    uint256 internal constant MAX_BASIS_POINTS = 10_000;
    uint256 internal constant SECONDS_PER_YEAR = 365 days;

    struct BufferAccrualResult {
        uint256 secondsElapsed;
        uint256 aprDelta;
        uint256 bufferMintAmount;
        uint256 reserveMintAmount;
        uint256 managementFeeMintAmount;
        uint256 performanceFeeMintAmount;
        uint256 oldPreviousSupply;
        uint256 newPreviousSupply;
        uint256 oldPerformanceFeeHighWatermark;
        uint256 newPerformanceFeeHighWatermark;
        uint256 currentNav;
        uint64 timestamp;
    }

    function _initializeBuffer(address onReToken) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        LibOnReValidation._requireEnabledOnReToken(onReToken);

        BufferState storage state = LibOnReStorage._appStorage().bufferStates[onReToken];
        if (state.exists) revert BufferAlreadyExistsError(onReToken);

        bytes32 reserveVaultId = OnReIds._bufferReserveVaultId(onReToken);
        bytes32 managementFeeVaultId = OnReIds._bufferManagementFeeVaultId(onReToken);
        bytes32 performanceFeeVaultId = OnReIds._bufferPerformanceFeeVaultId(onReToken);

        LibOnReVault._createDerivedConfigurableVault(
            reserveVaultId, ConfigurableVaultKind.BufferReserve, OnReIds.BUFFER_RESERVE_VAULT_INSTANCE_ID
        );
        LibOnReVault._createDerivedConfigurableVault(
            managementFeeVaultId, ConfigurableVaultKind.Fee, OnReIds.BUFFER_MANAGEMENT_FEE_VAULT_INSTANCE_ID
        );
        LibOnReVault._createDerivedConfigurableVault(
            performanceFeeVaultId, ConfigurableVaultKind.Fee, OnReIds.BUFFER_PERFORMANCE_FEE_VAULT_INSTANCE_ID
        );

        state.reserveVaultId = reserveVaultId;
        state.managementFeeVaultId = managementFeeVaultId;
        state.performanceFeeVaultId = performanceFeeVaultId;
        state.performanceFeeHighWatermarkEnabled = true;
        // forge-lint: disable-next-line(unsafe-typecast)
        state.lastAccrualTimestamp = uint64(block.timestamp);
        state.exists = true;

        emit BufferInitialized(
            onReToken, reserveVaultId, managementFeeVaultId, performanceFeeVaultId, state.lastAccrualTimestamp
        );
    }

    function _setBufferGrossApr(address onReToken, uint64 grossApr) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (grossApr > MAX_GROSS_APR) revert InvalidBufferAprError(grossApr);
        BufferState storage state = _requireBuffer(onReToken);
        if (state.grossApr == grossApr) revert NoChangeError();

        _accrue(onReToken, state);
        uint64 oldGrossApr = state.grossApr;
        state.grossApr = grossApr;
        emit BufferGrossAprUpdated(onReToken, oldGrossApr, grossApr);
    }

    function _setBufferFeeConfig(
        address onReToken,
        uint16 managementFeeBasisPoints,
        uint16 performanceFeeBasisPoints,
        bool performanceFeeHighWatermarkEnabled
    ) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (managementFeeBasisPoints > MAX_BASIS_POINTS || performanceFeeBasisPoints > MAX_BASIS_POINTS) {
            revert InvalidBasisPointsError();
        }

        BufferState storage state = _requireBuffer(onReToken);
        if (
            state.managementFeeBasisPoints == managementFeeBasisPoints
                && state.performanceFeeBasisPoints == performanceFeeBasisPoints
                && state.performanceFeeHighWatermarkEnabled == performanceFeeHighWatermarkEnabled
        ) {
            revert NoChangeError();
        }

        _accrue(onReToken, state);
        uint16 oldManagementFeeBasisPoints = state.managementFeeBasisPoints;
        uint16 oldPerformanceFeeBasisPoints = state.performanceFeeBasisPoints;
        bool oldPerformanceFeeHighWatermarkEnabled = state.performanceFeeHighWatermarkEnabled;

        state.managementFeeBasisPoints = managementFeeBasisPoints;
        state.performanceFeeBasisPoints = performanceFeeBasisPoints;
        state.performanceFeeHighWatermarkEnabled = performanceFeeHighWatermarkEnabled;

        emit BufferFeeConfigUpdated(
            onReToken,
            oldManagementFeeBasisPoints,
            managementFeeBasisPoints,
            oldPerformanceFeeBasisPoints,
            performanceFeeBasisPoints,
            oldPerformanceFeeHighWatermarkEnabled,
            performanceFeeHighWatermarkEnabled
        );
    }

    function _settleBuffer(address onReToken) internal returns (uint256 bufferMintAmount) {
        LibOnReAccessControl._checkRole(LibOnReRoles.WORKER_ROLE);
        if (LibOnReStorage._appStorage().isKilled) revert KilledError();
        bufferMintAmount = _accrue(onReToken, _requireBuffer(onReToken)).bufferMintAmount;
    }

    function _onBeforeSupplyChange(uint256 amount, bool isMint) internal {
        address onReToken = msg.sender;
        BufferState storage state = _requireBuffer(onReToken);
        _requireController(onReToken);
        _accrue(onReToken, state);

        uint256 oldPreviousSupply = state.previousSupply;
        uint256 newPreviousSupply;
        if (isMint) {
            newPreviousSupply = oldPreviousSupply + amount;
        } else {
            if (amount > oldPreviousSupply) revert InvalidAmountError();
            newPreviousSupply = oldPreviousSupply - amount;
        }
        state.previousSupply = newPreviousSupply;
        emit BufferSupplyChangeRecorded(onReToken, isMint, amount, oldPreviousSupply, newPreviousSupply);
    }

    function _bufferState(address onReToken) internal view returns (BufferState storage state) {
        state = _requireBuffer(onReToken);
    }

    function _accrue(address onReToken, BufferState storage state) private returns (BufferAccrualResult memory result) {
        _requireController(onReToken);
        (uint256 currentApr, uint256 currentNav) = _currentPricing(onReToken);
        // forge-lint: disable-next-line(unsafe-typecast)
        uint64 timestamp = uint64(block.timestamp);
        uint256 currentSupply = IERC20(onReToken).totalSupply();
        uint256 oldPreviousSupply = state.previousSupply;
        uint256 oldHighWatermark = state.performanceFeeHighWatermark;
        uint256 secondsElapsed = timestamp - state.lastAccrualTimestamp;

        if (oldPreviousSupply == 0) {
            return _seedBaseline(onReToken, state, currentSupply, currentApr, currentNav, secondsElapsed, timestamp);
        }

        if (currentSupply != oldPreviousSupply) {
            revert BufferSupplyMismatchError(onReToken, oldPreviousSupply, currentSupply);
        }
        uint256 aprDelta = state.grossApr > currentApr ? state.grossApr - currentApr : 0;
        uint256 bufferMintAmount = _calculateGrossAccrual(oldPreviousSupply, aprDelta, currentApr, secondsElapsed);
        (uint256 reserveMintAmount, uint256 managementFeeMintAmount, uint256 performanceFeeMintAmount) =
            _calculateFeeSplit(state, bufferMintAmount, aprDelta, currentNav);

        uint256 newPreviousSupply = currentSupply + bufferMintAmount;
        uint256 newHighWatermark = oldHighWatermark > currentNav ? oldHighWatermark : currentNav;
        state.previousSupply = newPreviousSupply;
        state.performanceFeeHighWatermark = newHighWatermark;
        state.lastAccrualTimestamp = timestamp;

        if (bufferMintAmount > 0) {
            LibOnReVault._accrue(state.reserveVaultId, onReToken, reserveMintAmount);
            LibOnReVault._accrue(state.managementFeeVaultId, onReToken, managementFeeMintAmount);
            LibOnReVault._accrue(state.performanceFeeVaultId, onReToken, performanceFeeMintAmount);
            IOnReToken(onReToken).mintBuffer(bufferMintAmount);
        }

        result = BufferAccrualResult({
            secondsElapsed: secondsElapsed,
            aprDelta: aprDelta,
            bufferMintAmount: bufferMintAmount,
            reserveMintAmount: reserveMintAmount,
            managementFeeMintAmount: managementFeeMintAmount,
            performanceFeeMintAmount: performanceFeeMintAmount,
            oldPreviousSupply: oldPreviousSupply,
            newPreviousSupply: newPreviousSupply,
            oldPerformanceFeeHighWatermark: oldHighWatermark,
            newPerformanceFeeHighWatermark: newHighWatermark,
            currentNav: currentNav,
            timestamp: timestamp
        });
        _emitAccrued(onReToken, result);
    }

    function _seedBaseline(
        address onReToken,
        BufferState storage state,
        uint256 currentSupply,
        uint256 currentApr,
        uint256 currentNav,
        uint256 secondsElapsed,
        uint64 timestamp
    ) private returns (BufferAccrualResult memory result) {
        uint256 oldHighWatermark = state.performanceFeeHighWatermark;
        state.previousSupply = currentSupply;
        state.performanceFeeHighWatermark = currentNav;
        state.lastAccrualTimestamp = timestamp;
        result = BufferAccrualResult({
            secondsElapsed: secondsElapsed,
            aprDelta: state.grossApr > currentApr ? state.grossApr - currentApr : 0,
            bufferMintAmount: 0,
            reserveMintAmount: 0,
            managementFeeMintAmount: 0,
            performanceFeeMintAmount: 0,
            oldPreviousSupply: 0,
            newPreviousSupply: currentSupply,
            oldPerformanceFeeHighWatermark: oldHighWatermark,
            newPerformanceFeeHighWatermark: currentNav,
            currentNav: currentNav,
            timestamp: timestamp
        });
        _emitAccrued(onReToken, result);
    }

    function _calculateGrossAccrual(
        uint256 previousSupply,
        uint256 aprDelta,
        uint256 currentApr,
        uint256 secondsElapsed
    ) private pure returns (uint256) {
        if (previousSupply == 0 || aprDelta == 0 || secondsElapsed == 0) return 0;
        uint256 denominator = SECONDS_PER_YEAR * APR_SCALE + currentApr * secondsElapsed;
        return Math.mulDiv(previousSupply, aprDelta * secondsElapsed, denominator);
    }

    function _calculateFeeSplit(
        BufferState storage state,
        uint256 bufferMintAmount,
        uint256 aprDelta,
        uint256 currentNav
    ) private view returns (uint256 reserveAmount, uint256 managementAmount, uint256 performanceAmount) {
        if (bufferMintAmount == 0) return (0, 0, 0);

        if (aprDelta > 0) {
            uint256 managementFeeApr = uint256(state.managementFeeBasisPoints) * APR_SCALE / MAX_BASIS_POINTS;
            if (managementFeeApr > aprDelta) managementFeeApr = aprDelta;
            managementAmount = Math.mulDiv(bufferMintAmount, managementFeeApr, aprDelta);
        }

        uint256 afterManagement = bufferMintAmount - managementAmount;
        // `>=` is the high-watermark policy; changing equality would alter fee eligibility.
        // solhint-disable gas-strict-inequalities
        bool chargePerformanceFee = !state.performanceFeeHighWatermarkEnabled
            || (state.performanceFeeHighWatermark != 0 && currentNav >= state.performanceFeeHighWatermark);
        // solhint-enable gas-strict-inequalities
        if (chargePerformanceFee) {
            performanceAmount = Math.mulDiv(afterManagement, state.performanceFeeBasisPoints, MAX_BASIS_POINTS);
        }
        reserveAmount = afterManagement - performanceAmount;
    }

    function _currentPricing(address onReToken) private view returns (uint256 currentApr, uint256 currentNav) {
        bytes32 pricerId = OnReIds._usdPricerId(onReToken);
        Pricer storage pricer = LibOnReValidation._requireExecutablePricer(pricerId);
        PricingVector storage vector = LibOnRePricer._activePricingVector(pricerId, pricer);
        currentApr = vector.apr;
        currentNav = LibOnRePricer._calculatePricingVectorPriceAt(vector, block.timestamp);
    }

    function _requireBuffer(address onReToken) private view returns (BufferState storage state) {
        state = LibOnReStorage._appStorage().bufferStates[onReToken];
        if (!state.exists) revert BufferNotFoundError(onReToken);
    }

    function _requireController(address onReToken) private view {
        address controller = IOnReToken(onReToken).bufferController();
        if (controller != address(this)) revert InvalidBufferControllerError(onReToken, controller);
    }

    function _emitAccrued(address onReToken, BufferAccrualResult memory result) private {
        emit BufferAccrued(
            onReToken,
            result.secondsElapsed,
            result.aprDelta,
            result.bufferMintAmount,
            result.reserveMintAmount,
            result.managementFeeMintAmount,
            result.performanceFeeMintAmount,
            result.oldPreviousSupply,
            result.newPreviousSupply,
            result.oldPerformanceFeeHighWatermark,
            result.newPerformanceFeeHighWatermark,
            result.currentNav,
            result.timestamp
        );
    }
}
