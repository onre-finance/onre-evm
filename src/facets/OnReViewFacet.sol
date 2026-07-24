// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReView} from "../libraries/LibOnReView.sol";
import {IOnReView} from "../interfaces/IOnReView.sol";

contract OnReViewFacet is IOnReView {
    function getOnReTokenConfig(address onReToken) external view override returns (OnReTypes.OnReTokenConfig memory) {
        return LibOnReView.getOnReTokenConfig(onReToken);
    }

    function getPricer(bytes32 pricerId) external view override returns (OnReTypes.Pricer memory) {
        return LibOnReView.getPricer(pricerId);
    }

    function getPricingVector(bytes32 pricerId, uint8 vectorIndex)
        external
        view
        override
        returns (OnReTypes.PricingVector memory)
    {
        return LibOnReView.getPricingVector(pricerId, vectorIndex);
    }

    function getQuoter(bytes32 quoterId) external view override returns (OnReTypes.Quoter memory) {
        return LibOnReView.getQuoter(quoterId);
    }

    function getFeeConfig(bytes32 feeConfigId) external view override returns (OnReTypes.FeeConfig memory) {
        return LibOnReView.getFeeConfig(feeConfigId);
    }

    function getOfferConfig(bytes32 offerConfigId) external view override returns (OnReTypes.OfferConfig memory) {
        return LibOnReView.getOfferConfig(offerConfigId);
    }

    function getFulfillmentRequest(bytes32 fulfillmentRequestId)
        external
        view
        override
        returns (OnReTypes.FulfillmentRequest memory)
    {
        return LibOnReView.getFulfillmentRequest(fulfillmentRequestId);
    }

    function getConfigurableVault(bytes32 vaultId) external view override returns (OnReTypes.ConfigurableVault memory) {
        return LibOnReView.getConfigurableVault(vaultId);
    }

    function getExcludedSupplyAccounts(address onReToken) external view override returns (address[] memory) {
        return LibOnReView.getExcludedSupplyAccounts(onReToken);
    }

    function appConfig() external view override returns (bool isKilled, address approver1, address approver2) {
        return LibOnReView.appConfig();
    }
}
