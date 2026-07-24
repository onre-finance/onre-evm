// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReFulfillment} from "../libraries/LibOnReFulfillment.sol";
import {IOnReFulfillment} from "../interfaces/IOnReFulfillment.sol";

contract OnReFulfillmentFacet is IOnReFulfillment {
    function createFulfillmentRequest(bytes32 offerConfigId, uint64 requestId, uint256 inputAmount)
        external
        override
        returns (bytes32 fulfillmentRequestId)
    {
        return LibOnReFulfillment.createFulfillmentRequest(offerConfigId, requestId, inputAmount);
    }

    function cancelFulfillmentRequest(bytes32 fulfillmentRequestId) external override {
        LibOnReFulfillment.cancelFulfillmentRequest(fulfillmentRequestId);
    }

    function fulfillWorkerRequest(bytes32 fulfillmentRequestId, uint256 inputAmount)
        external
        override
        returns (uint256 amountOut)
    {
        return LibOnReFulfillment.fulfillWorkerRequest(fulfillmentRequestId, inputAmount);
    }
}
