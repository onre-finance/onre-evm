// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

interface IDiamondCut {
    enum FacetCutAction {
        Add,
        Replace,
        Remove
    }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    event DiamondCut(FacetCut[] diamondCut, address init, bytes initCalldata);

    function diamondCut(FacetCut[] calldata cut, address init, bytes calldata initCalldata) external;
}
