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
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
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
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
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
        if (vault.kind == OnReTypes.ConfigurableVaultKind.Liquidity) {
            LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        }
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
        transferExactTokenAmount(token, destination, withdrawnAmount);
        emit IOnReAppEvents.ConfigurableVaultWithdrawn(vaultId, token, destination, withdrawnAmount);
    }

    function pullExactTokenAmount(address token, address from, uint256 amount) internal {
        transferExactTokenAmountFrom(token, from, address(this), amount);
    }

    function transferExactTokenAmountFrom(address token, address from, address recipient, uint256 amount) internal {
        IERC20 tokenContract = IERC20(token);
        uint256 senderBalanceBefore = tokenContract.balanceOf(from);
        uint256 recipientBalanceBefore = tokenContract.balanceOf(recipient);
        tokenContract.safeTransferFrom(from, recipient, amount);
        _requireExactBalanceDeltas(
            tokenContract, token, from, recipient, amount, senderBalanceBefore, recipientBalanceBefore
        );
    }

    function transferExactTokenAmount(address token, address recipient, uint256 amount) internal {
        IERC20 tokenContract = IERC20(token);
        uint256 senderBalanceBefore = tokenContract.balanceOf(address(this));
        uint256 recipientBalanceBefore = tokenContract.balanceOf(recipient);
        tokenContract.safeTransfer(recipient, amount);
        _requireExactBalanceDeltas(
            tokenContract, token, address(this), recipient, amount, senderBalanceBefore, recipientBalanceBefore
        );
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
        transferExactTokenAmount(token, recipient, amount);
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

    function _requireExactBalanceDeltas(
        IERC20 tokenContract,
        address token,
        address sender,
        address recipient,
        uint256 amount,
        uint256 senderBalanceBefore,
        uint256 recipientBalanceBefore
    ) private view {
        uint256 senderBalanceAfter = tokenContract.balanceOf(sender);
        uint256 debitedAmount = senderBalanceAfter <= senderBalanceBefore ? senderBalanceBefore - senderBalanceAfter : 0;
        if (debitedAmount != amount) {
            revert IOnReAppErrors.ExactAssetDebitRequiredError(token, amount, debitedAmount);
        }

        uint256 recipientBalanceAfter = tokenContract.balanceOf(recipient);
        uint256 receivedAmount =
            recipientBalanceAfter >= recipientBalanceBefore ? recipientBalanceAfter - recipientBalanceBefore : 0;
        if (receivedAmount != amount) {
            revert IOnReAppErrors.ExactAssetTransferRequiredError(token, amount, receivedAmount);
        }
    }
}
