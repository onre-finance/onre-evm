// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OnReOps} from "./base/OnReOps.sol";

/// Run with ONRE_ENV and --rpc-url; reads settlementAccount from the environment configuration.
contract SetSettlementAccount is OnReOps {
    function run() external {
        Environment memory env = _loadEnvironment();
        _init(env.diamond, env.safe);
        require(env.settlementAccount != address(0), "SETTLEMENT_ACCOUNT not set");

        _log("Previous settlement account", IDiamondProxy(diamond).permissionlessSettlementAccount());
        _setPermissionlessSettlementAccount(env.settlementAccount);
        require(
            IDiamondProxy(diamond).permissionlessSettlementAccount() == env.settlementAccount,
            "settlement account not set"
        );

        _log("New settlement account", env.settlementAccount);
        _printTxs();
    }
}
