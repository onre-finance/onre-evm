// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

interface IDiamondOwnership {
    event OwnershipTransferred(address indexed previousOwner, address indexed newOwner);

    function owner() external view returns (address);
    function transferOwnership(address newOwner) external;
}
