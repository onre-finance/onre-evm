// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {IOnReAccessControl} from "../interfaces/IOnReAccessControl.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {IDiamondCut} from "./interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "./interfaces/IDiamondLoupe.sol";
import {IDiamondOwnership} from "./interfaces/IDiamondOwnership.sol";
import {LibDiamond} from "./libraries/LibDiamond.sol";
import {LibOnReStorage} from "./libraries/LibOnReStorage.sol";
import {LibOnReAccessControl} from "../libraries/LibOnReAccessControl.sol";

contract OnReDiamondInit is IOnReAppEvents, IOnReAppErrors {
    function init(OnReTypes.InitializeParams calldata params) external {
        LibOnReStorage.AppStorage storage s = LibOnReStorage.appStorage();
        if (s.initialized) {
            revert NoChangeError();
        }
        if (params.admin == address(0) || params.worker == address(0)) {
            revert ZeroAddressError();
        }
        if (params.approvers.length > 2) {
            revert BothApproversFilledError();
        }

        LibOnReAccessControl.initialize(params.admin, params.worker);

        uint256 approverLength = params.approvers.length;
        for (uint256 i = 0; i < approverLength;) {
            _addApprover(s, params.approvers[i]);
            unchecked {
                ++i;
            }
        }

        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        ds.supportedInterfaces[type(IERC165).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondCut).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondLoupe).interfaceId] = true;
        ds.supportedInterfaces[type(IDiamondOwnership).interfaceId] = true;
        ds.supportedInterfaces[type(IAccessControl).interfaceId] = true;
        ds.supportedInterfaces[type(IOnReAccessControl).interfaceId] = true;
        s.initialized = true;
    }

    function _addApprover(LibOnReStorage.AppStorage storage s, address approver) private {
        if (approver == address(0)) {
            revert ZeroAddressError();
        }
        if (approver == s.approver1 || approver == s.approver2) {
            revert ApproverAlreadyExistsError(approver);
        }
        if (s.approver1 == address(0)) {
            s.approver1 = approver;
        } else if (s.approver2 == address(0)) {
            s.approver2 = approver;
        } else {
            revert BothApproversFilledError();
        }
        emit ApproverAdded(approver);
    }
}
