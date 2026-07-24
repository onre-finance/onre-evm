// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {OnReDiamond} from "../src/OnReDiamond.sol";
import {OnReDiamondInit} from "../src/diamond/OnReDiamondInit.sol";
import {IDiamondCut} from "../src/diamond/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/diamond/interfaces/IDiamondLoupe.sol";
import {LibDiamond} from "../src/diamond/libraries/LibDiamond.sol";
import {LibOnReSelectors} from "../src/diamond/libraries/LibOnReSelectors.sol";
import {LibOnReStorage} from "../src/diamond/libraries/LibOnReStorage.sol";
import {IOnReApp} from "../src/interfaces/IOnReApp.sol";
import {IOnReAppErrors} from "../src/interfaces/IOnReAppErrors.sol";
import {IOnReAccessControl} from "../src/interfaces/IOnReAccessControl.sol";
import {IOnReConfig} from "../src/interfaces/IOnReConfig.sol";
import {IOnReMarketStats} from "../src/interfaces/IOnReMarketStats.sol";
import {OnReTypes} from "../src/types/OnReTypes.sol";
import {OnReDiamondTestHelper} from "./helpers/OnReDiamondTestHelper.sol";

contract OnReDiamondTest is Test, OnReDiamondTestHelper {
    address private boss = makeAddr("boss");
    address private admin = makeAddr("admin");
    address private worker = makeAddr("worker");
    address private upgrader = makeAddr("upgrader");
    address private other = makeAddr("other");
    IOnReApp private app;

    function setUp() public {
        OnReTypes.InitializeParams memory params = OnReTypes.InitializeParams({
            boss: boss, admin: admin, worker: worker, upgrader: upgrader, approvers: new address[](0)
        });
        app = _deployDiamondApp(params);
    }

    function test_AtomicDeploymentInstallsStandardAndApplicationFacets() public view {
        IDiamondLoupe loupe = IDiamondLoupe(address(app));
        assertEq(loupe.facetAddresses().length, 11);
        assertEq(loupe.facets().length, 11);
        assertTrue(loupe.facetAddress(IOnReConfig.registerOnReToken.selector) != address(0));
        assertTrue(loupe.facetAddress(IOnReMarketStats.marketStats.selector) != address(0));
        assertNotEq(
            loupe.facetAddress(IOnReConfig.registerOnReToken.selector),
            loupe.facetAddress(IOnReMarketStats.marketStats.selector)
        );
        assertEq(loupe.facetFunctionSelectors(loupe.facetAddress(IOnReMarketStats.marketStats.selector)).length, 1);

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
        bytes32 adminRole = app.ADMIN_ROLE();
        bytes32 workerRole = app.WORKER_ROLE();
        bytes32 upgraderRole = app.UPGRADER_ROLE();
        assertEq(defaultAdminRole, bytes32(0));
        assertEq(app.getRoleAdmin(adminRole), defaultAdminRole);
        assertEq(app.getRoleAdmin(workerRole), defaultAdminRole);
        assertEq(app.getRoleAdmin(upgraderRole), defaultAdminRole);
        assertTrue(app.hasRole(defaultAdminRole, boss));
        assertTrue(app.hasRole(adminRole, admin));
        assertTrue(app.hasRole(workerRole, worker));
        assertTrue(app.hasRole(upgraderRole, upgrader));
        assertFalse(app.hasRole(upgraderRole, boss));

        vm.expectEmit(true, true, true, true, address(app));
        emit IAccessControl.RoleGranted(adminRole, other, boss);
        vm.prank(boss);
        app.grantRole(adminRole, other);
        assertTrue(app.hasRole(adminRole, other));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, defaultAdminRole)
        );
        vm.prank(other);
        app.grantRole(workerRole, other);

        vm.expectRevert(IAccessControl.AccessControlBadConfirmation.selector);
        vm.prank(other);
        app.renounceRole(adminRole, boss);

        vm.expectEmit(true, true, true, true, address(app));
        emit IAccessControl.RoleRevoked(adminRole, other, other);
        vm.prank(other);
        app.renounceRole(adminRole, other);
        assertFalse(app.hasRole(adminRole, other));

        vm.prank(boss);
        app.grantRole(adminRole, other);
        vm.prank(boss);
        app.revokeRole(adminRole, other);
        assertFalse(app.hasRole(adminRole, other));

        vm.prank(boss);
        app.revokeRole(adminRole, other);
        assertFalse(app.hasRole(adminRole, other));

        bytes32 unsupportedRole = keccak256("unsupported");
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.UnsupportedRoleError.selector, unsupportedRole));
        vm.prank(boss);
        app.grantRole(unsupportedRole, other);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.UnsupportedRoleError.selector, unsupportedRole));
        vm.prank(boss);
        app.revokeRole(unsupportedRole, other);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.UnsupportedRoleError.selector, unsupportedRole));
        vm.prank(other);
        app.renounceRole(unsupportedRole, other);
    }

    function test_BossIsSingletonAndTransfersWithTwoStepAcceptance() public {
        bytes32 defaultAdminRole = app.DEFAULT_ADMIN_ROLE();
        bytes32 upgraderRole = app.UPGRADER_ROLE();
        address replacementBoss = makeAddr("replacementBoss");

        assertEq(app.boss(), boss);
        assertEq(app.pendingBoss(), address(0));

        vm.expectRevert(IOnReAppErrors.BossRoleManagedSeparatelyError.selector);
        vm.prank(boss);
        app.grantRole(defaultAdminRole, other);
        vm.expectRevert(IOnReAppErrors.BossRoleManagedSeparatelyError.selector);
        vm.prank(boss);
        app.revokeRole(defaultAdminRole, boss);
        vm.expectRevert(IOnReAppErrors.BossRoleManagedSeparatelyError.selector);
        vm.prank(boss);
        app.renounceRole(defaultAdminRole, boss);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.BossUpgraderRoleConflictError.selector, boss));
        vm.prank(boss);
        app.grantRole(upgraderRole, boss);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, defaultAdminRole)
        );
        vm.prank(other);
        app.beginBossTransfer(other);

        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        vm.prank(boss);
        app.beginBossTransfer(address(0));
        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        vm.prank(boss);
        app.beginBossTransfer(boss);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.BossUpgraderRoleConflictError.selector, upgrader));
        vm.prank(boss);
        app.beginBossTransfer(upgrader);

        vm.expectEmit(true, true, false, false, address(app));
        emit IOnReAccessControl.BossTransferStarted(boss, other);
        vm.prank(boss);
        app.beginBossTransfer(other);
        assertEq(app.pendingBoss(), other);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.BossUpgraderRoleConflictError.selector, other));
        vm.prank(boss);
        app.grantRole(upgraderRole, other);

        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        vm.prank(boss);
        app.beginBossTransfer(other);

        vm.expectEmit(true, true, false, false, address(app));
        emit IOnReAccessControl.BossTransferCancelled(boss, other);
        vm.expectEmit(true, true, false, false, address(app));
        emit IOnReAccessControl.BossTransferStarted(boss, replacementBoss);
        vm.prank(boss);
        app.beginBossTransfer(replacementBoss);
        assertEq(app.pendingBoss(), replacementBoss);

        vm.expectEmit(true, true, false, false, address(app));
        emit IOnReAccessControl.BossTransferCancelled(boss, replacementBoss);
        vm.prank(boss);
        app.cancelBossTransfer();
        assertEq(app.pendingBoss(), address(0));

        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        vm.prank(boss);
        app.cancelBossTransfer();

        vm.prank(boss);
        app.beginBossTransfer(other);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.NotPendingBossError.selector, replacementBoss));
        vm.prank(replacementBoss);
        app.acceptBossTransfer();

        vm.expectEmit(true, true, true, true, address(app));
        emit IAccessControl.RoleRevoked(defaultAdminRole, boss, other);
        vm.expectEmit(true, true, true, true, address(app));
        emit IAccessControl.RoleGranted(defaultAdminRole, other, other);
        vm.expectEmit(true, true, false, false, address(app));
        emit IOnReAccessControl.BossTransferred(boss, other);
        vm.prank(other);
        app.acceptBossTransfer();

        assertEq(app.boss(), other);
        assertEq(app.pendingBoss(), address(0));
        assertFalse(app.hasRole(defaultAdminRole, boss));
        assertTrue(app.hasRole(defaultAdminRole, other));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, boss, defaultAdminRole)
        );
        vm.prank(boss);
        app.beginBossTransfer(replacementBoss);
    }

    function test_DiamondCutIsUpgraderOnlyAndRejectsDuplicateSelector() public {
        DiamondTestFacetV1 v1 = new DiamondTestFacetV1();
        bytes4[] memory selectors = _singleSelector(DiamondTestFacetV1.version.selector);
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](1);
        cut[0] = IDiamondCut.FacetCut({
            facetAddress: address(v1), action: IDiamondCut.FacetCutAction.Add, functionSelectors: selectors
        });

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, app.UPGRADER_ROLE())
        );
        vm.prank(other);
        IDiamondCut(address(app)).diamondCut(cut, address(0), "");

        vm.prank(upgrader);
        IDiamondCut(address(app)).diamondCut(cut, address(0), "");

        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.FunctionAlreadyExists.selector, DiamondTestFacetV1.version.selector)
        );
        vm.prank(upgrader);
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
        vm.expectRevert(LibDiamond.EmptyFacetSelectors.selector);
        _rawCut(address(v1), IDiamondCut.FacetCutAction.Replace, new bytes4[](0), address(0), "");
        vm.expectRevert(LibDiamond.EmptyFacetSelectors.selector);
        _rawCut(address(0), IDiamondCut.FacetCutAction.Remove, new bytes4[](0), address(0), "");

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
        OnReTypes.InitializeParams memory params = _defaultParams(boss);

        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        _initializeOnly(address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        IDiamondCut.FacetCut[] memory emptyCut = new IDiamondCut.FacetCut[](0);
        params.admin = other;
        OnReDiamond separate = new OnReDiamond(emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));
        assertEq(address(separate).code.length > 0, true);
    }

    function test_InitializerRejectsInvalidAddressesAndApprovers() public {
        OnReDiamondInit init = new OnReDiamondInit();
        IDiamondCut.FacetCut[] memory emptyCut = new IDiamondCut.FacetCut[](0);
        OnReTypes.InitializeParams memory params = _defaultParams(boss);

        params.worker = address(0);
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        new OnReDiamond(emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.admin = address(0);
        params.worker = makeAddr("validWorker");
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        new OnReDiamond(emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.admin = admin;
        params.boss = address(0);
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        new OnReDiamond(emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.boss = boss;
        params.upgrader = address(0);
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        new OnReDiamond(emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.upgrader = boss;
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.BossUpgraderRoleConflictError.selector, boss));
        new OnReDiamond(emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.upgrader = upgrader;
        params.approvers = new address[](3);
        params.approvers[0] = makeAddr("approverA");
        params.approvers[1] = makeAddr("approverB");
        params.approvers[2] = makeAddr("approverC");
        vm.expectRevert(IOnReAppErrors.BothApproversFilledError.selector);
        new OnReDiamond(emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.approvers = new address[](1);
        params.approvers[0] = address(0);
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        new OnReDiamond(emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        address duplicateApprover = makeAddr("duplicateApprover");
        params.approvers = new address[](2);
        params.approvers[0] = duplicateApprover;
        params.approvers[1] = duplicateApprover;
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.ApproverAlreadyExistsError.selector, duplicateApprover));
        new OnReDiamond(emptyCut, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));
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
        address inventorySource = makeAddr("inventorySource");
        vm.prank(boss);
        app.registerOnReToken(address(token), inventorySource);

        StorageAwareMarketStatsFacet replacement = new StorageAwareMarketStatsFacet();
        _cut(
            address(replacement),
            IDiamondCut.FacetCutAction.Replace,
            IOnReMarketStats.marketStats.selector,
            address(0),
            ""
        );

        OnReTypes.MarketStats memory stats = app.marketStats(address(token));
        assertEq(stats.tvl, uint160(inventorySource));
        assertEq(stats.nav, 9);
    }

    function test_UpgraderRoleChangeChangesDiamondCutAuthority() public {
        bytes32 upgraderRole = app.UPGRADER_ROLE();
        vm.prank(boss);
        app.grantRole(upgraderRole, other);
        vm.prank(boss);
        app.revokeRole(upgraderRole, upgrader);

        DiamondTestFacetV1 v1 = new DiamondTestFacetV1();
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, upgrader, upgraderRole)
        );
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
        vm.prank(upgrader);
        IDiamondCut(address(app)).diamondCut(cut, address(0), "");
    }

    function test_UnknownSelectorReverts() public {
        bytes4 unknownSelector = bytes4(keccak256("unknown()"));
        vm.expectRevert(abi.encodeWithSelector(OnReDiamond.FunctionNotFound.selector, unknownSelector));
        IDiamondUnknown(address(app)).unknown();
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
        vm.prank(upgrader);
        IDiamondCut(address(app)).diamondCut(cut, init, initCalldata);
    }

    function _initializeOnly(address init, bytes memory initCalldata) private {
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](0);
        vm.prank(upgrader);
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

    function _defaultParams(address initialBoss) private returns (OnReTypes.InitializeParams memory params) {
        params = OnReTypes.InitializeParams({
            boss: initialBoss,
            admin: makeAddr("initAdmin"),
            worker: makeAddr("initWorker"),
            upgrader: makeAddr("initUpgrader"),
            approvers: new address[](0)
        });
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
        stats.tvl = uint160(config.inventorySource);
        stats.nav = config.decimals;
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
