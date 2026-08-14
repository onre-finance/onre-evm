// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    ApproverAlreadyExistsError,
    BothApproversFilledError,
    NoChangeError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
import {ApproverAdded} from "../types/OnReAppEvents.sol";
import {InitializeParams} from "../types/OnReTypes.sol";
import {IDiamondCut} from "./contracts/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "./contracts/interfaces/IDiamondLoupe.sol";
import {LibDiamond} from "./contracts/libraries/LibDiamond.sol";
import {LibOnReStorage} from "./LibOnReStorage.sol";
import {LibOnReAccessControl} from "../libraries/LibOnReAccessControl.sol";
import {LibOnReRoles} from "../libraries/LibOnReRoles.sol";

contract OnReDiamondInit {
    function init(InitializeParams calldata params) external {
        LibOnReStorage.AppStorage storage s = LibOnReStorage._appStorage();
        if (s.initialized) {
            revert NoChangeError();
        }
        if (
            params.boss == address(0) || params.admin == address(0) || params.worker == address(0)
                || params.upgrader == address(0)
        ) {
            revert ZeroAddressError();
        }
        if (params.approvers.length > 2) {
            revert BothApproversFilledError();
        }

        LibOnReAccessControl._initialize(params.boss, params.admin, params.worker, params.upgrader);

        uint256 approverLength = params.approvers.length;
        for (uint256 i = 0; i < approverLength;) {
            _addApprover(s, params.approvers[i]);
            unchecked {
                ++i;
            }
        }

        LibDiamond.DiamondStorage storage ds = LibDiamond._diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IAccessControl).interfaceId] = true;
        s.initialized = true;

        _handOffBootstrapUpgrader(params.upgrader);
    }

    /// @notice Drops the deployer's temporary upgrade authority.
    /// @dev `DiamondProxy` grants UPGRADER_ROLE to its deployer so the very
    /// first `diamondCut` (the one carrying this initializer) can be signed by
    /// the deployment wallet. `init` runs inside that cut via delegatecall, so
    /// `msg.sender` is still that wallet. Once the configured upgrader holds
    /// the role, the bootstrap grant has to go, or every deployment would
    /// leave a hot key with permanent cut rights.
    function _handOffBootstrapUpgrader(address upgrader) private {
        if (msg.sender != upgrader) {
            LibOnReAccessControl._revokeRoleUnchecked(LibOnReRoles.UPGRADER_ROLE, msg.sender);
        }
    }

    function _addApprover(LibOnReStorage.AppStorage storage s, address approver) private {
        if (approver == address(0)) {
            revert ZeroAddressError();
        }
        // With at most two initializer approvers, a duplicate can only be the
        // first approver while the second slot is still empty.
        if (approver == s.approver1) {
            revert ApproverAlreadyExistsError(approver);
        }
        if (s.approver1 == address(0)) {
            s.approver1 = approver;
        } else {
            s.approver2 = approver;
        }
        emit ApproverAdded(approver);
    }
}
