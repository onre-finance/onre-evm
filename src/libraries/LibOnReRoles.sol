// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @notice Application roles include the authority used for Diamond upgrades.
library LibOnReRoles {
    bytes32 internal constant DEFAULT_ADMIN_ROLE = bytes32(0);
    bytes32 internal constant ADMIN_ROLE = keccak256("ONRE_ADMIN_ROLE");
    bytes32 internal constant WORKER_ROLE = keccak256("ONRE_WORKER_ROLE");
    bytes32 internal constant UPGRADER_ROLE = keccak256("ONRE_UPGRADER_ROLE");

    function _isSupportedRole(bytes32 role) internal pure returns (bool) {
        return role == DEFAULT_ADMIN_ROLE || role == ADMIN_ROLE || role == WORKER_ROLE || role == UPGRADER_ROLE;
    }
}
