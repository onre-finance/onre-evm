// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Script, console} from "forge-std/Script.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {ManagedToken} from "../src/ManagedToken.sol";

/// SAFE must hold DEFAULT_ADMIN_ROLE. SAFE becomes admin and CCIP admin;
/// the Diamond is auto-added as minter and burner.
/// Run:
/// forge script script/DeployManagedToken.s.sol --rpc-url $ETH_MAINNET_RPC_URL
contract DeployManagedToken is Script {
    // TODO: fill in before running.
    address constant DIAMOND = address(0);
    address constant SAFE = address(0);

    string constant NAME = "";
    string constant SYMBOL = "";
    uint8 constant DECIMALS = 9;
    bytes32 constant SALT = bytes32(0);

    function run() external {
        require(DIAMOND != address(0) && SAFE != address(0), "DIAMOND/SAFE not set");
        require(bytes(NAME).length != 0 && bytes(SYMBOL).length != 0, "NAME/SYMBOL not set");

        bytes memory creationCode = type(ManagedToken).creationCode;
        address impl = vm.computeCreate2Address(SALT, keccak256(creationCode), CREATE2_FACTORY);
        require(impl.code.length == 0, "ManagedToken implementation already deployed");

        bytes memory deployImplData = abi.encodePacked(SALT, creationCode);
        bytes memory deployTokenData = abi.encodeCall(
            IDiamondProxy.deployManagedToken,
            (impl, NAME, SYMBOL, DECIMALS, SAFE, SAFE, new address[](0), new address[](0))
        );

        vm.startPrank(SAFE);

        bool ok;
        (ok,) = CREATE2_FACTORY.call(deployImplData);
        require(ok && impl.code.length != 0, "implementation deployment simulation failed");

        bytes memory ret;
        (ok, ret) = DIAMOND.call(deployTokenData);
        require(ok, "deployManagedToken simulation failed");

        vm.stopPrank();
        address managedToken = abi.decode(ret, (address));
        require(IDiamondProxy(DIAMOND).isManagedTokenDeployed(managedToken), "managed token not registered");

        console.log("Safe:            ", SAFE);
        console.log("Implementation:  ", impl);
        console.log("Managed token:   ", managedToken, "(simulated; depends on Diamond nonce)");
        console.log("");

        console.log("Tx 1: deploy ManagedToken implementation (CREATE2)");
        console.log("  to:   ", CREATE2_FACTORY);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(deployImplData));

        console.log("Tx 2: deployManagedToken");
        console.log("  to:   ", DIAMOND);
        console.log("  value: 0");
        console.log("  data: ", vm.toString(deployTokenData));
    }
}
