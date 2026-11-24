// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReFulfillment} from "../libraries/LibOnReFulfillment.sol";
import {ApprovalMessage} from "../types/OnReTypes.sol";

contract OnReFulfillmentFacet {
    function createFulfillmentRequest(bytes32 offerConfigId, uint64 requestId, uint256 inputAmount)
        external
        returns (bytes32 fulfillmentRequestId)
    {
        fulfillmentRequestId = LibOnReFulfillment._createFulfillmentRequest(offerConfigId, requestId, inputAmount);
    }

    /// @notice Creates a request on a permissioned worker offer; the approval must be for the caller.
    function createFulfillmentRequestWithApproval(
        bytes32 offerConfigId,
        uint64 requestId,
        uint256 inputAmount,
        ApprovalMessage calldata approval,
        bytes calldata signature
    ) external returns (bytes32 fulfillmentRequestId) {
        fulfillmentRequestId = LibOnReFulfillment._createFulfillmentRequestWithApproval(
            offerConfigId, requestId, inputAmount, approval, signature
        );
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
