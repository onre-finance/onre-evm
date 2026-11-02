// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReOps} from "./base/OnReOps.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";

/// Run with ONRE_ENV, --rpc-url, and --sig "run(string,string,uint8,bytes32)" <name> <symbol> <decimals> <salt>.
/// The configured Safe must hold DEFAULT_ADMIN_ROLE and becomes token admin and CCIP admin.
contract DeployManagedToken is OnReOps {
    function run(string memory name, string memory symbol, uint8 decimals, bytes32 salt) external {
        Environment memory env = _loadEnvironment();
        _init(env.diamond, env.safe);
        require(bytes(name).length != 0 && bytes(symbol).length != 0, "NAME/SYMBOL not set");
        require(decimals <= 18, "Managed token decimals exceed 18");
        address implementation = _deployManagedTokenImpl(salt);
        address token = _deployManagedToken(implementation, name, symbol, decimals);
        require(IDiamondProxy(diamond).isManagedTokenDeployed(token), "Managed token not registered");
        _log("Implementation", implementation);
        _log("Managed token (simulated; depends on Diamond nonce)", token);
        _printTxs();
    }
}
