// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    ApproverAlreadyExistsError,
    BothApproversFilledError,
    NoChangeError,
    NotApproverError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
import {ApproverAdded, ApproverRemoved, KillSwitchSet} from "../types/OnReAppEvents.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";

/// @notice Permissioned-offer approvers and application emergency control.
library LibOnReAppConfig {
    function addApprover(address approver) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (approver == address(0)) revert ZeroAddressError();
        if (approver == LibOnReStorage.appStorage().approver1 || approver == LibOnReStorage.appStorage().approver2) {
            revert ApproverAlreadyExistsError(approver);
        }

        if (LibOnReStorage.appStorage().approver1 == address(0)) {
            LibOnReStorage.appStorage().approver1 = approver;
        } else if (LibOnReStorage.appStorage().approver2 == address(0)) {
            LibOnReStorage.appStorage().approver2 = approver;
        } else {
            revert BothApproversFilledError();
        }
        emit ApproverAdded(approver);
    }

    function removeApprover(address approver) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (approver == address(0)) revert ZeroAddressError();

        if (LibOnReStorage.appStorage().approver1 == approver) {
            LibOnReStorage.appStorage().approver1 = address(0);
        } else if (LibOnReStorage.appStorage().approver2 == approver) {
            LibOnReStorage.appStorage().approver2 = address(0);
        } else {
            revert NotApproverError(approver);
        }
        emit ApproverRemoved(approver);
    }

    function setKillSwitch(bool killed) internal {
        if (killed) {
            if (
                !LibOnReAccessControl.hasRole(LibOnReRoles.DEFAULT_ADMIN_ROLE, msg.sender)
                    && !LibOnReAccessControl.hasRole(LibOnReRoles.ADMIN_ROLE, msg.sender)
            ) {
                revert IAccessControl.AccessControlUnauthorizedAccount(msg.sender, LibOnReRoles.ADMIN_ROLE);
            }
        } else {
            LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        }
        if (LibOnReStorage.appStorage().isKilled == killed) revert NoChangeError();
        LibOnReStorage.appStorage().isKilled = killed;
        emit KillSwitchSet(killed);
    }
}
