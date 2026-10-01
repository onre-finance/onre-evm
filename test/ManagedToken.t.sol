// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {IGetCCIPAdmin} from "@chainlink/contracts/src/v0.8/shared/interfaces/IGetCCIPAdmin.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {IERC20Errors} from "@openzeppelin/contracts/interfaces/draft-IERC6093.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {IManagedToken} from "../src/IManagedToken.sol";
import {IBufferController} from "../src/IBufferController.sol";
import {ManagedToken} from "../src/ManagedToken.sol";
import {IAppConfig} from "../src/IAppConfig.sol";
import {KilledError} from "../src/types/OnReAppErrors.sol";

contract ManagedTokenTest is Test {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    ManagedToken private token;
    address private implementation;
    MockKillSwitch private killSwitch;

    address private admin = makeAddr("admin");
    address private ccipAdmin = makeAddr("ccipAdmin");
    address private minter = makeAddr("minter");
    address private burner = makeAddr("burner");
    address private pool = makeAddr("pool");
    address private user = makeAddr("user");

    function setUp() public {
        killSwitch = new MockKillSwitch();
        implementation = address(new ManagedToken());
        token = _deployToken(9, admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));
    }

    function test_InitializesTokenAndCCIPAdmin() public view {
        assertEq(token.name(), "OnRe USD");
        assertEq(token.symbol(), "ONusd");
        assertEq(token.decimals(), 9);
        assertEq(token.getCCIPAdmin(), ccipAdmin);
        assertEq(token.killSwitchController(), address(killSwitch));
        assertTrue(token.hasRole(token.UPGRADER_ROLE(), admin));
        assertTrue(token.supportsInterface(type(IBurnMintERC20).interfaceId));
        assertTrue(token.supportsInterface(type(IGetCCIPAdmin).interfaceId));
        assertTrue(token.supportsInterface(type(IManagedToken).interfaceId));
        assertTrue(token.supportsInterface(type(IAccessControl).interfaceId));
        assertFalse(token.supportsInterface(0xffffffff));
    }

    function test_InitializesWithConfiguredDecimals() public {
        ManagedToken sixDecimalToken = _deployToken(6, admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));
        ManagedToken zeroDecimalToken =
            _deployToken(0, admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));
        ManagedToken maxDecimalToken =
            _deployToken(type(uint8).max, admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));

        assertEq(sixDecimalToken.decimals(), 6);
        assertEq(zeroDecimalToken.decimals(), 0);
        assertEq(maxDecimalToken.decimals(), type(uint8).max);
    }

    function test_InitializeRejectsZeroAdminOrCCIPAdmin() public {
        _expectDeployTokenZeroAddressRevert(address(0), ccipAdmin, _singleAddress(minter), _singleAddress(burner));
        _expectDeployTokenZeroAddressRevert(admin, address(0), _singleAddress(minter), _singleAddress(burner));
    }

    function test_InitializeRejectsZeroInitialMinterOrBurner() public {
        _expectDeployTokenZeroAddressRevert(admin, ccipAdmin, _singleAddress(address(0)), _singleAddress(burner));
        _expectDeployTokenZeroAddressRevert(admin, ccipAdmin, _singleAddress(minter), _singleAddress(address(0)));
    }

    function test_InitializeRequiresAWorkingKillSwitchController() public {
        address[2] memory noCodeControllers = [address(0), user];
        for (uint256 i; i < noCodeControllers.length; ++i) {
            killSwitch = MockKillSwitch(noCodeControllers[i]);
            vm.expectRevert(
                abi.encodeWithSelector(IManagedToken.InvalidKillSwitchControllerError.selector, noCodeControllers[i])
            );
            _deployToken(9, admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));
        }

        killSwitch = MockKillSwitch(address(new RecordingBufferController()));
        vm.expectRevert();
        _deployToken(9, admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));
    }

    function test_TracksInitialMintersAndBurners() public view {
        address[] memory minters = token.getMinters();
        address[] memory burners = token.getBurners();

        assertEq(minters.length, 1);
        assertEq(minters[0], minter);
        assertEq(token.minterCount(), 1);
        assertTrue(token.isMinter(minter));

        assertEq(burners.length, 1);
        assertEq(burners[0], burner);
        assertEq(token.burnerCount(), 1);
        assertTrue(token.isBurner(burner));
    }

    function test_MinterCanMint() public {
        vm.prank(minter);
        token.mint(user, 100e9);

        assertEq(token.balanceOf(user), 100e9);
        assertEq(token.totalSupply(), 100e9);
    }

    function test_MintLimitsDefaultToDisabledAndPreserveInterfaces() public view {
        assertEq(token.maxSupply(), 0);
        assertEq(token.maxMintAmount(), 0);
        assertTrue(token.supportsInterface(type(IManagedToken).interfaceId));
        assertTrue(token.supportsInterface(type(IBurnMintERC20).interfaceId));
    }

    function test_MintLimitsConfigurationAndRecoveryWhileKilled() public {
        address[4] memory unauthorized = [user, minter, burner, ccipAdmin];
        for (uint256 i; i < unauthorized.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized[i], bytes32(0)
                )
            );
            vm.prank(unauthorized[i]);
            token.setMintLimits(100e9, 10e9);
        }
        vm.expectEmit(address(token));
        emit IManagedToken.MintLimitsSet(0, 100e9, 0, 10e9);
        vm.prank(admin);
        token.setMintLimits(100e9, 10e9);
        vm.expectRevert(IManagedToken.NoChangeError.selector);
        vm.prank(admin);
        token.setMintLimits(100e9, 10e9);

        killSwitch.setKilled(true);
        vm.expectEmit(address(token));
        emit IManagedToken.MintLimitsSet(100e9, 200e9, 10e9, 20e9);
        vm.prank(admin);
        token.setMintLimits(200e9, 20e9);
        assertEq(token.maxSupply(), 200e9);
        assertEq(token.maxMintAmount(), 20e9);
    }

    function test_MintLimitsCanBeDisabledIndependently() public {
        vm.prank(admin);
        token.setMintLimits(100e9, 10e9);
        vm.prank(admin);
        token.setMintLimits(100e9, 0);
        vm.prank(minter);
        token.mint(user, 100e9);
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.MaxSupplyExceededError.selector, 100e9, 1, 100e9));
        vm.prank(minter);
        token.mint(user, 1);

        vm.prank(admin);
        token.setMintLimits(0, 10e9);
        vm.prank(minter);
        token.mint(user, 10e9);
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.MaxMintAmountExceededError.selector, 10e9 + 1, 10e9));
        vm.prank(minter);
        token.mint(user, 10e9 + 1);
        vm.prank(admin);
        token.setMintLimits(0, 0);
        vm.prank(minter);
        token.mint(user, 1_000e9);
        assertEq(token.totalSupply(), 1_110e9);
    }

    function test_SupplyCapRejectsBelowSupplyAndAllowsBurnsAndTransfersAtCap() public {
        vm.prank(minter);
        token.mint(burner, 100e9);
        vm.expectRevert(
            abi.encodeWithSelector(IManagedToken.MaxSupplyBelowCurrentSupplyError.selector, 100e9 - 1, 100e9)
        );
        vm.prank(admin);
        token.setMintLimits(100e9 - 1, 1);
        assertEq(token.maxMintAmount(), 0);
        vm.prank(admin);
        token.setMintLimits(100e9, 1);
        vm.prank(burner);
        token.transfer(user, 40e9);
        vm.prank(burner);
        token.burn(60e9);
        vm.prank(minter);
        token.mint(user, 1);
        assertEq(token.totalSupply(), 40e9 + 1);
    }

    function testFuzz_MintLimitsBoundEveryAuthorizedMinter(uint128 cap_) public {
        uint256 cap = bound(uint256(cap_), 1, type(uint128).max);
        vm.startPrank(admin);
        token.grantMintRole(pool);
        token.setMintLimits(cap * 2, cap);
        vm.stopPrank();
        vm.prank(minter);
        token.mint(user, cap);
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.MaxMintAmountExceededError.selector, cap + 1, cap));
        vm.prank(pool);
        token.mint(user, cap + 1);
        vm.prank(pool);
        token.mint(user, cap);
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.MaxSupplyExceededError.selector, cap * 2, 1, cap * 2));
        vm.prank(pool);
        token.mint(user, 1);
        assertEq(token.totalSupply(), cap * 2);
    }

    function testFuzz_ConfiguredSupplyLimitEnforcesRemainingHeadroom(uint256 cap_, uint256 startingSupply_) public {
        uint256 cap = bound(cap_, 1, type(uint256).max);
        uint256 startingSupply = bound(startingSupply_, 0, cap);
        vm.prank(minter);
        token.mint(burner, startingSupply);
        vm.prank(admin);
        token.setMintLimits(cap, 0);
        assertEq(token.maxSupply(), cap);

        vm.prank(minter);
        token.mint(burner, cap - startingSupply);
        assertEq(token.totalSupply(), cap);
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.MaxSupplyExceededError.selector, cap, 1, cap));
        vm.prank(minter);
        token.mint(burner, 1);
        assertEq(token.totalSupply(), cap);
        assertEq(token.balanceOf(burner), cap);

        // Burning reopens exactly the same amount of supply headroom.
        vm.prank(burner);
        token.burn(1);
        vm.prank(minter);
        token.mint(burner, 1);
        assertEq(token.totalSupply(), cap);
    }

    function testFuzz_ConfiguredPerMintLimitAllowsBoundaryAndRejectsOneAbove(uint256 cap_) public {
        uint256 cap = bound(cap_, 1, type(uint256).max / 2);
        vm.prank(admin);
        token.setMintLimits(0, cap);
        assertEq(token.maxMintAmount(), cap);

        vm.expectRevert(abi.encodeWithSelector(IManagedToken.MaxMintAmountExceededError.selector, cap + 1, cap));
        vm.prank(minter);
        token.mint(user, cap + 1);
        assertEq(token.totalSupply(), 0);
        assertEq(token.balanceOf(user), 0);

        // The configured limit applies to each call, not their combined amount.
        vm.startPrank(minter);
        token.mint(user, cap);
        token.mint(user, cap);
        vm.stopPrank();
        assertEq(token.totalSupply(), cap * 2);
        assertEq(token.balanceOf(user), cap * 2);
    }

    function testFuzz_IndependentMintLimitsEnforceTighterBoundary(
        uint128 startingSupply,
        uint128 headroom_,
        uint128 mintCap_
    ) public {
        uint256 headroom = bound(uint256(headroom_), 1, type(uint128).max);
        uint256 mintCap = bound(uint256(mintCap_), 1, type(uint128).max);
        uint256 supplyCap = uint256(startingSupply) + headroom;
        uint256 allowedMint = headroom < mintCap ? headroom : mintCap;
        vm.prank(minter);
        token.mint(user, startingSupply);
        vm.prank(admin);
        token.setMintLimits(supplyCap, mintCap);
        assertEq(token.maxSupply(), supplyCap);
        assertEq(token.maxMintAmount(), mintCap);

        if (mintCap <= headroom) {
            vm.expectRevert(
                abi.encodeWithSelector(IManagedToken.MaxMintAmountExceededError.selector, allowedMint + 1, mintCap)
            );
        } else {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IManagedToken.MaxSupplyExceededError.selector, startingSupply, allowedMint + 1, supplyCap
                )
            );
        }
        vm.prank(minter);
        token.mint(user, allowedMint + 1);
        assertEq(token.totalSupply(), startingSupply);
        assertEq(token.balanceOf(user), startingSupply);

        vm.prank(minter);
        token.mint(user, allowedMint);
        assertEq(token.totalSupply(), uint256(startingSupply) + allowedMint);
        assertEq(token.balanceOf(user), uint256(startingSupply) + allowedMint);
    }

    function test_SupplyCapRejectsHugeMintWithoutArithmeticOverflow() public {
        vm.prank(minter);
        token.mint(user, 1);
        vm.prank(admin);
        token.setMintLimits(type(uint256).max, 0);
        vm.expectRevert(
            abi.encodeWithSelector(
                IManagedToken.MaxSupplyExceededError.selector, 1, type(uint256).max, type(uint256).max
            )
        );
        vm.prank(minter);
        token.mint(user, type(uint256).max);
    }

    function test_KillSwitchReadFailureFreezesSupplyButAllowsTransfers() public {
        vm.prank(minter);
        token.mint(burner, 100e9);
        bytes memory failure = abi.encodeWithSignature("KillSwitchUnavailable()");
        vm.mockCallRevert(address(killSwitch), abi.encodeCall(IAppConfig.appConfig, ()), failure);

        vm.expectRevert(failure);
        vm.prank(minter);
        token.mint(user, 1e9);
        vm.expectRevert(failure);
        vm.prank(burner);
        token.burn(1e9);
        vm.prank(burner);
        token.transfer(user, 10e9);
        assertEq(token.totalSupply(), 100e9);
        assertEq(token.balanceOf(user), 10e9);
    }

    function test_ChangingBufferControllerCannotBypassKillSwitch() public {
        killSwitch.setKilled(true);
        RecordingBufferController replacementBuffer = new RecordingBufferController();
        vm.prank(admin);
        token.setBufferController(address(replacementBuffer));

        vm.expectRevert(KilledError.selector);
        vm.prank(minter);
        token.mint(user, 1e9);
        assertEq(token.totalSupply(), 0);
    }

    function test_NonMinterCannotMint() public {
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.SenderNotMinterError.selector, user));
        vm.prank(user);
        token.mint(user, 1);
    }

    function test_AdminCanGrantAndRevokeMintAndBurnRoles() public {
        vm.prank(admin);
        token.grantMintAndBurnRoles(pool);

        assertTrue(token.isMinter(pool));
        assertTrue(token.isBurner(pool));
        assertEq(token.minterCount(), 2);
        assertEq(token.burnerCount(), 2);

        vm.prank(admin);
        token.revokeMintAndBurnRoles(pool);

        assertFalse(token.isMinter(pool));
        assertFalse(token.isBurner(pool));
        assertEq(token.minterCount(), 1);
        assertEq(token.burnerCount(), 1);
    }

    function test_AdminCanGrantAndRevokeIndividualRoles() public {
        vm.startPrank(admin);
        token.grantMintRole(pool);
        token.grantBurnRole(pool);

        assertTrue(token.isMinter(pool));
        assertTrue(token.isBurner(pool));

        token.revokeMintRole(pool);
        token.revokeBurnRole(pool);
        vm.stopPrank();

        assertFalse(token.isMinter(pool));
        assertFalse(token.isBurner(pool));
    }

    function test_AdminRoleChangesRejectZeroAddress() public {
        vm.expectRevert(IManagedToken.ZeroAddressError.selector);
        vm.prank(admin);
        token.grantMintRole(address(0));

        vm.expectRevert(IManagedToken.ZeroAddressError.selector);
        vm.prank(admin);
        token.grantBurnRole(address(0));
    }

    function test_DuplicateGrantsAndMissingRevokesAreNoops() public {
        vm.startPrank(admin);
        token.grantMintAndBurnRoles(pool);
        token.grantMintAndBurnRoles(pool);
        token.revokeMintAndBurnRoles(user);
        vm.stopPrank();

        assertEq(token.minterCount(), 2);
        assertEq(token.burnerCount(), 2);
        assertTrue(token.isMinter(pool));
        assertTrue(token.isBurner(pool));
        assertFalse(token.isMinter(user));
        assertFalse(token.isBurner(user));
    }

    function test_RevokeSwapsWithLastRoleEntry() public {
        vm.startPrank(admin);
        token.grantMintAndBurnRoles(pool);
        token.grantMintAndBurnRoles(user);
        token.revokeMintRole(minter);
        token.revokeBurnRole(burner);
        vm.stopPrank();

        assertFalse(token.isMinter(minter));
        assertFalse(token.isBurner(burner));
        assertEq(token.minterCount(), 2);
        assertEq(token.burnerCount(), 2);
    }

    function test_CcipPoolStyleBurnMintFlow() public {
        vm.prank(admin);
        token.grantMintAndBurnRoles(pool);

        vm.prank(pool);
        token.mint(pool, 100e9);

        vm.prank(pool);
        token.burn(40e9);

        assertEq(token.balanceOf(pool), 60e9);
        assertEq(token.totalSupply(), 60e9);
    }

    function test_NonBurnerCannotBurn() public {
        vm.prank(minter);
        token.mint(user, 1);

        vm.expectRevert(abi.encodeWithSelector(IManagedToken.SenderNotBurnerError.selector, user));
        vm.prank(user);
        token.burn(1);

        vm.expectRevert(abi.encodeWithSelector(IManagedToken.SenderNotBurnerError.selector, user));
        vm.prank(user);
        token.burnFrom(pool, 1);

        vm.expectRevert(abi.encodeWithSelector(IManagedToken.SenderNotBurnerError.selector, user));
        vm.prank(user);
        token.burnFrom(user, 1);

        assertEq(token.balanceOf(user), 1);
        assertEq(token.totalSupply(), 1);
    }

    function test_BurnFromOwnBalanceRequiresNoAllowanceAndNotifiesBuffer() public {
        RecordingBufferController controller = new RecordingBufferController();
        vm.prank(admin);
        token.setBufferController(address(controller));

        vm.prank(minter);
        token.mint(burner, 100e9);
        assertEq(token.allowance(burner, burner), 0);

        vm.prank(burner);
        token.burnFrom(burner, 40e9);

        assertEq(token.balanceOf(burner), 60e9);
        assertEq(token.totalSupply(), 60e9);
        assertEq(token.allowance(burner, burner), 0);
        assertEq(controller.callCount(), 2);
        assertEq(controller.lastAmount(), 40e9);
        assertFalse(controller.lastIsMint());
    }

    function test_BurnFromOwnBalanceDoesNotSpendSelfAllowance() public {
        vm.prank(minter);
        token.mint(burner, 100e9);

        vm.startPrank(burner);
        token.approve(burner, 10e9);
        token.burnFrom(burner, 40e9);
        vm.stopPrank();

        assertEq(token.allowance(burner, burner), 10e9);
        assertEq(token.balanceOf(burner), 60e9);
        assertEq(token.totalSupply(), 60e9);
    }

    function test_BurnAddressAliasBurnsOwnBalanceWithoutAllowance() public {
        vm.prank(minter);
        token.mint(burner, 100e9);

        vm.prank(burner);
        token.burn(burner, 40e9);

        assertEq(token.balanceOf(burner), 60e9);
        assertEq(token.totalSupply(), 60e9);
        assertEq(token.allowance(burner, burner), 0);
    }

    function test_BurnAddressAliasUsesBurnFrom() public {
        vm.prank(minter);
        token.mint(user, 100e9);

        vm.prank(admin);
        token.grantBurnRole(pool);

        vm.prank(user);
        token.approve(pool, 40e9);

        vm.prank(pool);
        token.burn(user, 40e9);

        assertEq(token.balanceOf(user), 60e9);
        assertEq(token.totalSupply(), 60e9);
    }

    function test_BurnFromRequiresAllowance() public {
        vm.prank(minter);
        token.mint(user, 100e9);

        vm.prank(admin);
        token.grantBurnRole(pool);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, pool, 0, 50e9));
        vm.prank(pool);
        token.burnFrom(user, 50e9);

        assertEq(token.balanceOf(user), 100e9);
        assertEq(token.totalSupply(), 100e9);

        vm.prank(user);
        token.approve(pool, 60e9);

        vm.prank(pool);
        token.burnFrom(user, 50e9);

        assertEq(token.balanceOf(user), 50e9);
        assertEq(token.totalSupply(), 50e9);
        assertEq(token.allowance(user, pool), 10e9);

        vm.expectRevert(abi.encodeWithSelector(IERC20Errors.ERC20InsufficientAllowance.selector, pool, 10e9, 50e9));
        vm.prank(pool);
        token.burnFrom(user, 50e9);

        assertEq(token.balanceOf(user), 50e9);
        assertEq(token.totalSupply(), 50e9);
        assertEq(token.allowance(user, pool), 10e9);
    }

    function test_AdminCanUpdateCCIPAdmin() public {
        address nextAdmin = makeAddr("nextAdmin");

        vm.expectRevert(IManagedToken.ZeroAddressError.selector);
        vm.prank(admin);
        token.setCCIPAdmin(address(0));

        vm.prank(admin);
        vm.expectEmit(true, true, false, true, address(token));
        emit IManagedToken.CCIPAdminTransferredEvent(ccipAdmin, nextAdmin);
        token.setCCIPAdmin(nextAdmin);

        assertEq(token.getCCIPAdmin(), nextAdmin);
    }

    function test_SetCCIPAdminRejectsUnchangedAdmin() public {
        vm.expectRevert(IManagedToken.NoChangeError.selector);
        vm.prank(admin);
        token.setCCIPAdmin(ccipAdmin);

        assertEq(token.getCCIPAdmin(), ccipAdmin);
    }

    function test_BufferControllerObservesRegularSupplyChangesWhileBufferPathsBypassIt() public {
        RecordingBufferController controller = new RecordingBufferController();

        vm.expectRevert();
        vm.prank(user);
        token.setBufferController(address(controller));

        vm.expectRevert(IManagedToken.ZeroAddressError.selector);
        vm.prank(admin);
        token.setBufferController(address(0));

        address noCodeController = makeAddr("noCodeController");
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.BufferControllerHasNoCodeError.selector, noCodeController));
        vm.prank(admin);
        token.setBufferController(noCodeController);

        vm.prank(admin);
        token.setBufferController(address(controller));
        assertEq(token.bufferController(), address(controller));

        vm.expectRevert(IManagedToken.NoChangeError.selector);
        vm.prank(admin);
        token.setBufferController(address(controller));

        vm.prank(minter);
        token.mint(user, 100e9);
        assertEq(controller.callCount(), 1);
        assertEq(controller.lastAmount(), 100e9);
        assertTrue(controller.lastIsMint());

        vm.prank(minter);
        token.mint(burner, 50e9);
        vm.prank(burner);
        token.burn(20e9);
        assertEq(controller.callCount(), 3);
        assertEq(controller.lastAmount(), 20e9);
        assertFalse(controller.lastIsMint());

        vm.prank(user);
        token.approve(burner, 10e9);
        vm.prank(burner);
        token.burnFrom(user, 10e9);
        assertEq(controller.callCount(), 4);
        assertEq(controller.lastAmount(), 10e9);
        assertFalse(controller.lastIsMint());

        vm.prank(address(controller));
        token.mintBuffer(7e9);
        assertEq(controller.callCount(), 4);
        assertEq(token.balanceOf(address(controller)), 7e9);

        uint256 supplyBeforeBurn = token.totalSupply();
        vm.prank(address(controller));
        token.burnBuffer(3e9);
        assertEq(controller.callCount(), 4);
        assertEq(token.balanceOf(address(controller)), 4e9);
        assertEq(token.totalSupply(), supplyBeforeBurn - 3e9);
        assertEq(token.balanceOf(user), 90e9);

        vm.expectRevert();
        vm.prank(address(controller));
        token.burnBuffer(4e9 + 1);
        assertEq(token.balanceOf(address(controller)), 4e9);
        assertEq(controller.callCount(), 4);
    }

    function test_BurnBufferRequiresConfiguredControllerEvenForAdminOrBurner() public {
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.SenderNotBufferControllerError.selector, burner));
        vm.prank(burner);
        token.burnBuffer(0);

        RecordingBufferController controller = new RecordingBufferController();
        vm.prank(admin);
        token.setBufferController(address(controller));
        address[3] memory unauthorized = [admin, burner, user];
        for (uint256 i; i < unauthorized.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(IManagedToken.SenderNotBufferControllerError.selector, unauthorized[i])
            );
            vm.prank(unauthorized[i]);
            token.burnBuffer(1);
        }
    }

    function test_AdminUpgradesOnlySelectedTokenAndPreservesState() public {
        ManagedToken secondToken = _deployToken(6, admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));

        vm.prank(minter);
        token.mint(user, 100e9);

        vm.prank(admin);
        token.setMintLimits(200e9, 10e9);

        ManagedTokenV2 newImplementation = new ManagedTokenV2();

        assertEq(_implementationOf(address(token)), implementation);
        assertEq(_implementationOf(address(secondToken)), implementation);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, token.UPGRADER_ROLE()
            )
        );
        vm.prank(user);
        token.upgradeToAndCall(address(newImplementation), "");

        vm.prank(admin);
        token.upgradeToAndCall(address(newImplementation), "");

        assertEq(_implementationOf(address(token)), address(newImplementation));
        assertEq(_implementationOf(address(secondToken)), implementation);
        assertEq(ManagedTokenV2(address(token)).version(), 2);
        (bool secondUpgraded,) = address(secondToken).staticcall(abi.encodeCall(ManagedTokenV2.version, ())); // selector is absent on V1
        assertFalse(secondUpgraded);
        assertEq(token.decimals(), 9);
        assertEq(secondToken.decimals(), 6);
        assertEq(token.balanceOf(user), 100e9);
        assertEq(token.maxSupply(), 200e9);
        assertEq(token.maxMintAmount(), 10e9);
        assertEq(secondToken.maxSupply(), 0);
        assertEq(secondToken.maxMintAmount(), 0);
        assertTrue(token.isMinter(minter));
        assertTrue(token.isBurner(burner));
        assertTrue(token.hasRole(token.DEFAULT_ADMIN_ROLE(), admin));

        vm.prank(minter);
        token.mint(user, 1);
        assertEq(token.balanceOf(user), 100e9 + 1);
    }

    function _deployToken(
        uint8 decimals_,
        address admin_,
        address ccipAdmin_,
        address[] memory initialMinters,
        address[] memory initialBurners
    ) private returns (ManagedToken) {
        IManagedToken.InitializeParams memory params = IManagedToken.InitializeParams({
            name: "OnRe USD",
            symbol: "ONusd",
            decimals: decimals_,
            admin: admin_,
            ccipAdmin: ccipAdmin_,
            killSwitchController: address(killSwitch),
            initialMinters: initialMinters,
            initialBurners: initialBurners
        });

        ERC1967Proxy proxy = new ERC1967Proxy(implementation, abi.encodeCall(ManagedToken.initialize, (params)));
        return ManagedToken(address(proxy));
    }

    function _expectDeployTokenZeroAddressRevert(
        address admin_,
        address ccipAdmin_,
        address[] memory initialMinters,
        address[] memory initialBurners
    ) private {
        IManagedToken.InitializeParams memory params = IManagedToken.InitializeParams({
            name: "OnRe USD",
            symbol: "ONusd",
            decimals: 9,
            admin: admin_,
            ccipAdmin: ccipAdmin_,
            killSwitchController: address(killSwitch),
            initialMinters: initialMinters,
            initialBurners: initialBurners
        });

        vm.expectRevert(IManagedToken.ZeroAddressError.selector);
        new ERC1967Proxy(implementation, abi.encodeCall(ManagedToken.initialize, (params)));
    }

    function _implementationOf(address proxy) private view returns (address) {
        return address(uint160(uint256(vm.load(proxy, IMPLEMENTATION_SLOT))));
    }

    function _singleAddress(address account) private pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }
}

contract ManagedTokenV2 is ManagedToken {
    function version() external pure returns (uint256) {
        return 2;
    }
}

contract RecordingBufferController is IBufferController {
    uint256 public callCount;
    uint256 public lastAmount;
    bool public lastIsMint;

    function onBeforeSupplyChange(uint256 amount, bool isMint) external {
        ++callCount;
        lastAmount = amount;
        lastIsMint = isMint;
    }
}

contract MockKillSwitch is IAppConfig {
    bool public killed;

    function setKilled(bool value) external {
        killed = value;
    }

    function appConfig() external view returns (bool, address, address) {
        return (killed, address(0), address(0));
    }
}
