// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReVault} from "../libraries/LibOnReVault.sol";
import {IOnReConfigurableVault} from "../interfaces/IOnReConfigurableVault.sol";

contract OnReConfigurableVaultFacet is IOnReConfigurableVault {
    function createConfigurableVault(
        OnReTypes.ConfigurableVaultKind kind,
        uint64 vaultInstanceId,
        address withdrawalDestination,
        uint16 refillTargetBps
    ) external override returns (bytes32 vaultId) {
        return LibOnReVault.createConfigurableVault(kind, vaultInstanceId, withdrawalDestination, refillTargetBps);
    }

    function updateConfigurableVault(bytes32 vaultId, address withdrawalDestination, uint16 refillTargetBps)
        external
        override
    {
        LibOnReVault.updateConfigurableVault(vaultId, withdrawalDestination, refillTargetBps);
    }

    function depositConfigurableVault(bytes32 vaultId, address token, uint256 amount) external override {
        LibOnReVault.depositConfigurableVault(vaultId, token, amount);
    }

    function withdrawConfigurableVault(bytes32 vaultId, address token, uint256 amount)
        external
        override
        returns (uint256 withdrawnAmount)
    {
        return LibOnReVault.withdrawConfigurableVault(vaultId, token, amount);
    }

    function configurableVaultBalance(bytes32 vaultId, address token) external view override returns (uint256) {
        return LibOnReVault.balance(vaultId, token);
    }
}
