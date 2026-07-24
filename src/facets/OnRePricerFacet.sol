// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnRePricer} from "../libraries/LibOnRePricer.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {IOnRePricer} from "../interfaces/IOnRePricer.sol";

contract OnRePricerFacet is IOnRePricer {
    function createPricer(address onReToken, OnReTypes.PricingDenomination denomination)
        external
        override
        returns (bytes32 pricerId)
    {
        return LibOnRePricer.createPricer(onReToken, denomination);
    }

    function addPricingVector(bytes32 pricerId, OnReTypes.PricingVector calldata vector) external override {
        LibOnRePricer.addPricingVector(pricerId, vector);
    }

    function deletePricingVector(bytes32 pricerId, uint64 startTime) external override {
        LibOnRePricer.deletePricingVector(pricerId, startTime);
    }

    function deleteAllPricingVectors(bytes32 pricerId) external override {
        LibOnRePricer.deleteAllPricingVectors(pricerId);
    }

    function setPricerDisabled(bytes32 pricerId, bool disabled) external override {
        LibOnRePricer.setPricerDisabled(pricerId, disabled);
    }

    function currentPrice(bytes32 pricerId) external view override returns (uint256) {
        return LibOnRePricer.currentPrice(pricerId);
    }
}
