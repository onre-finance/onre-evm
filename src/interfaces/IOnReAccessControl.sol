// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IOnReAccessControl is IAccessControl {
    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);
    function CONFIG_ADMIN_ROLE() external pure returns (bytes32);
    function WORKER_ROLE() external pure returns (bytes32);
    function VAULT_ADMIN_ROLE() external pure returns (bytes32);
    function PAUSER_ROLE() external pure returns (bytes32);
}
