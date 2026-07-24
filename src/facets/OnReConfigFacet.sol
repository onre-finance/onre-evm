// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReConfig} from "../libraries/LibOnReConfig.sol";

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
        LibOnReConfig.addApprover(approver);
    }

    function removeApprover(address approver) external {
        LibOnReConfig.removeApprover(approver);
    }

    function setKillSwitch(bool killed) external {
        LibOnReConfig.setKillSwitch(killed);
    }
}
