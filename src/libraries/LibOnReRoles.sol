// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @notice Application roles are separate from Diamond upgrade ownership.
library LibOnReRoles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal constant CONFIG_ADMIN_ROLE = keccak256("ONRE_CONFIG_ADMIN_ROLE");
    bytes32 internal constant WORKER_ROLE = keccak256("ONRE_WORKER_ROLE");
    bytes32 internal constant VAULT_ADMIN_ROLE = keccak256("ONRE_VAULT_ADMIN_ROLE");
    bytes32 internal constant PAUSER_ROLE = keccak256("ONRE_PAUSER_ROLE");
}
