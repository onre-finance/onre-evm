// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";

interface IOnReAccessControl is IAccessControl {
    event BossTransferStarted(address indexed currentBoss, address indexed pendingBoss);
    event BossTransferCancelled(address indexed currentBoss, address indexed cancelledPendingBoss);
    event BossTransferred(address indexed previousBoss, address indexed newBoss);

    function DEFAULT_ADMIN_ROLE() external pure returns (bytes32);
    function ADMIN_ROLE() external pure returns (bytes32);
    function WORKER_ROLE() external pure returns (bytes32);
    function UPGRADER_ROLE() external pure returns (bytes32);

    function boss() external view returns (address);
    function pendingBoss() external view returns (address);
    function beginBossTransfer(address newBoss) external;
    function cancelBossTransfer() external;
    function acceptBossTransfer() external;
}
