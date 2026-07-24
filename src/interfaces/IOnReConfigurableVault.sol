// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";

interface IOnReConfigurableVault {
    function createConfigurableVault(
        OnReTypes.ConfigurableVaultKind kind,
        uint64 vaultInstanceId,
        address withdrawalDestination,
        uint16 refillTargetBps
    ) external returns (bytes32 vaultId);
    function updateConfigurableVault(bytes32 vaultId, address withdrawalDestination, uint16 refillTargetBps) external;
    function depositConfigurableVault(bytes32 vaultId, address token, uint256 amount) external;
    function withdrawConfigurableVault(bytes32 vaultId, address token, uint256 amount)
        external
        returns (uint256 withdrawnAmount);
    function configurableVaultBalance(bytes32 vaultId, address token) external view returns (uint256);
}
