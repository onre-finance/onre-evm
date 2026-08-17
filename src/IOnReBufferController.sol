// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @notice Receives atomic OnRe-token supply-change notifications.
interface IOnReBufferController {
    function onBeforeSupplyChange(uint256 amount, bool isMint) external;
}
