// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

interface IOnReFulfillment {
    function createFulfillmentRequest(bytes32 offerConfigId, uint64 requestId, uint256 inputAmount)
        external
        returns (bytes32 fulfillmentRequestId);
    function cancelFulfillmentRequest(bytes32 fulfillmentRequestId) external;
    function fulfillWorkerRequest(bytes32 fulfillmentRequestId, uint256 inputAmount)
        external
        returns (uint256 amountOut);
}
