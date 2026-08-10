// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReDiamondInit} from "../../src/diamond/OnReDiamondInit.sol";
import {IDiamondCut} from "../../src/diamond/contracts/interfaces/IDiamondCut.sol";
import {DiamondProxy} from "../../src/generated/DiamondProxy.sol";
import {LibDiamondHelper} from "../../src/generated/LibDiamondHelper.sol";
import {IDiamondProxy} from "../../src/generated/IDiamondProxy.sol";
import {InitializeParams} from "../../src/types/OnReTypes.sol";

/// @notice Deploys the app exactly the way `gemforge deploy` does.
/// @dev The proxy constructor installs the core facets and grants the caller a
/// bootstrap UPGRADER_ROLE; the single follow-up cut installs every application
/// facet and runs the initializer, which hands that role over. Facet selectors
/// come from `LibDiamondHelper`, which Gemforge regenerates from the facet ABIs
/// on every `gemforge build`, so tests exercise the deployed selector set rather
/// than a hand-maintained copy of it.
abstract contract OnReDiamondTestHelper {
    function _deployDiamondApp(InitializeParams memory params) internal returns (IDiamondProxy app) {
        DiamondProxy diamond = new DiamondProxy(address(this));

        IDiamondCut.FacetCut[] memory cut = LibDiamondHelper.deployFacetsAndGetCuts(address(diamond));
        OnReDiamondInit init = new OnReDiamondInit();
        IDiamondCut(address(diamond)).diamondCut(cut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        app = IDiamondProxy(address(diamond));
    }
}

contract OnReDiamondTestDeployer is OnReDiamondTestHelper {
    function deploy(InitializeParams memory params) external returns (IDiamondProxy) {
        return _deployDiamondApp(params);
    }
}
