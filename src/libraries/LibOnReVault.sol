// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    ConfigurableVaultAlreadyExistsError,
    ExactAssetDebitRequiredError,
    ExactAssetTransferRequiredError,
    InsufficientBalanceError,
    InsufficientLiquidityError,
    InvalidAmountError,
    InvalidBasisPointsError,
    KilledError,
    MissingConfigurableVaultDestinationError,
    NoChangeError,
    UnsupportedConfigurableVaultKindError,
    ZeroAddressError,
    ZeroBalanceError
} from "../types/OnReAppErrors.sol";
import {
    ConfigurableVaultAccrued,
    ConfigurableVaultCreated,
    ConfigurableVaultUpdated,
    ConfigurableVaultWithdrawn
} from "../types/OnReAppEvents.sol";
import {ConfigurableVault, ConfigurableVaultKind} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";

/// @notice Configuration, accounting, and token movement for reusable vault instances.
library LibOnReVault {
    using SafeERC20 for IERC20;

    uint16 private constant MAX_BASIS_POINTS = 10_000;

    function _createConfigurableVault(
        ConfigurableVaultKind kind,
        uint64 vaultInstanceId,
        address withdrawalDestination,
        uint16 refillTargetBps
    ) internal returns (bytes32 vaultId) {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        _validateRefillTarget(kind, refillTargetBps);

        vaultId = OnReIds._configurableVaultId(kind, vaultInstanceId);
        ConfigurableVault storage vault = LibOnReStorage._appStorage().configurableVaults[vaultId];
        if (vault.exists) revert ConfigurableVaultAlreadyExistsError(vaultId);

        vault.kind = kind;
        vault.vaultId = vaultInstanceId;
        vault.withdrawalDestination = withdrawalDestination;
        vault.refillTargetBps = refillTargetBps;
        vault.exists = true;
        emit ConfigurableVaultCreated(vaultId, kind, vaultInstanceId, withdrawalDestination, refillTargetBps);
    }

    function _updateConfigurableVault(bytes32 vaultId, address withdrawalDestination, uint16 refillTargetBps) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        ConfigurableVault storage vault = LibOnReValidation._requireConfigurableVault(vaultId);
        _validateRefillTarget(vault.kind, refillTargetBps);
        if (vault.withdrawalDestination == withdrawalDestination && vault.refillTargetBps == refillTargetBps) {
            revert NoChangeError();
        }

        vault.withdrawalDestination = withdrawalDestination;
        vault.refillTargetBps = refillTargetBps;
        emit ConfigurableVaultUpdated(vaultId, withdrawalDestination, refillTargetBps);
    }

    function _depositConfigurableVault(bytes32 vaultId, address token, uint256 amount) internal {
        LibOnReValidation._requireConfigurableVault(vaultId);
        if (token == address(0)) revert ZeroAddressError();
        if (amount == 0) revert InvalidAmountError();

        _pullExactTokenAmount(token, msg.sender, amount);
        _accrue(vaultId, token, amount);
    }

    function _withdrawConfigurableVault(bytes32 vaultId, address token, uint256 amount)
        internal
        returns (uint256 withdrawnAmount)
    {
        if (LibOnReStorage._appStorage().isKilled) revert KilledError();
        if (token == address(0)) revert ZeroAddressError();
        ConfigurableVault storage vault = LibOnReValidation._requireConfigurableVault(vaultId);
        if (vault.kind == ConfigurableVaultKind.Liquidity) {
            LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        } else if (vault.kind != ConfigurableVaultKind.Fee && vault.kind != ConfigurableVaultKind.Proceeds) {
            revert UnsupportedConfigurableVaultKindError(uint8(vault.kind));
        }
        address destination = vault.withdrawalDestination;
        if (destination == address(0)) {
            revert MissingConfigurableVaultDestinationError(vaultId);
        }

        uint256 availableAmount = _balance(vaultId, token);
        withdrawnAmount = amount == 0 ? availableAmount : amount;
        if (withdrawnAmount == 0) revert ZeroBalanceError();
        if (withdrawnAmount > availableAmount) {
            revert InsufficientBalanceError(availableAmount, withdrawnAmount);
        }

        LibOnReStorage._appStorage().configurableVaultBalances[vaultId][token] = availableAmount - withdrawnAmount;
        _transferExactTokenAmount(token, destination, withdrawnAmount);
        emit ConfigurableVaultWithdrawn(vaultId, token, destination, withdrawnAmount);
    }

    function _pullExactTokenAmount(address token, address from, uint256 amount) internal {
        _transferExactTokenAmountFrom(token, from, address(this), amount);
    }

    function _transferExactTokenAmountFrom(address token, address from, address recipient, uint256 amount) internal {
        IERC20 tokenContract = IERC20(token);
        uint256 senderBalanceBefore = tokenContract.balanceOf(from);
        uint256 recipientBalanceBefore = tokenContract.balanceOf(recipient);
        tokenContract.safeTransferFrom(from, recipient, amount);
        _requireExactBalanceDeltas(
            tokenContract, token, from, recipient, amount, senderBalanceBefore, recipientBalanceBefore
        );
    }

    function _transferExactTokenAmount(address token, address recipient, uint256 amount) internal {
        IERC20 tokenContract = IERC20(token);
        uint256 senderBalanceBefore = tokenContract.balanceOf(address(this));
        uint256 recipientBalanceBefore = tokenContract.balanceOf(recipient);
        tokenContract.safeTransfer(recipient, amount);
        _requireExactBalanceDeltas(
            tokenContract, token, address(this), recipient, amount, senderBalanceBefore, recipientBalanceBefore
        );
    }

    function _accrue(bytes32 vaultId, address token, uint256 amount) internal {
        if (amount == 0) return;
        LibOnReValidation._requireConfigurableVault(vaultId);
        uint256 newBalance = _balance(vaultId, token) + amount;
        LibOnReStorage._appStorage().configurableVaultBalances[vaultId][token] = newBalance;
        emit ConfigurableVaultAccrued(vaultId, token, amount, newBalance);
    }

    function _consumeLiquidity(bytes32 vaultId, address token, address recipient, uint256 amount) internal {
        LibOnReValidation._requireVaultKind(vaultId, ConfigurableVaultKind.Liquidity);
        uint256 availableAmount = _balance(vaultId, token);
        if (availableAmount < amount) {
            revert InsufficientLiquidityError(vaultId, token, availableAmount, amount);
        }
        LibOnReStorage._appStorage().configurableVaultBalances[vaultId][token] = availableAmount - amount;
        _transferExactTokenAmount(token, recipient, amount);
    }

    function _balance(bytes32 vaultId, address token) internal view returns (uint256) {
        return LibOnReStorage._appStorage().configurableVaultBalances[vaultId][token];
    }

    function _validateRefillTarget(ConfigurableVaultKind kind, uint16 refillTargetBps) private pure {
        if (refillTargetBps > MAX_BASIS_POINTS) revert InvalidBasisPointsError();
        if (kind == ConfigurableVaultKind.Liquidity) return;
        if (kind == ConfigurableVaultKind.Fee || kind == ConfigurableVaultKind.Proceeds) {
            if (refillTargetBps != 0) revert InvalidBasisPointsError();
            return;
        }
        revert UnsupportedConfigurableVaultKindError(uint8(kind));
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
            revert ExactAssetDebitRequiredError(token, amount, debitedAmount);
        }

        uint256 recipientBalanceAfter = tokenContract.balanceOf(recipient);
        uint256 receivedAmount =
            recipientBalanceAfter >= recipientBalanceBefore ? recipientBalanceAfter - recipientBalanceBefore : 0;
        if (receivedAmount != amount) {
            revert ExactAssetTransferRequiredError(token, amount, receivedAmount);
        }
    }
}
