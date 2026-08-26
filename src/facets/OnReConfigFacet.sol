// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReConfig} from "../libraries/LibOnReConfig.sol";
import {LibOnReAppConfig} from "../libraries/LibOnReAppConfig.sol";

contract OnReConfigFacet {
    function registerManagedToken(address managedToken) external {
        LibOnReConfig._registerManagedToken(managedToken);
    }

    function setManagedTokenEnabled(address managedToken, bool enabled) external {
        LibOnReConfig._setManagedTokenEnabled(managedToken, enabled);
    }

    function addExcludedSupplyAddress(address managedToken, address account) external {
        LibOnReConfig._addExcludedSupplyAddress(managedToken, account);
    }

    function removeExcludedSupplyAddress(address managedToken, address account) external {
        LibOnReConfig._removeExcludedSupplyAddress(managedToken, account);
    }

    function addApprover(address approver) external {
        LibOnReAppConfig._addApprover(approver);
    }

    function removeApprover(address approver) external {
        LibOnReAppConfig._removeApprover(approver);
    }

    function setKillSwitch(bool killed) external {
        LibOnReAppConfig._setKillSwitch(killed);
    }

    function setPermissionlessSettlementAccount(address account) external {
        LibOnReAppConfig._setPermissionlessSettlementAccount(account);
    }
}
