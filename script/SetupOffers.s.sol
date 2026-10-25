// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OfferSetup} from "./base/OfferSetup.sol";

/// Creates/reuses the named pricers, quoters, vaults, fee configurations, and offers.
/// Run with ONRE_ENV and --rpc-url. Flow and direction are explicit per offer.
contract SetupOffers is OfferSetup {
    function run() external {
        _setupOffers(_loadEnvironment(), _loadOfferConfiguration());
        _printTxs();
    }
}
