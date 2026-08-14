// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {InvalidQuoterKindError, QuoterNotFoundError, VectorIndexOutOfBoundsError} from "../types/OnReAppErrors.sol";
import {
    ConfigurableVault,
    FeeConfig,
    FulfillmentRequest,
    OfferConfig,
    OnReTokenConfig,
    Pricer,
    PricingVector,
    PropRfqState,
    Quoter,
    QuoterKind
} from "../types/OnReTypes.sol";

/// @notice Read helpers shared by the view facet.
library LibOnReView {
    function _getOnReTokenConfig(address onReToken) internal view returns (OnReTokenConfig memory) {
        return LibOnReStorage._appStorage().onReTokenConfigs[onReToken];
    }

    function _getPricer(bytes32 pricerId) internal view returns (Pricer memory) {
        return LibOnReStorage._appStorage().pricers[pricerId];
    }

    function _getPricingVector(bytes32 pricerId, uint8 vectorIndex) internal view returns (PricingVector memory) {
        Pricer storage pricer = LibOnReStorage._appStorage().pricers[pricerId];
        if (vectorIndex >= pricer.vectorCount) {
            revert VectorIndexOutOfBoundsError(vectorIndex, pricer.vectorCount);
        }
        return pricer.vectors[vectorIndex];
    }

    function _getQuoter(bytes32 quoterId) internal view returns (Quoter memory) {
        return LibOnReStorage._appStorage().quoters[quoterId];
    }

    function _getPropRfqState(bytes32 quoterId) internal view returns (PropRfqState memory) {
        Quoter storage quoter = LibOnReStorage._appStorage().quoters[quoterId];
        if (!quoter.exists) revert QuoterNotFoundError(quoterId);
        if (quoter.kind != QuoterKind.PropRfq) {
            revert InvalidQuoterKindError(quoterId, uint8(QuoterKind.PropRfq), uint8(quoter.kind));
        }
        return LibOnReStorage._appStorage().propRfqStates[quoterId];
    }

    function _getFeeConfig(bytes32 feeConfigId) internal view returns (FeeConfig memory) {
        return LibOnReStorage._appStorage().feeConfigs[feeConfigId];
    }

    function _getOfferConfig(bytes32 offerConfigId) internal view returns (OfferConfig memory) {
        return LibOnReStorage._appStorage().offerConfigs[offerConfigId];
    }

    function _getFulfillmentRequest(bytes32 fulfillmentRequestId) internal view returns (FulfillmentRequest memory) {
        return LibOnReStorage._appStorage().fulfillmentRequests[fulfillmentRequestId];
    }

    function _getConfigurableVault(bytes32 vaultId) internal view returns (ConfigurableVault memory) {
        return LibOnReStorage._appStorage().configurableVaults[vaultId];
    }

    function _getExcludedSupplyAccounts(address onReToken) internal view returns (address[] memory) {
        return LibOnReStorage._appStorage().excludedSupplyAccounts[onReToken];
    }

    function _appConfig() internal view returns (bool isKilled, address approver1, address approver2) {
        LibOnReStorage.AppStorage storage s = LibOnReStorage._appStorage();
        (isKilled, approver1, approver2) = (s.isKilled, s.approver1, s.approver2);
    }
}
