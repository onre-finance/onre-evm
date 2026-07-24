// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";

interface IOnRePricer {
    function createPricer(address onReToken, OnReTypes.PricingDenomination denomination)
        external
        returns (bytes32 pricerId);
    function addPricingVector(bytes32 pricerId, OnReTypes.PricingVector calldata vector) external;
    function deletePricingVector(bytes32 pricerId, uint64 startTime) external;
    function deleteAllPricingVectors(bytes32 pricerId) external;
    function setPricerDisabled(bytes32 pricerId, bool disabled) external;
    function currentPrice(bytes32 pricerId) external view returns (uint256);
}
