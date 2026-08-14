// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnRePricer} from "../libraries/LibOnRePricer.sol";
import {PricingDenomination, PricingVector} from "../types/OnReTypes.sol";

contract OnRePricerFacet {
    function createPricer(address onReToken, PricingDenomination denomination) external returns (bytes32 pricerId) {
        pricerId = LibOnRePricer._createPricer(onReToken, denomination);
    }

    function addPricingVector(bytes32 pricerId, PricingVector calldata vector) external {
        LibOnRePricer._addPricingVector(pricerId, vector);
    }

    function deletePricingVector(bytes32 pricerId, uint64 startTime) external {
        LibOnRePricer._deletePricingVector(pricerId, startTime);
    }

    function deleteAllPricingVectors(bytes32 pricerId) external {
        LibOnRePricer._deleteAllPricingVectors(pricerId);
    }

    function setPricerEnabled(bytes32 pricerId, bool enabled) external {
        LibOnRePricer._setPricerEnabled(pricerId, enabled);
    }

    function currentPrice(bytes32 pricerId) external view returns (uint256) {
        return LibOnRePricer._currentPrice(pricerId);
    }
}
