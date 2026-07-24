// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {OnReTypes} from "../types/OnReTypes.sol";

/// @notice Read helpers shared by the view facet.
library LibOnReView {
    function getOnReTokenConfig(address onReToken) internal view returns (OnReTypes.OnReTokenConfig memory) {
        return LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
    }

    function getPricer(bytes32 pricerId) internal view returns (OnReTypes.Pricer memory) {
        return LibOnReStorage.appStorage().pricers[pricerId];
    }

    function getPricingVector(bytes32 pricerId, uint8 vectorIndex)
        internal
        view
        returns (OnReTypes.PricingVector memory)
    {
        OnReTypes.Pricer storage pricer = LibOnReStorage.appStorage().pricers[pricerId];
        if (vectorIndex >= pricer.vectorCount) {
            revert IOnReAppErrors.VectorIndexOutOfBoundsError(vectorIndex, pricer.vectorCount);
        }
        return pricer.vectors[vectorIndex];
    }

    function getQuoter(bytes32 quoterId) internal view returns (OnReTypes.Quoter memory) {
        return LibOnReStorage.appStorage().quoters[quoterId];
    }

    function getFeeConfig(bytes32 feeConfigId) internal view returns (OnReTypes.FeeConfig memory) {
        return LibOnReStorage.appStorage().feeConfigs[feeConfigId];
    }

    function getOfferConfig(bytes32 offerConfigId) internal view returns (OnReTypes.OfferConfig memory) {
        return LibOnReStorage.appStorage().offerConfigs[offerConfigId];
    }

    function getFulfillmentRequest(bytes32 fulfillmentRequestId)
        internal
        view
        returns (OnReTypes.FulfillmentRequest memory)
    {
        return LibOnReStorage.appStorage().fulfillmentRequests[fulfillmentRequestId];
    }

    function getConfigurableVault(bytes32 vaultId) internal view returns (OnReTypes.ConfigurableVault memory) {
        return LibOnReStorage.appStorage().configurableVaults[vaultId];
    }

    function getExcludedSupplyAccounts(address onReToken) internal view returns (address[] memory) {
        return LibOnReStorage.appStorage().excludedSupplyAccounts[onReToken];
    }

    function appConfig()
        internal
        view
        returns (bool isKilled, address approver1, address approver2, address mintGateway)
    {
        LibOnReStorage.AppStorage storage s = LibOnReStorage.appStorage();
        return (s.isKilled, s.approver1, s.approver2, s.mintGateway);
    }
}
