// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

import {LibOnReAccessControl} from "../libraries/LibOnReAccessControl.sol";
import {LibOnReRoles} from "../libraries/LibOnReRoles.sol";

contract OnReAccessControlFacet is IAccessControl {
    function hasRole(bytes32 role, address account) external view override returns (bool) {
        return LibOnReAccessControl._hasRole(role, account);
    }

    function getRoleAdmin(bytes32 role) external view override returns (bytes32) {
        return LibOnReAccessControl._getRoleAdmin(role);
    }

    function grantRole(bytes32 role, address account) external override {
        LibOnReAccessControl._grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external override {
        LibOnReAccessControl._revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) external override {
        LibOnReAccessControl._renounceRole(role, callerConfirmation);
    }

    function boss() external view returns (address) {
        return LibOnReAccessControl._boss();
    }

    function pendingBoss() external view returns (address) {
        return LibOnReAccessControl._pendingBoss();
    }

    function beginBossTransfer(address newBoss) external {
        LibOnReAccessControl._beginBossTransfer(newBoss);
    }

    function cancelBossTransfer() external {
        LibOnReAccessControl._cancelBossTransfer();
    }

    function acceptBossTransfer() external {
        LibOnReAccessControl._acceptBossTransfer();
    }

    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32) {
        return LibOnReRoles.DEFAULT_ADMIN_ROLE;
    }

    function ADMIN_ROLE() external pure returns (bytes32) {
        return LibOnReRoles.ADMIN_ROLE;
    }

    function WORKER_ROLE() external pure returns (bytes32) {
        return LibOnReRoles.WORKER_ROLE;
    }

    function UPGRADER_ROLE() external pure returns (bytes32) {
        return LibOnReRoles.UPGRADER_ROLE;
    }
}
