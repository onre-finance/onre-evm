// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

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
import {LibOnReView} from "../libraries/LibOnReView.sol";

contract OnReViewFacet {
    function getOnReTokenConfig(address onReToken) external view returns (OnReTokenConfig memory) {
        return LibOnReView.getOnReTokenConfig(onReToken);
    }

    function getPricer(bytes32 pricerId) external view returns (Pricer memory) {
        return LibOnReView.getPricer(pricerId);
    }

    function getPricingVector(bytes32 pricerId, uint8 vectorIndex) external view returns (PricingVector memory) {
        return LibOnReView.getPricingVector(pricerId, vectorIndex);
    }

    function getQuoter(bytes32 quoterId) external view returns (Quoter memory) {
        return LibOnReView.getQuoter(quoterId);
    }

    function getFeeConfig(bytes32 feeConfigId) external view returns (FeeConfig memory) {
        return LibOnReView.getFeeConfig(feeConfigId);
    }

    function getOfferConfig(bytes32 offerConfigId) external view returns (OfferConfig memory) {
        return LibOnReView.getOfferConfig(offerConfigId);
    }

    function getFulfillmentRequest(bytes32 fulfillmentRequestId) external view returns (FulfillmentRequest memory) {
        return LibOnReView.getFulfillmentRequest(fulfillmentRequestId);
    }

    function getConfigurableVault(bytes32 vaultId) external view returns (ConfigurableVault memory) {
        return LibOnReView.getConfigurableVault(vaultId);
    }

    function getExcludedSupplyAccounts(address onReToken) external view returns (address[] memory) {
        return LibOnReView.getExcludedSupplyAccounts(onReToken);
    }

    function appConfig() external view returns (bool isKilled, address approver1, address approver2) {
        return LibOnReView.appConfig();
    }
}
