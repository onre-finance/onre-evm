// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnRePricer} from "../libraries/LibOnRePricer.sol";
import {OnReTypes} from "../types/OnReTypes.sol";

contract OnRePricerFacet {
    function createPricer(address onReToken, OnReTypes.PricingDenomination denomination)
        external
        returns (bytes32 pricerId)
    {
        return LibOnRePricer.createPricer(onReToken, denomination);
    }

    function setMainPricer(address onReToken, bytes32 pricerId) external {
        LibOnRePricer.setMainPricer(onReToken, pricerId);
    }

    function addPricingVector(bytes32 pricerId, OnReTypes.PricingVector calldata vector) external {
        LibOnRePricer.addPricingVector(pricerId, vector);
    }

    function deletePricingVector(bytes32 pricerId, uint64 startTime) external {
        LibOnRePricer.deletePricingVector(pricerId, startTime);
    }

    function deleteAllPricingVectors(bytes32 pricerId) external {
        LibOnRePricer.deleteAllPricingVectors(pricerId);
    }

    function setPricerDisabled(bytes32 pricerId, bool disabled) external {
        LibOnRePricer.setPricerDisabled(pricerId, disabled);
    }

    function currentPrice(bytes32 pricerId) external view returns (uint256) {
        return LibOnRePricer.currentPrice(pricerId);
    }
}
