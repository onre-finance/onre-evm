// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Reusable fee-policy configuration and fee calculation.
library LibOnReFeeConfig {
    uint16 internal constant MAX_BASIS_POINTS = 10_000;
    uint16 internal constant MAX_ALLOWED_FEE_BPS = 1_000;

    function createFeeConfig(uint64 feeConfigInstanceId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        internal
        returns (bytes32 feeConfigId)
    {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        _validateFeePolicy(basisPoints, feeVaultId);

        feeConfigId = OnReIds.feeConfigId(feeConfigInstanceId);
        OnReTypes.FeeConfig storage feeConfig = LibOnReStorage.appStorage().feeConfigs[feeConfigId];
        if (feeConfig.exists) revert IOnReAppErrors.FeeConfigAlreadyExistsError(feeConfigId);

        feeConfig.feeConfigId = feeConfigInstanceId;
        feeConfig.basisPoints = basisPoints;
        feeConfig.minimumAmount = minimumAmount;
        feeConfig.feeVaultId = feeVaultId;
        feeConfig.enabled = true;
        feeConfig.exists = true;
        emit IOnReAppEvents.FeeConfigCreated(feeConfigId, feeConfigInstanceId, basisPoints, minimumAmount, feeVaultId);
    }

    function updateFeeConfig(bytes32 feeConfigId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        internal
    {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        _validateFeePolicy(basisPoints, feeVaultId);
        OnReTypes.FeeConfig storage feeConfig = LibOnReValidation.requireFeeConfig(feeConfigId);
        if (
            feeConfig.basisPoints == basisPoints && feeConfig.minimumAmount == minimumAmount
                && feeConfig.feeVaultId == feeVaultId
        ) {
            revert IOnReAppErrors.NoChangeError();
        }

        feeConfig.basisPoints = basisPoints;
        feeConfig.minimumAmount = minimumAmount;
        feeConfig.feeVaultId = feeVaultId;
        emit IOnReAppEvents.FeeConfigUpdated(feeConfigId, basisPoints, minimumAmount, feeVaultId);
    }

    function setFeeConfigEnabled(bytes32 feeConfigId, bool enabled) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OnReTypes.FeeConfig storage feeConfig = LibOnReValidation.requireFeeConfig(feeConfigId);
        if (feeConfig.enabled == enabled) revert IOnReAppErrors.NoChangeError();
        feeConfig.enabled = enabled;
        emit IOnReAppEvents.FeeConfigEnabledSet(feeConfigId, enabled);
    }

    function calculateFee(uint256 grossInputAmount, OnReTypes.FeeConfig storage feeConfig)
        internal
        view
        returns (uint256 feeAmount)
    {
        feeAmount = OnReMath.calculateFee(grossInputAmount, feeConfig.basisPoints, MAX_BASIS_POINTS);
        if (feeAmount < feeConfig.minimumAmount) feeAmount = feeConfig.minimumAmount;
        if (feeAmount > grossInputAmount) revert IOnReAppErrors.InvalidFeeError();
    }

    function _validateFeePolicy(uint16 basisPoints, bytes32 feeVaultId) private view {
        if (basisPoints > MAX_ALLOWED_FEE_BPS) revert IOnReAppErrors.InvalidFeeError();
        LibOnReValidation.requireVaultKind(feeVaultId, OnReTypes.ConfigurableVaultKind.Fee);
    }
}
