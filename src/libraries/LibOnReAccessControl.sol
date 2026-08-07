// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IOnReAccessControl} from "../interfaces/IOnReAccessControl.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";

/// @notice Diamond-native role storage with the OpenZeppelin IAccessControl surface.
/// @dev Uses a dedicated ERC-7201 namespace so every facet observes the same roles.
library LibOnReAccessControl {
    struct RoleData {
        mapping(address account => bool) hasRole;
        bytes32 adminRole;
    }

    /// @custom:storage-location erc7201:onre.storage.AccessControl
    struct AccessControlStorage {
        mapping(bytes32 role => RoleData) roles;
        address boss;
        address pendingBoss;
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

    function boss() internal view returns (address) {
        return accessControlStorage().boss;
    }

    function pendingBoss() internal view returns (address) {
        return accessControlStorage().pendingBoss;
    }

    function grantRole(bytes32 role, address account) internal {
        _requireSupportedRole(role);
        _requireNonBossRole(role);
        checkRole(getRoleAdmin(role));
        _grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) internal {
        _requireSupportedRole(role);
        _requireNonBossRole(role);
        checkRole(getRoleAdmin(role));
        _revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) internal {
        _requireSupportedRole(role);
        _requireNonBossRole(role);
        if (callerConfirmation != msg.sender) {
            revert IAccessControl.AccessControlBadConfirmation();
        }
        _revokeRole(role, callerConfirmation);
    }

    function initialize(address initialBoss, address admin, address worker, address upgrader) internal {
        accessControlStorage().boss = initialBoss;
        _grantRole(LibOnReRoles.DEFAULT_ADMIN_ROLE, initialBoss);
        _grantRole(LibOnReRoles.ADMIN_ROLE, admin);
        _grantRole(LibOnReRoles.WORKER_ROLE, worker);
        _grantRole(LibOnReRoles.UPGRADER_ROLE, upgrader);
    }

    function beginBossTransfer(address newBoss) internal {
        checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (newBoss == address(0)) revert IOnReAppErrors.ZeroAddressError();

        AccessControlStorage storage s = accessControlStorage();
        if (newBoss == s.boss || newBoss == s.pendingBoss) revert IOnReAppErrors.NoChangeError();

        address previousPendingBoss = s.pendingBoss;
        if (previousPendingBoss != address(0)) {
            emit IOnReAccessControl.BossTransferCancelled(s.boss, previousPendingBoss);
        }
        s.pendingBoss = newBoss;
        emit IOnReAccessControl.BossTransferStarted(s.boss, newBoss);
    }

    function cancelBossTransfer() internal {
        checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);

        AccessControlStorage storage s = accessControlStorage();
        address cancelledPendingBoss = s.pendingBoss;
        if (cancelledPendingBoss == address(0)) revert IOnReAppErrors.NoChangeError();

        s.pendingBoss = address(0);
        emit IOnReAccessControl.BossTransferCancelled(s.boss, cancelledPendingBoss);
    }

    function acceptBossTransfer() internal {
        AccessControlStorage storage s = accessControlStorage();
        address newBoss = s.pendingBoss;
        if (msg.sender != newBoss) revert IOnReAppErrors.NotPendingBossError(msg.sender);

        address previousBoss = s.boss;
        s.pendingBoss = address(0);
        s.boss = newBoss;
        _revokeRole(LibOnReRoles.DEFAULT_ADMIN_ROLE, previousBoss);
        _grantRole(LibOnReRoles.DEFAULT_ADMIN_ROLE, newBoss);
        emit IOnReAccessControl.BossTransferred(previousBoss, newBoss);
    }

    function _requireSupportedRole(bytes32 role) private pure {
        if (!LibOnReRoles.isSupportedRole(role)) revert IOnReAppErrors.UnsupportedRoleError(role);
    }

    function _requireNonBossRole(bytes32 role) private pure {
        if (role == LibOnReRoles.DEFAULT_ADMIN_ROLE) {
            revert IOnReAppErrors.BossRoleManagedSeparatelyError();
        }
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
