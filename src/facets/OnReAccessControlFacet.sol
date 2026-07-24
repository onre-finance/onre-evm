// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReAccessControl} from "../libraries/LibOnReAccessControl.sol";
import {LibOnReRoles} from "../libraries/LibOnReRoles.sol";
import {IOnReAccessControl} from "../interfaces/IOnReAccessControl.sol";

contract OnReAccessControlFacet is IOnReAccessControl {
    function hasRole(bytes32 role, address account) external view returns (bool) {
        return LibOnReAccessControl.hasRole(role, account);
    }

    function getRoleAdmin(bytes32 role) external view returns (bytes32) {
        return LibOnReAccessControl.getRoleAdmin(role);
    }

    function grantRole(bytes32 role, address account) external {
        LibOnReAccessControl.grantRole(role, account);
    }

    function revokeRole(bytes32 role, address account) external {
        LibOnReAccessControl.revokeRole(role, account);
    }

    function renounceRole(bytes32 role, address callerConfirmation) external {
        LibOnReAccessControl.renounceRole(role, callerConfirmation);
    }

    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32) {
        return LibOnReRoles.DEFAULT_ADMIN_ROLE;
    }

    function CONFIG_ADMIN_ROLE() external pure returns (bytes32) {
        return LibOnReRoles.CONFIG_ADMIN_ROLE;
    }

    function WORKER_ROLE() external pure returns (bytes32) {
        return LibOnReRoles.WORKER_ROLE;
    }

    function VAULT_ADMIN_ROLE() external pure returns (bytes32) {
        return LibOnReRoles.VAULT_ADMIN_ROLE;
    }

    function PAUSER_ROLE() external pure returns (bytes32) {
        return LibOnReRoles.PAUSER_ROLE;
    }
}
