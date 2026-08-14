// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ConfigurableVaultKind} from "../types/OnReTypes.sol";
import {LibOnReVault} from "../libraries/LibOnReVault.sol";

contract OnReConfigurableVaultFacet {
    function createConfigurableVault(
        ConfigurableVaultKind kind,
        uint64 vaultInstanceId,
        address withdrawalDestination,
        uint16 refillTargetBps
    ) external returns (bytes32 vaultId) {
        vaultId = LibOnReVault._createConfigurableVault(kind, vaultInstanceId, withdrawalDestination, refillTargetBps);
    }

    function updateConfigurableVault(bytes32 vaultId, address withdrawalDestination, uint16 refillTargetBps) external {
        LibOnReVault._updateConfigurableVault(vaultId, withdrawalDestination, refillTargetBps);
    }

    function depositConfigurableVault(bytes32 vaultId, address token, uint256 amount) external {
        LibOnReVault._depositConfigurableVault(vaultId, token, amount);
    }

    function withdrawConfigurableVault(bytes32 vaultId, address token, uint256 amount)
        external
        returns (uint256 withdrawnAmount)
    {
        withdrawnAmount = LibOnReVault._withdrawConfigurableVault(vaultId, token, amount);
    }

    function configurableVaultBalance(bytes32 vaultId, address token) external view returns (uint256) {
        return LibOnReVault._balance(vaultId, token);
    }
}
