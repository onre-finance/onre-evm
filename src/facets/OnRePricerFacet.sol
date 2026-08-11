// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnRePricer} from "../libraries/LibOnRePricer.sol";
import {PricingDenomination, PricingVector} from "../types/OnReTypes.sol";

contract OnRePricerFacet {
    function createPricer(address onReToken, PricingDenomination denomination) external returns (bytes32 pricerId) {
        return LibOnRePricer.createPricer(onReToken, denomination);
    }

    function addPricingVector(bytes32 pricerId, PricingVector calldata vector) external {
        LibOnRePricer.addPricingVector(pricerId, vector);
    }

    function deletePricingVector(bytes32 pricerId, uint64 startTime) external {
        LibOnRePricer.deletePricingVector(pricerId, startTime);
    }

    function deleteAllPricingVectors(bytes32 pricerId) external {
        LibOnRePricer.deleteAllPricingVectors(pricerId);
    }

    function setPricerEnabled(bytes32 pricerId, bool enabled) external {
        LibOnRePricer.setPricerEnabled(pricerId, enabled);
    }

    function currentPrice(bytes32 pricerId) external view returns (uint256) {
        return LibOnRePricer.currentPrice(pricerId);
    }
}
