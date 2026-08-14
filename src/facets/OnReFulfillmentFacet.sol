// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReFulfillment} from "../libraries/LibOnReFulfillment.sol";

contract OnReFulfillmentFacet {
    function createFulfillmentRequest(bytes32 offerConfigId, uint64 requestId, uint256 inputAmount)
        external
        returns (bytes32 fulfillmentRequestId)
    {
        fulfillmentRequestId = LibOnReFulfillment._createFulfillmentRequest(offerConfigId, requestId, inputAmount);
    }

    function cancelFulfillmentRequest(bytes32 fulfillmentRequestId) external {
        LibOnReFulfillment._cancelFulfillmentRequest(fulfillmentRequestId);
    }

    function fulfillWorkerRequest(bytes32 fulfillmentRequestId, uint256 inputAmount)
        external
        returns (uint256 amountOut)
    {
        amountOut = LibOnReFulfillment._fulfillWorkerRequest(fulfillmentRequestId, inputAmount);
    }
}
