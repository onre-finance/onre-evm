// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {FeeConfigAlreadyExistsError, InvalidFeeError, NoChangeError} from "../types/OnReAppErrors.sol";
import {FeeConfigCreated, FeeConfigEnabledSet, FeeConfigUpdated} from "../types/OnReAppEvents.sol";
import {ConfigurableVaultKind, FeeConfig} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Reusable fee-policy configuration and fee calculation.
library LibOnReFeeConfig {
    uint16 internal constant MAX_BASIS_POINTS = 10_000;
    uint16 internal constant MAX_ALLOWED_FEE_BPS = 1_000;

    function _createFeeConfig(uint64 feeConfigInstanceId, uint16 basisPoints, bytes32 feeVaultId)
        internal
        returns (bytes32 feeConfigId)
    {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        _validateFeePolicy(basisPoints, feeVaultId);

        feeConfigId = OnReIds._feeConfigId(feeConfigInstanceId);
        FeeConfig storage feeConfig = LibOnReStorage._appStorage().feeConfigs[feeConfigId];
        if (feeConfig.exists) revert FeeConfigAlreadyExistsError(feeConfigId);

        feeConfig.feeConfigId = feeConfigInstanceId;
        feeConfig.basisPoints = basisPoints;
        feeConfig.feeVaultId = feeVaultId;
        feeConfig.enabled = true;
        feeConfig.exists = true;
        emit FeeConfigCreated(feeConfigId, feeConfigInstanceId, basisPoints, feeVaultId);
    }

    function _updateFeeConfig(bytes32 feeConfigId, uint16 basisPoints, bytes32 feeVaultId) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        _validateFeePolicy(basisPoints, feeVaultId);
        FeeConfig storage feeConfig = LibOnReValidation._requireFeeConfig(feeConfigId);
        if (feeConfig.basisPoints == basisPoints && feeConfig.feeVaultId == feeVaultId) {
            revert NoChangeError();
        }

        feeConfig.basisPoints = basisPoints;
        feeConfig.feeVaultId = feeVaultId;
        emit FeeConfigUpdated(feeConfigId, basisPoints, feeVaultId);
    }

    function _setFeeConfigEnabled(bytes32 feeConfigId, bool enabled) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        FeeConfig storage feeConfig = LibOnReValidation._requireFeeConfig(feeConfigId);
        if (feeConfig.enabled == enabled) revert NoChangeError();
        feeConfig.enabled = enabled;
        emit FeeConfigEnabledSet(feeConfigId, enabled);
    }

    function _calculateFee(uint256 grossInputAmount, FeeConfig storage feeConfig)
        internal
        view
        returns (uint256 feeAmount)
    {
        feeAmount = OnReMath._calculateFee(grossInputAmount, feeConfig.basisPoints, MAX_BASIS_POINTS);
    }

    function _validateFeePolicy(uint16 basisPoints, bytes32 feeVaultId) private view {
        if (basisPoints > MAX_ALLOWED_FEE_BPS) revert InvalidFeeError();
        LibOnReValidation._requireVaultKind(feeVaultId, ConfigurableVaultKind.Fee);
    }
}
