// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";

/// @notice Configuration, accounting, and token movement for reusable vault instances.
library LibOnReVault {
    using SafeERC20 for IERC20;

    uint16 private constant MAX_BASIS_POINTS = 10_000;

    function createConfigurableVault(
        OnReTypes.ConfigurableVaultKind kind,
        uint64 vaultInstanceId,
        address withdrawalDestination,
        uint16 refillTargetBps
    ) internal returns (bytes32 vaultId) {
        LibOnReAccessControl.checkRole(LibOnReRoles.VAULT_ADMIN_ROLE);
        _validateRefillTarget(kind, refillTargetBps);

        vaultId = OnReIds.configurableVaultId(kind, vaultInstanceId);
        OnReTypes.ConfigurableVault storage vault = LibOnReStorage.appStorage().configurableVaults[vaultId];
        if (vault.exists) revert IOnReAppErrors.ConfigurableVaultAlreadyExistsError(vaultId);

        vault.kind = kind;
        vault.vaultId = vaultInstanceId;
        vault.withdrawalDestination = withdrawalDestination;
        vault.refillTargetBps = refillTargetBps;
        vault.exists = true;
        emit IOnReAppEvents.ConfigurableVaultCreated(
            vaultId, kind, vaultInstanceId, withdrawalDestination, refillTargetBps
        );
    }

    function updateConfigurableVault(bytes32 vaultId, address withdrawalDestination, uint16 refillTargetBps) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.VAULT_ADMIN_ROLE);
        OnReTypes.ConfigurableVault storage vault = LibOnReValidation.requireConfigurableVault(vaultId);
        _validateRefillTarget(vault.kind, refillTargetBps);
        if (vault.withdrawalDestination == withdrawalDestination && vault.refillTargetBps == refillTargetBps) {
            revert IOnReAppErrors.NoChangeError();
        }

        vault.withdrawalDestination = withdrawalDestination;
        vault.refillTargetBps = refillTargetBps;
        emit IOnReAppEvents.ConfigurableVaultUpdated(vaultId, withdrawalDestination, refillTargetBps);
    }

    function depositConfigurableVault(bytes32 vaultId, address token, uint256 amount) internal {
        LibOnReValidation.requireConfigurableVault(vaultId);
        if (token == address(0)) revert IOnReAppErrors.ZeroAddressError();
        if (amount == 0) revert IOnReAppErrors.InvalidAmountError();

        pullExactTokenAmount(token, msg.sender, amount);
        accrue(vaultId, token, amount);
    }

    function withdrawConfigurableVault(bytes32 vaultId, address token, uint256 amount)
        internal
        returns (uint256 withdrawnAmount)
    {
        if (LibOnReStorage.appStorage().isKilled) revert IOnReAppErrors.KilledError();
        if (token == address(0)) revert IOnReAppErrors.ZeroAddressError();
        OnReTypes.ConfigurableVault storage vault = LibOnReValidation.requireConfigurableVault(vaultId);
        address destination = vault.withdrawalDestination;
        if (destination == address(0)) {
            revert IOnReAppErrors.MissingConfigurableVaultDestinationError(vaultId);
        }

        uint256 availableAmount = balance(vaultId, token);
        withdrawnAmount = amount == 0 ? availableAmount : amount;
        if (withdrawnAmount == 0) revert IOnReAppErrors.ZeroBalanceError();
        if (withdrawnAmount > availableAmount) {
            revert IOnReAppErrors.InsufficientBalanceError(availableAmount, withdrawnAmount);
        }

        LibOnReStorage.appStorage().configurableVaultBalances[vaultId][token] = availableAmount - withdrawnAmount;
        _transferExact(token, destination, withdrawnAmount);
        emit IOnReAppEvents.ConfigurableVaultWithdrawn(vaultId, token, destination, withdrawnAmount);
    }

    function pullExactTokenAmount(address token, address from, uint256 amount) internal {
        transferExactTokenAmountFrom(token, from, address(this), amount);
    }

    function transferExactTokenAmountFrom(address token, address from, address recipient, uint256 amount) internal {
        IERC20 tokenContract = IERC20(token);
        uint256 balanceBefore = tokenContract.balanceOf(recipient);
        tokenContract.safeTransferFrom(from, recipient, amount);
        uint256 receivedAmount = tokenContract.balanceOf(recipient) - balanceBefore;
        if (receivedAmount != amount) {
            revert IOnReAppErrors.ExactAssetTransferRequiredError(token, amount, receivedAmount);
        }
    }

    function accrue(bytes32 vaultId, address token, uint256 amount) internal {
        if (amount == 0) return;
        LibOnReValidation.requireConfigurableVault(vaultId);
        uint256 newBalance = balance(vaultId, token) + amount;
        LibOnReStorage.appStorage().configurableVaultBalances[vaultId][token] = newBalance;
        emit IOnReAppEvents.ConfigurableVaultAccrued(vaultId, token, amount, newBalance);
    }

    function consumeLiquidity(bytes32 vaultId, address token, address recipient, uint256 amount) internal {
        LibOnReValidation.requireVaultKind(vaultId, OnReTypes.ConfigurableVaultKind.Liquidity);
        uint256 availableAmount = balance(vaultId, token);
        if (availableAmount < amount) {
            revert IOnReAppErrors.InsufficientLiquidityError(vaultId, token, availableAmount, amount);
        }
        LibOnReStorage.appStorage().configurableVaultBalances[vaultId][token] = availableAmount - amount;
        _transferExact(token, recipient, amount);
    }

    function balance(bytes32 vaultId, address token) internal view returns (uint256) {
        return LibOnReStorage.appStorage().configurableVaultBalances[vaultId][token];
    }

    function _validateRefillTarget(OnReTypes.ConfigurableVaultKind kind, uint16 refillTargetBps) private pure {
        if (refillTargetBps > MAX_BASIS_POINTS) revert IOnReAppErrors.InvalidBasisPointsError();
        if (kind != OnReTypes.ConfigurableVaultKind.Liquidity && refillTargetBps != 0) {
            revert IOnReAppErrors.InvalidBasisPointsError();
        }
    }

    function _transferExact(address token, address recipient, uint256 amount) private {
        IERC20 tokenContract = IERC20(token);
        uint256 balanceBefore = tokenContract.balanceOf(recipient);
        tokenContract.safeTransfer(recipient, amount);
        uint256 receivedAmount = tokenContract.balanceOf(recipient) - balanceBefore;
        if (receivedAmount != amount) {
            revert IOnReAppErrors.ExactAssetTransferRequiredError(token, amount, receivedAmount);
        }
    }
}
