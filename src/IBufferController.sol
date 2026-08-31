// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @notice Receives atomic managed-token supply-change notifications.
interface IBufferController {
    function onBeforeSupplyChange(uint256 amount, bool isMint) external;
}
