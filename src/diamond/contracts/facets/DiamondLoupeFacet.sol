// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC165} from "../interfaces/IERC165.sol";
import {IDiamondLoupe} from "../interfaces/IDiamondLoupe.sol";
import {LibDiamond} from "../libraries/LibDiamond.sol";

contract DiamondLoupeFacet is IDiamondLoupe, IERC165 {
    function facets() external view override returns (Facet[] memory facets_) {
        LibDiamond.DiamondStorage storage ds = LibDiamond.diamondStorage();
        uint256 facetLength = ds.facetAddresses.length;
        facets_ = new Facet[](facetLength);
        for (uint256 i = 0; i < facetLength;) {
            address facet = ds.facetAddresses[i];
            facets_[i] =
                Facet({facetAddress: facet, functionSelectors: ds.facetToFunctionSelectors[facet].functionSelectors});
            unchecked {
                ++i;
            }
        }
    }

    function facetFunctionSelectors(address facet) external view override returns (bytes4[] memory selectors) {
        return LibDiamond.diamondStorage().facetToFunctionSelectors[facet].functionSelectors;
    }

    function facetAddresses() external view override returns (address[] memory facetAddresses_) {
        return LibDiamond.diamondStorage().facetAddresses;
    }

    function facetAddress(bytes4 functionSelector) external view override returns (address facetAddress_) {
        return LibDiamond.diamondStorage().selectorToFacetAndPosition[functionSelector].facetAddress;
    }

    function supportsInterface(bytes4 interfaceId) external view override returns (bool) {
        return LibDiamond.diamondStorage().supportedInterfaces[interfaceId];
    }
}
