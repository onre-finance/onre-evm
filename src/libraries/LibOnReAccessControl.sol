// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";

/// @notice Diamond-native role storage with the OpenZeppelin IAccessControl surface.
/// @dev Uses a dedicated ERC-7201 namespace so every facet observes the same roles.
library LibOnReAccessControl {
    struct RoleData {
        mapping(address account => bool) hasRole;
        bytes32 adminRole;
    }

    struct AccessControlStorage {
        mapping(bytes32 role => RoleData) roles;
    }

    // keccak256(abi.encode(uint256(keccak256("onre.storage.AccessControl")) - 1)) & ~bytes32(uint256(0xff))
    bytes32 internal constant ACCESS_CONTROL_STORAGE_POSITION =
        0xc22d749a08533429f9f6342546255c4b448fe8fd084608530dff3c1a7e045100;

    function accessControlStorage() internal pure returns (AccessControlStorage storage s) {
        bytes32 position = ACCESS_CONTROL_STORAGE_POSITION;
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    function hasRole(bytes32 role, address account) internal view returns (bool) {
        return accessControlStorage().roles[role].hasRole[account];
    }

    function checkRole(bytes32 role) internal view {
        checkRole(role, msg.sender);
    }

    function checkRole(bytes32 role, address account) internal view {
        if (!hasRole(role, account)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(account, role);
        }
    }

    function getRoleAdmin(bytes32 role) internal view returns (bytes32) {
        return accessControlStorage().roles[role].adminRole;
    }

    function grantRole(bytes32 role, address account) internal {
        checkRole(getRoleAdmin(role));
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) internal {
        checkRole(getRoleAdmin(role));
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) internal {
        if (callerConfirmation != msg.sender) {
            revert IAccessControl.AccessControlBadConfirmation();
        }
        _revokeRole(role, callerConfirmation);
    }

    function initialize(address admin, address worker) internal {
        _grantRole(LibOnReRoles.DEFAULT_ADMIN_ROLE, admin);
        _grantRole(LibOnReRoles.CONFIG_ADMIN_ROLE, admin);
        _grantRole(LibOnReRoles.WORKER_ROLE, admin);
        _grantRole(LibOnReRoles.VAULT_ADMIN_ROLE, admin);
        _grantRole(LibOnReRoles.PAUSER_ROLE, admin);
        _grantRole(LibOnReRoles.WORKER_ROLE, worker);
    }

    function _grantRole(bytes32 role, address account) internal returns (bool granted) {
        AccessControlStorage storage s = accessControlStorage();
        if (!s.roles[role].hasRole[account]) {
            s.roles[role].hasRole[account] = true;
            emit IAccessControl.RoleGranted(role, account, msg.sender);
            return true;
        }
    }

    function _revokeRole(bytes32 role, address account) internal returns (bool revoked) {
        AccessControlStorage storage s = accessControlStorage();
        if (s.roles[role].hasRole[account]) {
            s.roles[role].hasRole[account] = false;
            emit IAccessControl.RoleRevoked(role, account, msg.sender);
            return true;
        }
    }
}
