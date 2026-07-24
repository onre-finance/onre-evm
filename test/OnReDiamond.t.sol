// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {OnReDiamond} from "../src/OnReDiamond.sol";
import {OnReDiamondInit} from "../src/diamond/OnReDiamondInit.sol";
import {IDiamondCut} from "../src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/diamond/interfaces/IDiamondLoupe.sol";
import {IDiamondOwnership} from "../src/diamond/interfaces/IDiamondOwnership.sol";
import {LibDiamond} from "../src/diamond/libraries/LibDiamond.sol";
import {LibOnReSelectors} from "../src/diamond/libraries/LibOnReSelectors.sol";
import {LibOnReStorage} from "../src/diamond/libraries/LibOnReStorage.sol";
import {IOnReApp} from "../src/interfaces/IOnReApp.sol";
import {IOnReAppErrors} from "../src/interfaces/IOnReAppErrors.sol";
import {IOnReAccessControl} from "../src/interfaces/IOnReAccessControl.sol";
import {OnReTypes} from "../src/types/OnReTypes.sol";
import {OnReDiamondTestHelper} from "./helpers/OnReDiamondTestHelper.sol";

contract OnReDiamondTest is Test, OnReDiamondTestHelper {
    address private owner = makeAddr("owner");
    address private other = makeAddr("other");
    IOnReApp private app;

    function setUp() public {
        OnReTypes.InitializeParams memory params =
            OnReTypes.InitializeParams({admin: owner, worker: makeAddr("worker"), approvers: new address[](0)});
        app = _deployDiamondApp(params);
    }

    function test_AtomicDeploymentInstallsStandardAndApplicationFacets() public view {
        IDiamondLoupe loupe = IDiamondLoupe(address(app));
        assertEq(loupe.facetAddresses().length, 12);
        assertEq(loupe.facets().length, 12);
        assertTrue(loupe.facetAddress(IOnReApp.registerOnReToken.selector) != address(0));
        assertTrue(loupe.facetAddress(IOnReApp.marketStats.selector) != address(0));
        assertNotEq(
            loupe.facetAddress(IOnReApp.registerOnReToken.selector), loupe.facetAddress(IOnReApp.marketStats.selector)
        );
        assertEq(loupe.facetFunctionSelectors(loupe.facetAddress(IOnReApp.marketStats.selector)).length, 1);

        _assertSelectorsOnSingleFacet(loupe, LibOnReSelectors.config());
        _assertSelectorsOnSingleFacet(loupe, LibOnReSelectors.accessControl());
        _assertSelectorsOnSingleFacet(loupe, LibOnReSelectors.pricer());
        _assertSelectorsOnSingleFacet(loupe, LibOnReSelectors.quoter());
        _assertSelectorsOnSingleFacet(loupe, LibOnReSelectors.offer());
        _assertSelectorsOnSingleFacet(loupe, LibOnReSelectors.fulfillment());
        _assertSelectorsOnSingleFacet(loupe, LibOnReSelectors.viewFunctions());
        _assertSelectorsOnSingleFacet(loupe, LibOnReSelectors.configurableVault());

        IERC165 erc165 = IERC165(address(app));
        assertTrue(erc165.supportsInterface(type(IERC165).interfaceId));
        assertTrue(erc165.supportsInterface(type(IDiamondCut).interfaceId));
        assertTrue(erc165.supportsInterface(type(IDiamondLoupe).interfaceId));
        assertTrue(erc165.supportsInterface(type(IDiamondOwnership).interfaceId));
        assertTrue(erc165.supportsInterface(type(IAccessControl).interfaceId));
        assertTrue(erc165.supportsInterface(type(IOnReAccessControl).interfaceId));
        // The mutable application ABI is discovered through the loupe. Only stable
        // standard interfaces are advertised through ERC-165.
        assertFalse(erc165.supportsInterface(type(IOnReApp).interfaceId));
        assertFalse(erc165.supportsInterface(0xffffffff));
    }

    function test_DiamondCutAddsReplacesAndRemovesSelector() public {
        DiamondTestFacetV1 v1 = new DiamondTestFacetV1();
        _cut(address(v1), IDiamondCut.FacetCutAction.Add, DiamondTestFacetV1.version.selector, address(0), "");
        assertEq(DiamondTestFacetV1(address(app)).version(), 1);

        DiamondTestFacetV2 v2 = new DiamondTestFacetV2();
        _cut(address(v2), IDiamondCut.FacetCutAction.Replace, DiamondTestFacetV2.version.selector, address(0), "");
        assertEq(DiamondTestFacetV2(address(app)).version(), 2);
        assertEq(IDiamondLoupe(address(app)).facetAddress(DiamondTestFacetV2.version.selector), address(v2));

        _cut(address(0), IDiamondCut.FacetCutAction.Remove, DiamondTestFacetV2.version.selector, address(0), "");
        vm.expectRevert(
            abi.encodeWithSelector(OnReDiamond.FunctionNotFound.selector, DiamondTestFacetV2.version.selector)
        );
        DiamondTestFacetV2(address(app)).version();
    }

    function test_AccessControlGrantRevokeAndRenounceUsesOpenZeppelinSemantics() public {
        bytes32 defaultAdminRole = app.DEFAULT_ADMIN_ROLE();
        bytes32 configAdminRole = app.CONFIG_ADMIN_ROLE();
        bytes32 pauserRole = app.PAUSER_ROLE();
        assertEq(defaultAdminRole, bytes32(0));
        assertEq(app.getRoleAdmin(configAdminRole), defaultAdminRole);

        vm.expectEmit(true, true, true, true, address(app));
        emit IAccessControl.RoleGranted(configAdminRole, other, owner);
        vm.prank(owner);
        app.grantRole(configAdminRole, other);
        assertTrue(app.hasRole(configAdminRole, other));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, defaultAdminRole)
        );
        vm.prank(other);
        app.grantRole(pauserRole, other);

        vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        vm.prank(other);
        app.renounceRole(configAdminRole, owner);

        vm.expectEmit(true, true, true, true, address(app));
        emit IAccessControl.RoleRevoked(configAdminRole, other, other);
        vm.prank(other);
        app.renounceRole(configAdminRole, other);
        assertFalse(app.hasRole(configAdminRole, other));

        vm.prank(owner);
        app.grantRole(configAdminRole, other);
        vm.prank(owner);
        app.revokeRole(configAdminRole, other);
        assertFalse(app.hasRole(configAdminRole, other));

        vm.prank(owner);
        app.revokeRole(configAdminRole, other);
        assertFalse(app.hasRole(configAdminRole, other));
    }

    function test_DiamondCutIsOwnerOnlyAndRejectsDuplicateSelector() public {
        DiamondTestFacetV1 v1 = new DiamondTestFacetV1();
        bytes4[] memory selectors = _singleSelector(DiamondTestFacetV1.version.selector);
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(v1), action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });

        vm.expectRevert(abi.encodeWithSelector(LibDiamond.UnauthorizedDiamondOwner.selector, other));
        vm.prank(other);
        IDiamondCut(address(app)).diamondCut(cut, address(0), "");

        vm.prank(owner);
        IDiamondCut(address(app)).diamondCut(cut, address(0), "");

        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.FunctionAlreadyExists.selector, DiamondTestFacetV1.version.selector)
        );
        vm.prank(owner);
        IDiamondCut(address(app)).diamondCut(cut, address(0), "");
    }

    function test_FailedCutInitializerRollsBackSelectorAddition() public {
        DiamondTestFacetV1 v1 = new DiamondTestFacetV1();
        RevertingDiamondInit revertingInit = new RevertingDiamondInit();

        vm.expectRevert(RevertingDiamondInit.ExpectedRevert.selector);
        _cut(
            address(v1),
            IDiamondCut.FacetCutAction.Add,
            DiamondTestFacetV1.version.selector,
            address(revertingInit),
            abi.encodeCall(RevertingDiamondInit.init, ())
        );

        assertEq(IDiamondLoupe(address(app)).facetAddress(DiamondTestFacetV1.version.selector), address(0));
    }

    function test_DiamondCutValidatesFacetAndSelectorActions() public {
        DiamondTestFacetV1 v1 = new DiamondTestFacetV1();

        vm.expectRevert(LibDiamond.EmptyFacetSelectors.selector);
        _rawCut(address(v1), IDiamondCut.FacetCutAction.Add, new bytes4[](0), address(0), "");

        vm.expectRevert(LibDiamond.FacetAddressIsZero.selector);
        _cut(address(0), IDiamondCut.FacetCutAction.Add, DiamondTestFacetV1.version.selector, address(0), "");

        vm.expectRevert(abi.encodeWithSelector(LibDiamond.FacetHasNoCode.selector, other));
        _cut(other, IDiamondCut.FacetCutAction.Add, DiamondTestFacetV1.version.selector, address(0), "");

        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.FunctionDoesNotExist.selector, DiamondTestFacetV1.version.selector)
        );
        _cut(address(v1), IDiamondCut.FacetCutAction.Replace, DiamondTestFacetV1.version.selector, address(0), "");

        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.FunctionDoesNotExist.selector, DiamondTestFacetV1.version.selector)
        );
        _cut(address(0), IDiamondCut.FacetCutAction.Remove, DiamondTestFacetV1.version.selector, address(0), "");

        _cut(address(v1), IDiamondCut.FacetCutAction.Add, DiamondTestFacetV1.version.selector, address(0), "");

        vm.expectRevert(
            abi.encodeWithSelector(
                LibDiamond.FunctionAlreadyUsesFacet.selector, DiamondTestFacetV1.version.selector, address(v1)
            )
        );
        _cut(address(v1), IDiamondCut.FacetCutAction.Replace, DiamondTestFacetV1.version.selector, address(0), "");

        vm.expectRevert(abi.encodeWithSelector(LibDiamond.RemoveFacetAddressMustBeZero.selector, address(v1)));
        _cut(address(v1), IDiamondCut.FacetCutAction.Remove, DiamondTestFacetV1.version.selector, address(0), "");
    }

    function test_DiamondCutValidatesInitializerPairAndCode() public {
        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.InvalidInitialization.selector, address(0), bytes("not-empty"))
        );
        _initializeOnly(address(0), "not-empty");

        RevertingDiamondInit init = new RevertingDiamondInit();
        vm.expectRevert(abi.encodeWithSelector(LibDiamond.InvalidInitialization.selector, address(init), bytes("")));
        _initializeOnly(address(init), "");

        vm.expectRevert(abi.encodeWithSelector(LibDiamond.FacetHasNoCode.selector, other));
        _initializeOnly(other, hex"01");
    }

    function test_InitializerIsOneTimeAndAllowsSeparateApplicationAdmin() public {
        OnReDiamondInit init = new OnReDiamondInit();
        OnReTypes.InitializeParams memory params = _defaultParams(owner);

        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        _initializeOnly(address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        IDiamondCut.FacetCut[] memory emptyCut = new IDiamondCut.FacetCut[](0);
        params.admin = other;
        OnReDiamond separate =
            new OnReDiamond(owner, emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));
        assertEq(address(separate).code.length > 0, true);
    }

    function test_RemovingNonLastSelectorsAndFacetsPreservesLoupeBookkeeping() public {
        DiamondMultiSelectorFacet multi = new DiamondMultiSelectorFacet();
        bytes4[] memory multiSelectors = new bytes4[](2);
        multiSelectors[0] = DiamondMultiSelectorFacet.first.selector;
        multiSelectors[1] = DiamondMultiSelectorFacet.second.selector;
        _rawCut(address(multi), IDiamondCut.FacetCutAction.Add, multiSelectors, address(0), "");

        DiamondTestFacetV1 trailingFacet = new DiamondTestFacetV1();
        _cut(
            address(trailingFacet), IDiamondCut.FacetCutAction.Add, DiamondTestFacetV1.version.selector, address(0), ""
        );

        _cut(address(0), IDiamondCut.FacetCutAction.Remove, DiamondMultiSelectorFacet.first.selector, address(0), "");
        assertEq(DiamondMultiSelectorFacet(address(app)).second(), 2);
        assertEq(IDiamondLoupe(address(app)).facetAddress(DiamondMultiSelectorFacet.second.selector), address(multi));

        _cut(address(0), IDiamondCut.FacetCutAction.Remove, DiamondMultiSelectorFacet.second.selector, address(0), "");
        assertEq(DiamondTestFacetV1(address(app)).version(), 1);
        assertEq(IDiamondLoupe(address(app)).facetAddress(DiamondTestFacetV1.version.selector), address(trailingFacet));
    }

    function test_ReplacementFacetReadsExistingNamespacedApplicationState() public {
        NineDecimalToken token = new NineDecimalToken();
        vm.prank(owner);
        app.registerOnReToken(address(token), 123, 456);

        StorageAwareMarketStatsFacet replacement = new StorageAwareMarketStatsFacet();
        _cut(address(replacement), IDiamondCut.FacetCutAction.Replace, IOnReApp.marketStats.selector, address(0), "");

        OnReTypes.MarketStats memory stats = app.marketStats(address(token));
        assertEq(stats.tvl, 123);
        assertEq(stats.nav, 456);
    }

    function test_OwnershipTransferChangesDiamondCutAuthority() public {
        vm.expectEmit(true, true, false, false, address(app));
        emit IDiamondOwnership.OwnershipTransferred(owner, other);
        vm.prank(owner);
        IDiamondOwnership(address(app)).transferOwnership(other);

        DiamondTestFacetV1 v1 = new DiamondTestFacetV1();
        vm.expectRevert(abi.encodeWithSelector(LibDiamond.UnauthorizedDiamondOwner.selector, owner));
        _cut(address(v1), IDiamondCut.FacetCutAction.Add, DiamondTestFacetV1.version.selector, address(0), "");

        bytes4[] memory selectors = _singleSelector(DiamondTestFacetV1.version.selector);
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(v1), action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });
        vm.prank(other);
        IDiamondCut(address(app)).diamondCut(cut, address(0), "");
        assertEq(DiamondTestFacetV1(address(app)).version(), 1);
    }

    function test_DiamondCutEmitsStandardEvent() public {
        DiamondTestFacetV1 v1 = new DiamondTestFacetV1();
        bytes4[] memory selectors = _singleSelector(DiamondTestFacetV1.version.selector);
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(v1), action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });

        vm.expectEmit(false, false, false, true, address(app));
        emit IDiamondCut.DiamondCut(cut, address(0), "");
        vm.prank(owner);
        IDiamondCut(address(app)).diamondCut(cut, address(0), "");
    }

    function test_OwnershipCannotBeTransferredToZero() public {
        vm.expectRevert(LibDiamond.ZeroAddressOwner.selector);
        vm.prank(owner);
        IDiamondOwnership(address(app)).transferOwnership(address(0));
    }

    function test_UnknownSelectorAndZeroOwnerRevert() public {
        bytes4 unknownSelector = bytes4(keccak256("unknown()"));
        vm.expectRevert(abi.encodeWithSelector(OnReDiamond.FunctionNotFound.selector, unknownSelector));
        IDiamondUnknown(address(app)).unknown();

        IDiamondCut.FacetCut[] memory emptyCut = new IDiamondCut.FacetCut[](0);
        vm.expectRevert(LibDiamond.ZeroAddressOwner.selector);
        new OnReDiamond(address(0), emptyCut, address(0), "");
    }

    function _cut(
        address facet,
        IDiamondCut.FacetCutAction action,
        bytes4 selector,
        address init,
        bytes memory initCalldata
    ) private {
        _rawCut(facet, action, _singleSelector(selector), init, initCalldata);
    }

    function _rawCut(
        address facet,
        IDiamondCut.FacetCutAction action,
        bytes4[] memory selectors,
        address init,
        bytes memory initCalldata
    ) private {
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({facetAddress: facet, action: action, functionSelectors: selectors});
        vm.prank(owner);
        IDiamondCut(address(app)).diamondCut(cut, init, initCalldata);
    }

    function _initializeOnly(address init, bytes memory initCalldata) private {
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](0);
        vm.prank(owner);
        IDiamondCut(address(app)).diamondCut(cut, init, initCalldata);
    }

    function _singleSelector(bytes4 selector) private pure returns (bytes4[] memory selectors) {
        selectors = new bytes4[](1);
        selectors[0] = selector;
    }

    function _assertSelectorsOnSingleFacet(IDiamondLoupe loupe, bytes4[] memory selectors) private view {
        address facet = loupe.facetAddress(selectors[0]);
        assertTrue(facet != address(0));
        assertEq(loupe.facetFunctionSelectors(facet).length, selectors.length);
        for (uint256 i; i < selectors.length; ++i) {
            assertEq(loupe.facetAddress(selectors[i]), facet);
        }
    }

    function _defaultParams(address admin) private returns (OnReTypes.InitializeParams memory params) {
        params = OnReTypes.InitializeParams({admin: admin, worker: makeAddr("initWorker"), approvers: new address[](0)});
    }
}

contract DiamondTestFacetV1 {
    function version() external pure returns (uint256) {
        return 1;
    }
}

contract DiamondTestFacetV2 {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract DiamondMultiSelectorFacet {
    function first() external pure returns (uint256) {
        return 1;
    }

    function second() external pure returns (uint256) {
        return 2;
    }
}

contract StorageAwareMarketStatsFacet {
    function marketStats(address token) external view returns (OnReTypes.MarketStats memory stats) {
        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[token];
        stats.tvl = config.maxSupply;
        stats.nav = config.maxMintAmount;
    }
}

contract NineDecimalToken {
    function decimals() external pure returns (uint8) {
        return 9;
    }
}

contract RevertingDiamondInit {
    error ExpectedRevert();

    function init() external pure {
        revert ExpectedRevert();
    }
}

interface IDiamondUnknown {
    function unknown() external;
}
