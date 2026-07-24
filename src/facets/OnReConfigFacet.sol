// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReConfig} from "../libraries/LibOnReConfig.sol";
import {LibOnReAppConfig} from "../libraries/LibOnReAppConfig.sol";
import {IOnReConfig} from "../interfaces/IOnReConfig.sol";

contract OnReConfigFacet is IOnReConfig {
    function registerOnReToken(address onReToken, address inventorySource) external override {
        LibOnReConfig.registerOnReToken(onReToken, inventorySource);
    }

    function setOnReTokenEnabled(address onReToken, bool enabled) external override {
        LibOnReConfig.setOnReTokenEnabled(onReToken, enabled);
    }

    function setOnReTokenInventorySource(address onReToken, address inventorySource) external override {
        LibOnReConfig.setOnReTokenInventorySource(onReToken, inventorySource);
    }

    function addExcludedSupplyAddress(address onReToken, address account) external override {
        LibOnReConfig.addExcludedSupplyAddress(onReToken, account);
    }

    function removeExcludedSupplyAddress(address onReToken, address account) external override {
        LibOnReConfig.removeExcludedSupplyAddress(onReToken, account);
    }

    function addApprover(address approver) external override {
        LibOnReAppConfig.addApprover(approver);
    }

    function removeApprover(address approver) external override {
        LibOnReAppConfig.removeApprover(approver);
    }

    function setKillSwitch(bool killed) external override {
        LibOnReAppConfig.setKillSwitch(killed);
    }
}
