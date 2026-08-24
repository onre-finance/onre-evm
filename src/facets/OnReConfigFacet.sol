// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReConfig} from "../libraries/LibOnReConfig.sol";
import {LibOnReAppConfig} from "../libraries/LibOnReAppConfig.sol";

contract OnReConfigFacet {
    function registerOnReToken(address onReToken) external {
        LibOnReConfig._registerOnReToken(onReToken);
    }

    function setOnReTokenEnabled(address onReToken, bool enabled) external {
        LibOnReConfig._setOnReTokenEnabled(onReToken, enabled);
    }

    function addExcludedSupplyAddress(address onReToken, address account) external {
        LibOnReConfig._addExcludedSupplyAddress(onReToken, account);
    }

    function removeExcludedSupplyAddress(address onReToken, address account) external {
        LibOnReConfig._removeExcludedSupplyAddress(onReToken, account);
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
