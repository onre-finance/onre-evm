// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReDiamond} from "../../src/OnReDiamond.sol";
import {OnReDiamondInit} from "../../src/diamond/OnReDiamondInit.sol";
import {DiamondCutFacet} from "../../src/diamond/facets/DiamondCutFacet.sol";
import {DiamondLoupeFacet} from "../../src/diamond/facets/DiamondLoupeFacet.sol";
import {IDiamondCut} from "../../src/diamond/interfaces/IDiamondCut.sol";
import {LibOnReSelectors} from "../../src/diamond/libraries/LibOnReSelectors.sol";
import {OnReConfigFacet} from "../../src/facets/OnReConfigFacet.sol";
import {OnReAccessControlFacet} from "../../src/facets/OnReAccessControlFacet.sol";
import {OnReConfigurableVaultFacet} from "../../src/facets/OnReConfigurableVaultFacet.sol";
import {OnReMarketStatsFacet} from "../../src/facets/OnReMarketStatsFacet.sol";
import {OnReOfferFacet} from "../../src/facets/OnReOfferFacet.sol";
import {OnRePricerFacet} from "../../src/facets/OnRePricerFacet.sol";
import {OnReQuoterFacet} from "../../src/facets/OnReQuoterFacet.sol";
import {OnReFulfillmentFacet} from "../../src/facets/OnReFulfillmentFacet.sol";
import {OnReViewFacet} from "../../src/facets/OnReViewFacet.sol";
import {IOnReApp} from "../../src/interfaces/IOnReApp.sol";
import {OnReTypes} from "../../src/types/OnReTypes.sol";

abstract contract OnReDiamondTestHelper {
    function _deployDiamondApp(OnReTypes.InitializeParams memory params) internal returns (IOnReApp app) {
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](11);
        cut[0] = _facetCut(address(new DiamondCutFacet()), LibOnReSelectors.diamondCut());
        cut[1] = _facetCut(address(new DiamondLoupeFacet()), LibOnReSelectors.diamondLoupe());
        cut[2] = _facetCut(address(new OnReAccessControlFacet()), LibOnReSelectors.accessControl());
        cut[3] = _facetCut(address(new OnReConfigFacet()), LibOnReSelectors.config());
        cut[4] = _facetCut(address(new OnRePricerFacet()), LibOnReSelectors.pricer());
        cut[5] = _facetCut(address(new OnReQuoterFacet()), LibOnReSelectors.quoter());
        cut[6] = _facetCut(address(new OnReOfferFacet()), LibOnReSelectors.offer());
        cut[7] = _facetCut(address(new OnReFulfillmentFacet()), LibOnReSelectors.fulfillment());
        cut[8] = _facetCut(address(new OnReViewFacet()), LibOnReSelectors.viewFunctions());
        cut[9] = _facetCut(address(new OnReConfigurableVaultFacet()), LibOnReSelectors.configurableVault());
        cut[10] = _facetCut(address(new OnReMarketStatsFacet()), LibOnReSelectors.marketStats());

        OnReDiamondInit init = new OnReDiamondInit();
        OnReDiamond diamond = new OnReDiamond(cut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));
        app = IOnReApp(address(diamond));
    }

    function _facetCut(address facetAddress, bytes4[] memory selectors)
        private
        pure
        returns (IDiamondCut.FacetCut memory)
    {
        return IDiamondCut.FacetCut({
            facetAddress: facetAddress, action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });
    }
}

contract OnReDiamondTestDeployer is OnReDiamondTestHelper {
    function deploy(OnReTypes.InitializeParams memory params) external returns (IOnReApp) {
        return _deployDiamondApp(params);
    }
}
