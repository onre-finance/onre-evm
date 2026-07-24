// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";

interface IOnReView {
    function getOnReTokenConfig(address onReToken) external view returns (OnReTypes.OnReTokenConfig memory);
    function getPricer(bytes32 pricerId) external view returns (OnReTypes.Pricer memory);
    function getPricingVector(bytes32 pricerId, uint8 vectorIndex)
        external
        view
        returns (OnReTypes.PricingVector memory);
    function getQuoter(bytes32 quoterId) external view returns (OnReTypes.Quoter memory);
    function getFeeConfig(bytes32 feeConfigId) external view returns (OnReTypes.FeeConfig memory);
    function getOfferConfig(bytes32 offerConfigId) external view returns (OnReTypes.OfferConfig memory);
    function getFulfillmentRequest(bytes32 fulfillmentRequestId)
        external
        view
        returns (OnReTypes.FulfillmentRequest memory);
    function getConfigurableVault(bytes32 vaultId) external view returns (OnReTypes.ConfigurableVault memory);
    function getExcludedSupplyAccounts(address onReToken) external view returns (address[] memory);
    function appConfig() external view returns (bool isKilled, address approver1, address approver2);
}
