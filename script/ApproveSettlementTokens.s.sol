// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OfferConfiguration} from "./base/OfferConfiguration.sol";
import {OfferFlow} from "../src/types/OnReTypes.sol";

/// Run with ONRE_ENV and --rpc-url. Execute these calls from the settlement Safe.
/// Approves the Diamond for both tokens of each configured permissionless offer.
contract ApproveSettlementTokens is OfferConfiguration {
    function run() external {
        Environment memory env = _loadEnvironment();
        Configuration memory config = _loadOfferConfiguration();
        _init(env.diamond, env.settlementAccount);
        for (uint256 i; i < config.offers.length; ++i) {
            OfferDefinition memory offer = config.offers[i];
            if (offer.flow != OfferFlow.Permissionless) continue;
            _ensureApproval(offer.assetToken, type(uint256).max);
            _ensureApproval(offer.managedToken, type(uint256).max);
        }
        _printTxs();
    }
}
