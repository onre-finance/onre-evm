// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC165} from "@openzeppelin/contracts/utils/introspection/IERC165.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {OnReDiamondInit} from "../src/diamond/OnReDiamondInit.sol";
import {Diamond} from "../src/diamond/contracts/Diamond.sol";
import {DiamondCutFacet} from "../src/diamond/contracts/facets/DiamondCutFacet.sol";
import {IDiamondCut} from "../src/diamond/contracts/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../src/diamond/contracts/interfaces/IDiamondLoupe.sol";
import {LibDiamond} from "../src/diamond/contracts/libraries/LibDiamond.sol";
import {LibOnReStorage} from "../src/diamond/LibOnReStorage.sol";
import {DiamondProxy} from "../src/generated/DiamondProxy.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {
    ApproverAlreadyExistsError,
    BossRoleManagedSeparatelyError,
    BothApproversFilledError,
    NoChangeError,
    NotPendingBossError,
    UnsupportedRoleError,
    ZeroAddressError
} from "../src/types/OnReAppErrors.sol";
import {BossTransferCancelled, BossTransferStarted, BossTransferred} from "../src/types/OnReAppEvents.sol";
import {InitializeParams, MarketStats, OnReTokenConfig} from "../src/types/OnReTypes.sol";
import {OnReDiamondTestHelper} from "./helpers/OnReDiamondTestHelper.sol";

contract OnReDiamondTest is Test, OnReDiamondTestHelper {
    address private boss = makeAddr("boss");
    address private admin = makeAddr("admin");
    address private worker = makeAddr("worker");
    address private upgrader = makeAddr("upgrader");
    address private other = makeAddr("other");
    IDiamondProxy private app;

    function setUp() public {
        InitializeParams memory params = InitializeParams({
            boss: boss, admin: admin, worker: worker, upgrader: upgrader, approvers: new address[](0)
        });
        app = _deployDiamondApp(params);
    }

    function test_ProxyRejectsZeroBootstrapUpgrader() public {
        vm.expectRevert(DiamondProxy.BootstrapUpgraderIsZero.selector);
        new DiamondProxy(address(0));
    }

    function test_AtomicDeploymentInstallsStandardAndApplicationFacets() public view {
        IDiamondLoupe loupe = IDiamondLoupe(address(app));
        assertEq(loupe.facetAddresses().length, 11);
        assertEq(loupe.facets().length, 11);
        assertTrue(loupe.facetAddress(IDiamondProxy.registerOnReToken.selector) != address(0));
        assertTrue(loupe.facetAddress(IDiamondProxy.marketStats.selector) != address(0));
        assertNotEq(
            loupe.facetAddress(IDiamondProxy.registerOnReToken.selector),
            loupe.facetAddress(IDiamondProxy.marketStats.selector)
        );
        assertEq(loupe.facetFunctionSelectors(loupe.facetAddress(IDiamondProxy.marketStats.selector)).length, 1);

        IERC165 erc165 = IERC165(address(app));
        assertTrue(erc165.supportsInterface(type(IERC165).interfaceId));
        assertTrue(erc165.supportsInterface(type(IDiamondCut).interfaceId));
        assertTrue(erc165.supportsInterface(type(IDiamondLoupe).interfaceId));
        assertTrue(erc165.supportsInterface(type(IAccessControl).interfaceId));
        // The mutable application ABI is discovered through the loupe. Only stable
        // standard interfaces are advertised through ERC-165. The boss-transfer
        // surface is no longer advertised: it had no standard id, and a stored
        // ERC-165 flag cannot track a selector set that a cut can change.
        assertFalse(erc165.supportsInterface(type(IDiamondProxy).interfaceId));
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
        vm.expectRevert(abi.encodeWithSelector(Diamond.FunctionNotFound.selector, DiamondTestFacetV2.version.selector));
        DiamondTestFacetV2(address(app)).version();
    }

    function test_DiamondCutSelectorCannotBeRemovedButCanBeSafelyReplaced() public {
        IDiamondLoupe loupe = IDiamondLoupe(address(app));
        address originalFacet = loupe.facetAddress(IDiamondCut.diamondCut.selector);

        vm.expectRevert(
            abi.encodeWithSelector(LibDiamond.FunctionIsImmutable.selector, IDiamondCut.diamondCut.selector)
        );
        _cut(address(0), IDiamondCut.FacetCutAction.Remove, IDiamondCut.diamondCut.selector, address(0), "");
        assertEq(loupe.facetAddress(IDiamondCut.diamondCut.selector), originalFacet);

        DiamondCutFacet replacement = new DiamondCutFacet();
        _cut(address(replacement), IDiamondCut.FacetCutAction.Replace, IDiamondCut.diamondCut.selector, address(0), "");
        assertEq(loupe.facetAddress(IDiamondCut.diamondCut.selector), address(replacement));
        assertTrue(IERC165(address(app)).supportsInterface(type(IDiamondCut).interfaceId));

        DiamondTestFacetV1 v1 = new DiamondTestFacetV1();
        _cut(address(v1), IDiamondCut.FacetCutAction.Add, DiamondTestFacetV1.version.selector, address(0), "");
        assertEq(DiamondTestFacetV1(address(app)).version(), 1);
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
        vm.expectRevert(abi.encodeWithSelector(UnsupportedRoleError.selector, unsupportedRole));
        vm.prank(boss);
        app.grantRole(unsupportedRole, other);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedRoleError.selector, unsupportedRole));
        vm.prank(boss);
        app.revokeRole(unsupportedRole, other);
        vm.expectRevert(abi.encodeWithSelector(UnsupportedRoleError.selector, unsupportedRole));
        vm.prank(other);
        app.renounceRole(unsupportedRole, other);
    }

    function test_BossIsSingletonAndTransfersWithTwoStepAcceptance() public {
        bytes32 defaultAdminRole = app.DEFAULT_ADMIN_ROLE();
        bytes32 upgraderRole = app.UPGRADER_ROLE();
        address replacementBoss = makeAddr("replacementBoss");

        assertEq(app.boss(), boss);
        assertEq(app.pendingBoss(), address(0));

        vm.expectRevert(BossRoleManagedSeparatelyError.selector);
        vm.prank(boss);
        app.grantRole(defaultAdminRole, other);
        vm.expectRevert(BossRoleManagedSeparatelyError.selector);
        vm.prank(boss);
        app.revokeRole(defaultAdminRole, boss);
        vm.expectRevert(BossRoleManagedSeparatelyError.selector);
        vm.prank(boss);
        app.renounceRole(defaultAdminRole, boss);
        vm.prank(boss);
        app.grantRole(upgraderRole, boss);
        assertTrue(app.hasRole(upgraderRole, boss));

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, other, defaultAdminRole)
        );
        vm.prank(other);
        app.beginBossTransfer(other);

        vm.expectRevert(ZeroAddressError.selector);
        vm.prank(boss);
        app.beginBossTransfer(address(0));
        vm.expectRevert(NoChangeError.selector);
        vm.prank(boss);
        app.beginBossTransfer(boss);
        vm.prank(boss);
        app.beginBossTransfer(upgrader);
        assertEq(app.pendingBoss(), upgrader);
        vm.prank(boss);
        app.cancelBossTransfer();

        vm.expectEmit(true, true, false, false, address(app));
        emit BossTransferStarted(boss, other);
        vm.prank(boss);
        app.beginBossTransfer(other);
        assertEq(app.pendingBoss(), other);
        vm.prank(boss);
        app.grantRole(upgraderRole, other);
        assertTrue(app.hasRole(upgraderRole, other));

        vm.expectRevert(NoChangeError.selector);
        vm.prank(boss);
        app.beginBossTransfer(other);

        vm.expectEmit(true, true, false, false, address(app));
        emit BossTransferCancelled(boss, other);
        vm.expectEmit(true, true, false, false, address(app));
        emit BossTransferStarted(boss, replacementBoss);
        vm.prank(boss);
        app.beginBossTransfer(replacementBoss);
        assertEq(app.pendingBoss(), replacementBoss);

        vm.expectEmit(true, true, false, false, address(app));
        emit BossTransferCancelled(boss, replacementBoss);
        vm.prank(boss);
        app.cancelBossTransfer();
        assertEq(app.pendingBoss(), address(0));

        vm.expectRevert(NoChangeError.selector);
        vm.prank(boss);
        app.cancelBossTransfer();

        vm.prank(boss);
        app.beginBossTransfer(other);
        vm.expectRevert(abi.encodeWithSelector(NotPendingBossError.selector, replacementBoss));
        vm.prank(replacementBoss);
        app.acceptBossTransfer();

        vm.expectEmit(true, true, true, true, address(app));
        emit IAccessControl.RoleRevoked(defaultAdminRole, boss, other);
        vm.expectEmit(true, true, true, true, address(app));
        emit IAccessControl.RoleGranted(defaultAdminRole, other, other);
        vm.expectEmit(true, true, false, false, address(app));
        emit BossTransferred(boss, other);
        vm.prank(other);
        app.acceptBossTransfer();

        assertEq(app.boss(), other);
        assertEq(app.pendingBoss(), address(0));
        assertFalse(app.hasRole(defaultAdminRole, boss));
        assertTrue(app.hasRole(defaultAdminRole, other));
        assertTrue(app.hasRole(upgraderRole, other));

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
        InitializeParams memory params = _defaultParams(boss);

        vm.expectRevert(NoChangeError.selector);
        _initializeOnly(address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.admin = other;
        address separate = _initializeBareDiamond(address(init), abi.encodeCall(OnReDiamondInit.init, (params)));
        assertEq(separate.code.length > 0, true);
    }

    function test_InitializerHandsOffTheBootstrapUpgraderGrant() public {
        // `app` was deployed by this contract, so this contract held the bootstrap
        // UPGRADER_ROLE granted by the proxy constructor and signed the first cut,
        // exactly as the Gemforge deploy wallet does. The initializer must have
        // taken that grant back once the configured upgrader was in place.
        bytes32 upgraderRole = app.UPGRADER_ROLE();
        assertFalse(app.hasRole(upgraderRole, address(this)));
        assertTrue(app.hasRole(upgraderRole, upgrader));

        // A deployer that is itself the configured upgrader keeps the role.
        InitializeParams memory params = InitializeParams({
            boss: boss, admin: admin, worker: worker, upgrader: address(this), approvers: new address[](0)
        });
        IDiamondProxy retained = _deployDiamondApp(params);
        assertTrue(retained.hasRole(upgraderRole, address(this)));
    }

    function test_InitializerRejectsInvalidAddressesAndApprovers() public {
        OnReDiamondInit init = new OnReDiamondInit();
        InitializeParams memory params = _defaultParams(boss);
        // Every attempt below reverts, so the diamond's state is untouched and one
        // bare proxy serves for all of them.
        DiamondProxy bare = new DiamondProxy(address(this));

        params.worker = address(0);
        vm.expectRevert(ZeroAddressError.selector);
        _cutBare(bare, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.admin = address(0);
        params.worker = makeAddr("validWorker");
        vm.expectRevert(ZeroAddressError.selector);
        _cutBare(bare, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.admin = admin;
        params.boss = address(0);
        vm.expectRevert(ZeroAddressError.selector);
        _cutBare(bare, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.boss = boss;
        params.upgrader = address(0);
        vm.expectRevert(ZeroAddressError.selector);
        _cutBare(bare, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.upgrader = upgrader;
        params.approvers = new address[](3);
        params.approvers[0] = makeAddr("approverA");
        params.approvers[1] = makeAddr("approverB");
        params.approvers[2] = makeAddr("approverC");
        vm.expectRevert(BothApproversFilledError.selector);
        _cutBare(bare, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        params.approvers = new address[](1);
        params.approvers[0] = address(0);
        vm.expectRevert(ZeroAddressError.selector);
        _cutBare(bare, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));

        address duplicateApprover = makeAddr("duplicateApprover");
        params.approvers = new address[](2);
        params.approvers[0] = duplicateApprover;
        params.approvers[1] = duplicateApprover;
        vm.expectRevert(abi.encodeWithSelector(ApproverAlreadyExistsError.selector, duplicateApprover));
        _cutBare(bare, address(init), abi.encodeCall(OnReDiamondInit.init, (params)));
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
            address(replacement), IDiamondCut.FacetCutAction.Replace, IDiamondProxy.marketStats.selector, address(0), ""
        );

        MarketStats memory stats = app.marketStats(address(token));
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
        vm.expectRevert(abi.encodeWithSelector(Diamond.FunctionNotFound.selector, unknownSelector));
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

    /// @dev Deploys a bare diamond the way Gemforge does — proxy constructor
    /// installs the core facets and grants this contract the bootstrap
    /// UPGRADER_ROLE — then runs only the initializer through the first cut.
    function _initializeBareDiamond(address init, bytes memory initCalldata) private returns (address) {
        DiamondProxy bare = new DiamondProxy(address(this));
        _cutBare(bare, init, initCalldata);
        return address(bare);
    }

    function _cutBare(DiamondProxy bare, address init, bytes memory initCalldata) private {
        IDiamondCut(address(bare)).diamondCut(new IDiamondCut.FacetCut[](0), init, initCalldata);
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

    function _defaultParams(address initialBoss) private returns (InitializeParams memory params) {
        params = InitializeParams({
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
    function marketStats(address token) external view returns (MarketStats memory stats) {
        OnReTokenConfig storage config = LibOnReStorage._appStorage().onReTokenConfigs[token];
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
