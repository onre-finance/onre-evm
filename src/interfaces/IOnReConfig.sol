// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

interface IOnReConfig {
    function registerOnReToken(address onReToken, address inventorySource) external;
    function setOnReTokenEnabled(address onReToken, bool enabled) external;
    function setOnReTokenInventorySource(address onReToken, address inventorySource) external;
    function addExcludedSupplyAddress(address onReToken, address account) external;
    function removeExcludedSupplyAddress(address onReToken, address account) external;
    function addApprover(address approver) external;
    function removeApprover(address approver) external;
    function setKillSwitch(bool killed) external;
}
