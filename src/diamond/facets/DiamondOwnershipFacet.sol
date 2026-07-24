// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IDiamondOwnership} from "../interfaces/IDiamondOwnership.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

contract DiamondOwnershipFacet is IDiamondOwnership {
    function owner() external view override returns (address) {
        return LibDiamond.contractOwner();
    }

    function transferOwnership(address newOwner) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.setContractOwner(newOwner);
    }
}
