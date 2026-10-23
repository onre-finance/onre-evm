// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script, console} from "forge-std/Script.sol";

/// Shared configuration for Safe operation scripts. ONRE_ENV must be selected explicitly.
abstract contract EnvironmentScript is Script {
    struct Environment {
        uint256 chainId;
        address diamond;
        address safe;
        address managedToken;
        address assetToken;
        address settlementAccount;
    }

    function _loadEnvironment() internal view returns (Environment memory env) {
        string memory name = vm.envString("ONRE_ENV");
        env = _loadEnvironment(name);
        console.log("Environment:", name);
        console.log("Chain ID:", env.chainId);
        console.log("Diamond:", env.diamond);
    }

    function _loadEnvironment(string memory name) internal view returns (Environment memory env) {
        bytes32 nameHash = keccak256(bytes(name));
        uint256 expectedChainId;
        if (nameHash == keccak256("base-sepolia")) {
            expectedChainId = 84532;
        } else if (nameHash == keccak256("ethereum-mainnet-test") || nameHash == keccak256("ethereum-mainnet-live")) {
            expectedChainId = 1;
        } else {
            revert("Unknown ONRE_ENV");
        }

        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/script/config/", name, ".json"));
        env.chainId = vm.parseJsonUint(json, ".chainId");
        require(env.chainId == expectedChainId, "Environment config has incorrect chainId");
        require(block.chainid == env.chainId, "RPC chain does not match ONRE_ENV");

        env.diamond = vm.parseJsonAddress(json, ".diamond");
        env.safe = vm.parseJsonAddress(json, ".safe");
        env.managedToken = vm.parseJsonAddress(json, ".managedToken");
        env.assetToken = vm.parseJsonAddress(json, ".assetToken");
        env.settlementAccount = vm.parseJsonAddress(json, ".settlementAccount");
        require(env.diamond != address(0) && env.safe != address(0), "Environment diamond/safe not set");
    }
}
