// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OnReOps} from "./base/OnReOps.sol";

/// Run with ONRE_ENV, --rpc-url, and --sig "run(bytes32)" <offerId>.
contract DisableOffer is OnReOps {
    function run(bytes32 offerId) external {
        Environment memory env = _loadEnvironment();
        _init(env.diamond, env.safe);
        require(offerId != bytes32(0), "Offer ID not set");

        if (IDiamondProxy(diamond).getOfferConfig(offerId).enabled) {
            _setOfferConfigEnabled(offerId, false);
        }
        require(!IDiamondProxy(diamond).getOfferConfig(offerId).enabled, "offer still enabled");

        _log("Disabled offer ID", offerId);
        _printTxs();
    }
}
