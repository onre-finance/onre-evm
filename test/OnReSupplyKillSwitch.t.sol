// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {KilledError} from "../src/types/OnReAppErrors.sol";
import {OnReAppTestBase} from "./helpers/OnReAppTestBase.sol";

contract OnReSupplyKillSwitchTest is OnReAppTestBase {
    function test_KillSwitchBlocksEveryRegularSupplyPathWithoutBuffer() public {
        assertEq(managedToken.killSwitchController(), address(app));
        assertEq(managedToken.bufferController(), address(0));
        managedToken.grantBurnRole(address(this));
        managedToken.mint(address(this), 100e9);
        managedToken.mint(user, 100e9);
        vm.prank(user);
        managedToken.approve(address(this), 50e9);
        app.setKillSwitch(true);

        vm.expectRevert(KilledError.selector);
        managedToken.mint(user, 1e9);
        vm.expectRevert(KilledError.selector);
        managedToken.burn(1e9);
        vm.expectRevert(KilledError.selector);
        managedToken.burnFrom(address(this), 1e9);
        vm.expectRevert(KilledError.selector);
        managedToken.burnFrom(user, 1e9);
        vm.expectRevert(KilledError.selector);
        managedToken.burn(address(this), 1e9);
        vm.expectRevert(KilledError.selector);
        managedToken.burn(user, 1e9);

        assertEq(managedToken.totalSupply(), 200e9);
        assertEq(managedToken.balanceOf(address(this)), 100e9);
        assertEq(managedToken.balanceOf(user), 100e9);
        assertEq(managedToken.allowance(user, address(this)), 50e9);

        // ERC20 transfers and approvals remain available while supply is frozen.
        managedToken.transfer(user, 10e9);
        vm.prank(user);
        managedToken.approve(address(this), 20e9);
        managedToken.transferFrom(user, worker, 5e9);
        assertEq(managedToken.balanceOf(user), 105e9);
        assertEq(managedToken.balanceOf(worker), 5e9);
        assertEq(managedToken.totalSupply(), 200e9);

        app.setKillSwitch(false);
        managedToken.mint(user, 4e9);
        managedToken.burn(1e9);
        managedToken.burnFrom(user, 2e9);
        assertEq(managedToken.totalSupply(), 201e9);
    }

    function test_KillSwitchAlsoBlocksAuthorizedBridgePool() public {
        address pool = makeAddr("ccipPool");
        managedToken.grantMintAndBurnRoles(pool);
        vm.prank(pool);
        managedToken.mint(pool, 10e9);
        app.setKillSwitch(true);

        vm.expectRevert(KilledError.selector);
        vm.prank(pool);
        managedToken.burn(5e9);
        vm.expectRevert(KilledError.selector);
        vm.prank(pool);
        managedToken.mint(user, 5e9);
        assertEq(managedToken.totalSupply(), 10e9);

        app.setKillSwitch(false);
        vm.prank(pool);
        managedToken.burn(5e9);
        vm.prank(pool);
        managedToken.mint(user, 5e9);
        assertEq(managedToken.totalSupply(), 10e9);
        assertEq(managedToken.balanceOf(user), 5e9);
    }
}
