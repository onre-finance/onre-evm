// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IDiamondCut} from "../interfaces/IDiamondCut.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

contract DiamondCutFacet is IDiamondCut {
    function diamondCut(FacetCut[] calldata cut, address init, bytes calldata initCalldata) external override {
        LibDiamond.enforceIsContractOwner();
        LibDiamond.diamondCut(cut, init, initCalldata);
    }
}
