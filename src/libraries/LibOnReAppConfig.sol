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
    function _addApprover(address approver) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (approver == address(0)) revert ZeroAddressError();
        if (approver == LibOnReStorage._appStorage().approver1 || approver == LibOnReStorage._appStorage().approver2) {
            revert ApproverAlreadyExistsError(approver);
        }

        if (LibOnReStorage._appStorage().approver1 == address(0)) {
            LibOnReStorage._appStorage().approver1 = approver;
        } else if (LibOnReStorage._appStorage().approver2 == address(0)) {
            LibOnReStorage._appStorage().approver2 = approver;
        } else {
            revert BothApproversFilledError();
        }
        emit ApproverAdded(approver);
    }

    function _removeApprover(address approver) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (approver == address(0)) revert ZeroAddressError();

        if (LibOnReStorage._appStorage().approver1 == approver) {
            LibOnReStorage._appStorage().approver1 = address(0);
        } else if (LibOnReStorage._appStorage().approver2 == approver) {
            LibOnReStorage._appStorage().approver2 = address(0);
        } else {
            revert NotApproverError(approver);
        }
        emit ApproverRemoved(approver);
    }

    function _setKillSwitch(bool killed) internal {
        if (killed) {
            if (
                !LibOnReAccessControl._hasRole(LibOnReRoles.DEFAULT_ADMIN_ROLE, msg.sender)
                    && !LibOnReAccessControl._hasRole(LibOnReRoles.ADMIN_ROLE, msg.sender)
            ) {
                revert IAccessControl.AccessControlUnauthorizedAccount(msg.sender, LibOnReRoles.ADMIN_ROLE);
            }
        } else {
            LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        }
        if (LibOnReStorage._appStorage().isKilled == killed) revert NoChangeError();
        LibOnReStorage._appStorage().isKilled = killed;
        emit KillSwitchSet(killed);
    }
}
