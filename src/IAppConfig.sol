// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

/// @notice Read-only access to application configuration.
interface IAppConfig {
    function appConfig() external view returns (bool isKilled, address approver1, address approver2);
}
