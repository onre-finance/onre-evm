// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    InvalidDecimalsError,
    InvalidOfferDirectionError,
    InvalidTokenError,
    LiquidityVaultRequiredError,
    NoChangeError,
    OfferConfigAlreadyExistsError,
    OfferConfigNotFoundError,
    OfferConfigNotMigratableError,
    UnsupportedOfferFlowError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
import {
    OfferConfigCreated,
    OfferConfigEnabledSet,
    OfferConfigModeSet,
    OfferConfigReferencesUpdated
} from "../types/OnReAppEvents.sol";
import {
    ConfigurableVaultKind,
    FeeConfig,
    MakeOfferConfigParams,
    OfferAccess,
    OfferConfig,
    OfferDirection,
    OfferExecution,
    OfferFlow,
    Quoter,
    QuoterKind
} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnRePropAmm} from "./LibOnRePropAmm.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {MAX_TOKEN_DECIMALS} from "./OnReConstants.sol";

/// @notice Pair-and-instance offer configuration and reference validation.
library LibOnReOfferConfig {
    function _makeOfferConfig(MakeOfferConfigParams calldata params) internal returns (bytes32 offerConfigId) {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (params.tokenIn == address(0) || params.tokenOut == address(0)) {
            revert ZeroAddressError();
        }
        if (params.tokenIn == params.tokenOut) revert InvalidTokenError();

        OfferDirection direction = _deriveDirection(params.tokenIn, params.tokenOut);
        uint8 tokenInDecimals = IERC20Metadata(params.tokenIn).decimals();
        uint8 tokenOutDecimals = IERC20Metadata(params.tokenOut).decimals();
        if (tokenInDecimals > MAX_TOKEN_DECIMALS || tokenOutDecimals > MAX_TOKEN_DECIMALS) {
            revert InvalidDecimalsError();
        }

        offerConfigId = OnReIds._offerConfigId(params.tokenIn, params.tokenOut, params.instanceId);
        OfferConfig storage offer = LibOnReStorage._appStorage().offerConfigs[offerConfigId];
        if (offer.exists) revert OfferConfigAlreadyExistsError(offerConfigId);

        offer.tokenIn = params.tokenIn;
        offer.tokenOut = params.tokenOut;
        offer.instanceId = params.instanceId;
        // Worker requests are created without an approval, so they cannot enforce permissioned access.
        if (params.execution == OfferExecution.Worker && params.access != OfferAccess.Permissionless) {
            revert UnsupportedOfferFlowError(uint8(OfferFlow.Worker));
        }
        offer.access = params.access;
        offer.execution = params.execution;
        offer.direction = direction;
        offer.tokenInDecimals = tokenInDecimals;
        offer.tokenOutDecimals = tokenOutDecimals;
        offer.enabled = true;
        offer.exists = true;
        _setOfferReferences(
            offerConfigId, offer, params.quoterId, params.feeConfigId, params.proceedsVaultId, params.liquidityVaultId
        );

        emit OfferConfigCreated(
            offerConfigId,
            params.tokenIn,
            params.tokenOut,
            LibOnReValidation._legacyFlow(offer),
            direction,
            params.quoterId,
            params.feeConfigId,
            params.proceedsVaultId,
            params.liquidityVaultId
        );
        emit OfferConfigModeSet(offerConfigId, params.instanceId, params.access, params.execution);
    }

    function _updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OfferConfig storage offer = LibOnReValidation._requireOfferConfig(offerConfigId);
        if (
            offer.quoterId == quoterId && offer.feeConfigId == feeConfigId && offer.proceedsVaultId == proceedsVaultId
                && offer.liquidityVaultId == liquidityVaultId
        ) {
            revert NoChangeError();
        }
        _setOfferReferences(offerConfigId, offer, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId);
        emit OfferConfigReferencesUpdated(offerConfigId, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId);
    }

    function _setOfferConfigEnabled(bytes32 offerConfigId, bool enabled) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OfferConfig storage offer = LibOnReValidation._requireOfferConfig(offerConfigId);
        if (offer.enabled == enabled) revert NoChangeError();
        offer.enabled = enabled;
        emit OfferConfigEnabledSet(offerConfigId, enabled);
    }

    /// @notice Brings offers created before instance IDs and the access/execution split to the current layout.
    /// @dev Those offers hashed their flow where the instance ID is hashed now, so each keeps its ID
    /// as the instance equal to its flow ordinal. Permissioned and Permissionless offers only gain
    /// that stored instance ID. A Worker offer also has an out-of-range access byte: it becomes
    /// Permissionless + Worker and cannot be read until migrated, so migrate it with the upgrade.
    /// Offers that already match their ID are skipped, which makes the call safe to repeat.
    function _migrateOfferConfigs(bytes32[] calldata offerConfigIds) internal returns (uint256 migratedCount) {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        uint256 length = offerConfigIds.length;
        for (uint256 i; i < length; ++i) {
            if (_migrateOfferConfig(offerConfigIds[i])) ++migratedCount;
        }
    }

    function _migrateOfferConfig(bytes32 offerConfigId) private returns (bool migrated) {
        OfferConfig storage offer = LibOnReStorage._appStorage().offerConfigs[offerConfigId];
        if (!offer.exists) revert OfferConfigNotFoundError(offerConfigId);
        // Read the first slot raw: a legacy Worker flow is not a valid `OfferAccess`.
        uint256 firstSlot;
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            firstSlot := sload(offer.slot)
        }
        // forge-lint: disable-start(unsafe-typecast)
        address tokenIn = address(uint160(firstSlot));
        uint8 legacyFlow = uint8(firstSlot >> 160);
        uint64 storedInstanceId = uint64(firstSlot >> 176);
        // forge-lint: disable-end(unsafe-typecast)
        address tokenOut = offer.tokenOut;
        if (OnReIds._offerConfigId(tokenIn, tokenOut, storedInstanceId) == offerConfigId) return false;
        if (
            legacyFlow > uint8(OfferFlow.Worker)
                || OnReIds._offerConfigId(tokenIn, tokenOut, legacyFlow) != offerConfigId
        ) {
            revert OfferConfigNotMigratableError(offerConfigId);
        }
        OfferAccess access =
            legacyFlow == uint8(OfferFlow.Permissioned) ? OfferAccess.Permissioned : OfferAccess.Permissionless;
        OfferExecution execution =
            legacyFlow == uint8(OfferFlow.Worker) ? OfferExecution.Worker : OfferExecution.Instant;
        offer.access = access;
        offer.execution = execution;
        offer.instanceId = legacyFlow;
        emit OfferConfigModeSet(offerConfigId, legacyFlow, access, execution);
        return true;
    }

    function _setOfferReferences(
        bytes32 offerConfigId,
        OfferConfig storage offer,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) private {
        LibOnReValidation._requirePricer(OnReIds._usdPricerId(LibOnReValidation._offerManagedToken(offer)));
        Quoter storage quoter = LibOnReValidation._requireQuoter(quoterId);
        _validateQuoter(offer, quoterId, quoter);
        FeeConfig storage feeConfig = LibOnReValidation._requireFeeConfig(feeConfigId);
        LibOnReValidation._requireVaultKind(feeConfig.feeVaultId, ConfigurableVaultKind.Fee);
        LibOnReValidation._requireVaultKind(proceedsVaultId, ConfigurableVaultKind.Proceeds);
        if (liquidityVaultId != bytes32(0)) {
            LibOnReValidation._requireVaultKind(liquidityVaultId, ConfigurableVaultKind.Liquidity);
        }
        if (offer.direction == OfferDirection.ManagedToAsset && liquidityVaultId == bytes32(0)) {
            revert LiquidityVaultRequiredError(offerConfigId);
        }

        offer.quoterId = quoterId;
        offer.feeConfigId = feeConfigId;
        offer.proceedsVaultId = proceedsVaultId;
        offer.liquidityVaultId = liquidityVaultId;
    }

    /// @dev Access and execution do not restrict the quoter. A Prop AMM quoter is bound to one pair;
    /// `NavPermissionless` is a deprecated alias of `Nav` kept for existing quoters and their IDs.
    function _validateQuoter(OfferConfig storage offer, bytes32 quoterId, Quoter storage quoter) private view {
        if (quoter.kind == QuoterKind.PropAmm) {
            LibOnRePropAmm._validatePair(quoterId, LibOnReStorage._appStorage().propAmmStates[quoterId], offer);
        }
    }

    function _deriveDirection(address tokenIn, address tokenOut) private view returns (OfferDirection) {
        bool inputIsManaged = LibOnReValidation._isManagedToken(tokenIn);
        bool outputIsManaged = LibOnReValidation._isManagedToken(tokenOut);
        if (inputIsManaged == outputIsManaged) revert InvalidOfferDirectionError();
        address managedToken = inputIsManaged ? tokenIn : tokenOut;
        LibOnReValidation._requireEnabledManagedToken(managedToken);
        return inputIsManaged ? OfferDirection.ManagedToAsset : OfferDirection.AssetToManaged;
    }
}
