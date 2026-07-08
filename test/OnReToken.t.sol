// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IBurnMintERC20} from "@chainlink/contracts/src/v0.8/shared/token/ERC20/IBurnMintERC20.sol";
import {IGetCCIPAdmin} from "@chainlink/contracts/src/v0.8/shared/interfaces/IGetCCIPAdmin.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {Test} from "forge-std/Test.sol";
import {IOnReToken} from "../src/interfaces/IOnReToken.sol";
import {OnReToken} from "../src/OnReToken.sol";

contract OnReTokenTest is Test {
    OnReToken private token;

    address private admin = makeAddr("admin");
    address private ccipAdmin = makeAddr("ccipAdmin");
    address private minter = makeAddr("minter");
    address private burner = makeAddr("burner");
    address private pool = makeAddr("pool");
    address private user = makeAddr("user");

    function setUp() public {
        token = _deployToken(admin, ccipAdmin, _singleAddress(minter), _singleAddress(burner));
    }

    function test_InitializesTokenAndCCIPAdmin() public view {
        assertEq(token.name(), "OnRe USD");
        assertEq(token.symbol(), "ONusd");
        assertEq(token.decimals(), 9);
        assertEq(token.getCCIPAdmin(), ccipAdmin);
        assertTrue(token.supportsInterface(type(IBurnMintERC20).interfaceId));
        assertTrue(token.supportsInterface(type(IGetCCIPAdmin).interfaceId));
        assertTrue(token.supportsInterface(type(IAccessControl).interfaceId));
        assertFalse(token.supportsInterface(0xffffffff));
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
        assertEq(token.minterAt(0), minter);
        assertEq(token.minterCount(), 1);
        assertTrue(token.isMinter(minter));

        assertEq(burners.length, 1);
        assertEq(burners[0], burner);
        assertEq(token.burnerAt(0), burner);
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
        vm.expectRevert(abi.encodeWithSelector(IOnReToken.SenderNotMinterError.selector, user));
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
        vm.expectRevert(IOnReToken.ZeroAddressError.selector);
        vm.prank(admin);
        token.grantMintRole(address(0));

        vm.expectRevert(IOnReToken.ZeroAddressError.selector);
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
        assertEq(token.minterAt(0), user);
        assertEq(token.burnerAt(0), user);
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
        vm.expectRevert(abi.encodeWithSelector(IOnReToken.SenderNotBurnerError.selector, user));
        vm.prank(user);
        token.burn(1);

        vm.expectRevert(abi.encodeWithSelector(IOnReToken.SenderNotBurnerError.selector, user));
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

        vm.prank(admin);
        token.setCCIPAdmin(nextAdmin);

        assertEq(token.getCCIPAdmin(), nextAdmin);
    }

    function test_OnlyUpgraderCanUpgrade() public {
        OnReToken newImplementation = new OnReToken();

        vm.expectRevert();
        vm.prank(user);
        token.upgradeToAndCall(address(newImplementation), "");

        vm.prank(admin);
        token.upgradeToAndCall(address(newImplementation), "");
    }

    function _deployToken(
        address admin_,
        address ccipAdmin_,
        address[] memory initialMinters,
        address[] memory initialBurners
    ) private returns (OnReToken) {
        OnReToken implementation = new OnReToken();
        IOnReToken.InitializeParams memory params = IOnReToken.InitializeParams({
            name: "OnRe USD",
            symbol: "ONusd",
            admin: admin_,
            ccipAdmin: ccipAdmin_,
            initialMinters: initialMinters,
            initialBurners: initialBurners
        });

        ERC1967Proxy proxy = new ERC1967Proxy(address(implementation), abi.encodeCall(OnReToken.initialize, (params)));
        return OnReToken(address(proxy));
    }

    function _expectDeployTokenZeroAddressRevert(
        address admin_,
        address ccipAdmin_,
        address[] memory initialMinters,
        address[] memory initialBurners
    ) private {
        OnReToken implementation = new OnReToken();
        IOnReToken.InitializeParams memory params = IOnReToken.InitializeParams({
            name: "OnRe USD",
            symbol: "ONusd",
            admin: admin_,
            ccipAdmin: ccipAdmin_,
            initialMinters: initialMinters,
            initialBurners: initialBurners
        });

        vm.expectRevert(IOnReToken.ZeroAddressError.selector);
        new ERC1967Proxy(address(implementation), abi.encodeCall(OnReToken.initialize, (params)));
    }

    function _singleAddress(address account) private pure returns (address[] memory accounts) {
        accounts = new address[](1);
        accounts[0] = account;
    }
}
