// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {IGetCCIPAdmin} from "@chainlink/contracts/src/v0.8/shared/interfaces/IGetCCIPAdmin.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {IManagedToken} from "../src/IManagedToken.sol";
import {IBufferController} from "../src/IBufferController.sol";
import {ManagedToken} from "../src/ManagedToken.sol";

contract ManagedTokenTest is Test {
    bytes32 private constant IMPLEMENTATION_SLOT = 0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    ManagedToken private token;
    address private implementation;

    address private admin = makeAddr("admin");
    address private ccipAdmin = makeAddr("ccipAdmin");
    address private minter = makeAddr("minter");
    address private burner = makeAddr("burner");
    address private pool = makeAddr("pool");
    address private user = makeAddr("user");

    function setUp() public {
        implementation = address(new ManagedToken());
        token = _deployToken(9, admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));
    }

    function test_InitializesTokenAndCCIPAdmin() public view {
        assertEq(token.name(), "OnRe USD");
        assertEq(token.symbol(), "ONusd");
        assertEq(token.decimals(), 9);
        assertEq(token.getCCIPAdmin(), ccipAdmin);
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
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.SenderNotBurnerError.selector, user));
        vm.prank(user);
        token.burn(1);

        vm.expectRevert(abi.encodeWithSelector(IManagedToken.SenderNotBurnerError.selector, user));
        vm.prank(user);
        token.burnFrom(pool, 1);
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

        vm.expectRevert();
        vm.prank(pool);
        token.burnFrom(user, 50e9);

        vm.prank(user);
        token.approve(pool, 50e9);

        vm.prank(pool);
        token.burnFrom(user, 50e9);

        assertEq(token.balanceOf(user), 50e9);
        assertEq(token.totalSupply(), 50e9);
    }

    function test_AdminCanUpdateCCIPAdmin() public {
        address nextAdmin = makeAddr("nextAdmin");

        vm.expectRevert(IManagedToken.ZeroAddressError.selector);
        vm.prank(admin);
        token.setCCIPAdmin(address(0));

        vm.prank(admin);
        token.setCCIPAdmin(nextAdmin);

        assertEq(token.getCCIPAdmin(), nextAdmin);
    }

    function test_BufferControllerObservesEveryRegularMintAndBurnWhileBufferMintBypassesIt() public {
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
    }

    function test_AdminUpgradesOnlySelectedTokenAndPreservesState() public {
        ManagedToken secondToken = _deployToken(6, admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));

        vm.prank(minter);
        token.mint(user, 100e9);

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
