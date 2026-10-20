// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {EnvironmentScript} from "./base/EnvironmentScript.sol";
import {console} from "forge-std/Script.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {ManagedToken} from "../src/ManagedToken.sol";

/// The configured Safe must hold DEFAULT_ADMIN_ROLE. The Safe becomes admin and CCIP admin;
/// the Diamond is auto-added as minter and burner.
/// Run with ONRE_ENV set and --rpc-url for the selected environment.
contract DeployManagedToken is EnvironmentScript {
    string constant NAME = "";
    string constant SYMBOL = "";
    uint8 constant DECIMALS = 9;
    bytes32 constant SALT = bytes32(0);

    function run() external {
        Environment memory env = _loadEnvironment();
        require(bytes(NAME).length != 0 && bytes(SYMBOL).length != 0, "NAME/SYMBOL not set");

        bytes memory creationCode = type(ManagedToken).creationCode;
        address impl = vm.computeCreate2Address(SALT, keccak256(creationCode), CREATE2_FACTORY);
        require(impl.code.length == 0, "ManagedToken implementation already deployed");

        bytes memory deployImplData = abi.encodePacked(SALT, creationCode);
        bytes memory deployTokenData = abi.encodeCall(
            IDiamondProxy.deployManagedToken,
            (impl, NAME, SYMBOL, DECIMALS, env.safe, env.safe, new address[](0), new address[](0))
        );

        vm.startPrank(env.safe);

        bool ok;
        (ok,) = CREATE2_FACTORY.call(deployImplData);
        require(ok && impl.code.length != 0, "implementation deployment simulation failed");

        bytes memory ret;
        (ok, ret) = env.diamond.call(deployTokenData);
        require(ok, "deployManagedToken simulation failed");

        vm.stopPrank();
        address managedToken = abi.decode(ret, (address));
        require(IDiamondProxy(env.diamond).isManagedTokenDeployed(managedToken), "managed token not registered");

        console.log("Safe:            ", env.safe);
        console.log("Implementation:  ", impl);
        console.log("Managed token:   ", managedToken, "(simulated; depends on Diamond nonce)");
        console.log("");

        console.log("Tx 1: deploy ManagedToken implementation (CREATE2)");
        console.log("  to:   ", CREATE2_FACTORY);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(deployImplData));

        console.log("Tx 2: deployManagedToken");
        console.log("  to:   ", env.diamond);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(deployTokenData));
    }
}
