// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Test} from "forge-std/Test.sol";
import {EnvironmentScript} from "../script/base/EnvironmentScript.sol";

contract EnvironmentHarness is EnvironmentScript {
    function load(string memory name) external view returns (Environment memory) {
        return _loadEnvironment(name);
    }
}

contract ScriptEnvironmentTest is Test {
    EnvironmentHarness internal harness;

    function setUp() public {
        harness = new EnvironmentHarness();
    }

    function test_LoadBaseSepolia() public {
        vm.chainId(84532);
        EnvironmentScript.Environment memory env = harness.load("base-sepolia");
        assertEq(env.chainId, 84532);
        assertTrue(env.diamond != address(0));
        assertTrue(env.safe != address(0));
        assertTrue(env.assetToken != address(0));
        assertTrue(env.managedToken != address(0));
    }

    function test_RejectBaseSepoliaOnMainnet() public {
        vm.chainId(1);
        vm.expectRevert("RPC chain does not match ONRE_ENV");
        harness.load("base-sepolia");
    }

    function test_RejectBothMainnetEnvironmentsOnBaseSepolia() public {
        vm.chainId(84532);
        vm.expectRevert("RPC chain does not match ONRE_ENV");
        harness.load("ethereum-mainnet-test");
        vm.expectRevert("RPC chain does not match ONRE_ENV");
        harness.load("ethereum-mainnet-live");
    }

    function test_RejectAmbiguousOrUnknownEnvironment() public {
        vm.expectRevert("Unknown ONRE_ENV");
        harness.load("mainnet");
        vm.expectRevert("Unknown ONRE_ENV");
        harness.load("");
        vm.expectRevert("Unknown ONRE_ENV");
        harness.load("../base-sepolia");
    }
}
