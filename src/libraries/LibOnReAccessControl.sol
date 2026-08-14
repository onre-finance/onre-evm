// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {BossTransferCancelled, BossTransferStarted, BossTransferred} from "../types/OnReAppEvents.sol";
import {
    BossRoleManagedSeparatelyError,
    NoChangeError,
    NotPendingBossError,
    UnsupportedRoleError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
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

    function _accessControlStorage() internal pure returns (AccessControlStorage storage s) {
        bytes32 position = ACCESS_CONTROL_STORAGE_POSITION;
        // solhint-disable-next-line no-inline-assembly
        assembly ("memory-safe") {
            s.slot := position
        }
    }

    function _hasRole(bytes32 role, address account) internal view returns (bool) {
        return _accessControlStorage().roles[role].hasRole[account];
    }

    function _checkRole(bytes32 role) internal view {
        _checkRole(role, msg.sender);
    }

    function _checkRole(bytes32 role, address account) internal view {
        if (!_hasRole(role, account)) {
            revert IAccessControl.AccessControlUnauthorizedAccount(account, role);
        }
    }

    function _getRoleAdmin(bytes32 role) internal view returns (bytes32) {
        return _accessControlStorage().roles[role].adminRole;
    }

    function _boss() internal view returns (address) {
        return _accessControlStorage().boss;
    }

    function _pendingBoss() internal view returns (address) {
        return _accessControlStorage().pendingBoss;
    }

    function _grantRole(bytes32 role, address account) internal {
        _requireSupportedRole(role);
        _requireNonBossRole(role);
        _checkRole(_getRoleAdmin(role));
        _grantRoleUnchecked(role, account);
    }

    function _revokeRole(bytes32 role, address account) internal {
        _requireSupportedRole(role);
        _requireNonBossRole(role);
        _checkRole(_getRoleAdmin(role));
        _revokeRoleUnchecked(role, account);
    }

    function _renounceRole(bytes32 role, address callerConfirmation) internal {
        _requireSupportedRole(role);
        _requireNonBossRole(role);
        if (callerConfirmation != msg.sender) {
            revert IAccessControl.AccessControlBadConfirmation();
        }
        _revokeRoleUnchecked(role, callerConfirmation);
    }

    function _initialize(address initialBoss, address admin, address worker, address upgrader) internal {
        _accessControlStorage().boss = initialBoss;
        _grantRoleUnchecked(LibOnReRoles.DEFAULT_ADMIN_ROLE, initialBoss);
        _grantRoleUnchecked(LibOnReRoles.ADMIN_ROLE, admin);
        _grantRoleUnchecked(LibOnReRoles.WORKER_ROLE, worker);
        _grantRoleUnchecked(LibOnReRoles.UPGRADER_ROLE, upgrader);
    }

    function _beginBossTransfer(address newBoss) internal {
        _checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (newBoss == address(0)) revert ZeroAddressError();

        AccessControlStorage storage s = _accessControlStorage();
        if (newBoss == s.boss || newBoss == s.pendingBoss) revert NoChangeError();

        address previousPendingBoss = s.pendingBoss;
        if (previousPendingBoss != address(0)) {
            emit BossTransferCancelled(s.boss, previousPendingBoss);
        }
        s.pendingBoss = newBoss;
        emit BossTransferStarted(s.boss, newBoss);
    }

    function _cancelBossTransfer() internal {
        _checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);

        AccessControlStorage storage s = _accessControlStorage();
        address cancelledPendingBoss = s.pendingBoss;
        if (cancelledPendingBoss == address(0)) revert NoChangeError();

        s.pendingBoss = address(0);
        emit BossTransferCancelled(s.boss, cancelledPendingBoss);
    }

    function _acceptBossTransfer() internal {
        AccessControlStorage storage s = _accessControlStorage();
        address newBoss = s.pendingBoss;
        if (msg.sender != newBoss) revert NotPendingBossError(msg.sender);

        address previousBoss = s.boss;
        s.pendingBoss = address(0);
        s.boss = newBoss;
        _revokeRoleUnchecked(LibOnReRoles.DEFAULT_ADMIN_ROLE, previousBoss);
        _grantRoleUnchecked(LibOnReRoles.DEFAULT_ADMIN_ROLE, newBoss);
        emit BossTransferred(previousBoss, newBoss);
    }

    function _requireSupportedRole(bytes32 role) private pure {
        if (!LibOnReRoles._isSupportedRole(role)) revert UnsupportedRoleError(role);
    }

    function _requireNonBossRole(bytes32 role) private pure {
        if (role == LibOnReRoles.DEFAULT_ADMIN_ROLE) {
            revert BossRoleManagedSeparatelyError();
        }
    }

    function _grantRoleUnchecked(bytes32 role, address account) internal returns (bool granted) {
        AccessControlStorage storage s = _accessControlStorage();
        if (!s.roles[role].hasRole[account]) {
            s.roles[role].hasRole[account] = true;
            emit IAccessControl.RoleGranted(role, account, msg.sender);
            granted = true;
        }
    }

    function _revokeRoleUnchecked(bytes32 role, address account) internal returns (bool revoked) {
        AccessControlStorage storage s = _accessControlStorage();
        if (s.roles[role].hasRole[account]) {
            s.roles[role].hasRole[account] = false;
            emit IAccessControl.RoleRevoked(role, account, msg.sender);
            revoked = true;
        }
    }
}
