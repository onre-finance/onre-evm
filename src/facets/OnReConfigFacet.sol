// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReConfig} from "../libraries/LibOnReConfig.sol";
import {LibOnReAppConfig} from "../libraries/LibOnReAppConfig.sol";

contract OnReConfigFacet {
    function registerOnReToken(address onReToken, address inventorySource) external {
        LibOnReConfig.registerOnReToken(onReToken, inventorySource);
    }

    function setOnReTokenEnabled(address onReToken, bool enabled) external {
        LibOnReConfig.setOnReTokenEnabled(onReToken, enabled);
    }

    function setOnReTokenInventorySource(address onReToken, address inventorySource) external {
        LibOnReConfig.setOnReTokenInventorySource(onReToken, inventorySource);
    }

    function addExcludedSupplyAddress(address onReToken, address account) external {
        LibOnReConfig.addExcludedSupplyAddress(onReToken, account);
    }

    function removeExcludedSupplyAddress(address onReToken, address account) external {
        LibOnReConfig.removeExcludedSupplyAddress(onReToken, account);
    }

    function addApprover(address approver) external {
        LibOnReAppConfig.addApprover(approver);
    }

    function removeApprover(address approver) external {
        LibOnReAppConfig.removeApprover(approver);
    }

    function setKillSwitch(bool killed) external {
        LibOnReAppConfig.setKillSwitch(killed);
    }
}
