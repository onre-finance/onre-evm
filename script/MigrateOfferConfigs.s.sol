// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {OfferConfiguration} from "./base/OfferConfiguration.sol";

/// Run with ONRE_ENV and --rpc-url, once, together with the upgrade that introduces instance IDs.
/// Migrates every configured offer: stores its instance ID and rewrites legacy Worker offers.
/// Offers that are already current are skipped on-chain, so the batch is safe to repeat.
contract MigrateOfferConfigs is OfferConfiguration {
    function run() external {
        Environment memory env = _loadEnvironment();
        Configuration memory config = _loadOfferConfiguration();
        _init(env.diamond, env.safe);
        bytes32[] memory offerIds = new bytes32[](config.offers.length);
        for (uint256 i; i < config.offers.length; ++i) {
            offerIds[i] = _offerId(config.offers[i]);
            _log(config.offers[i].name, offerIds[i]);
        }
        require(offerIds.length != 0, "No offers configured");
        _diamondCall("migrateOfferConfigs", abi.encodeCall(IDiamondProxy.migrateOfferConfigs, (offerIds)));
        for (uint256 i; i < config.offers.length; ++i) {
            require(
                IDiamondProxy(diamond).getOfferConfigV2(offerIds[i]).instanceId == config.offers[i].instanceId,
                "Offer instance ID verification failed"
            );
        }
        _printTxs();
    }
}
