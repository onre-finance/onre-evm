// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {VectorIndexOutOfBoundsError} from "../types/OnReAppErrors.sol";
import {
    ConfigurableVault,
    FeeConfig,
    FulfillmentRequest,
    OfferConfig,
    OnReTokenConfig,
    Pricer,
    PricingVector,
    Quoter
} from "../types/OnReTypes.sol";

/// @notice Read helpers shared by the view facet.
library LibOnReView {
    function getOnReTokenConfig(address onReToken) internal view returns (OnReTokenConfig memory) {
        return LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
    }

    function getPricer(bytes32 pricerId) internal view returns (Pricer memory) {
        return LibOnReStorage.appStorage().pricers[pricerId];
    }

    function getPricingVector(bytes32 pricerId, uint8 vectorIndex) internal view returns (PricingVector memory) {
        Pricer storage pricer = LibOnReStorage.appStorage().pricers[pricerId];
        if (vectorIndex >= pricer.vectorCount) {
            revert VectorIndexOutOfBoundsError(vectorIndex, pricer.vectorCount);
        }
        return pricer.vectors[vectorIndex];
    }

    function getQuoter(bytes32 quoterId) internal view returns (Quoter memory) {
        return LibOnReStorage.appStorage().quoters[quoterId];
    }

    function getFeeConfig(bytes32 feeConfigId) internal view returns (FeeConfig memory) {
        return LibOnReStorage.appStorage().feeConfigs[feeConfigId];
    }

    function getOfferConfig(bytes32 offerConfigId) internal view returns (OfferConfig memory) {
        return LibOnReStorage.appStorage().offerConfigs[offerConfigId];
    }

    function getFulfillmentRequest(bytes32 fulfillmentRequestId) internal view returns (FulfillmentRequest memory) {
        return LibOnReStorage.appStorage().fulfillmentRequests[fulfillmentRequestId];
    }

    function getConfigurableVault(bytes32 vaultId) internal view returns (ConfigurableVault memory) {
        return LibOnReStorage.appStorage().configurableVaults[vaultId];
    }

    function getExcludedSupplyAccounts(address onReToken) internal view returns (address[] memory) {
        return LibOnReStorage.appStorage().excludedSupplyAccounts[onReToken];
    }

    function appConfig() internal view returns (bool isKilled, address approver1, address approver2) {
        LibOnReStorage.AppStorage storage s = LibOnReStorage.appStorage();
        return (s.isKilled, s.approver1, s.approver2);
    }
}
