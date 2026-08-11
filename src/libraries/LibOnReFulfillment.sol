// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    FulfillmentAmountExceedsRemainingError,
    FulfillmentRequestAlreadyExistsError,
    InvalidAmountError,
    InvalidFlowQuoterError,
    UnauthorizedError
} from "../types/OnReAppErrors.sol";
import {FulfillmentRequestCancelled, FulfillmentRequestFilled, FulfillmentRequested} from "../types/OnReAppEvents.sol";
import {ExecutionAccounting, FulfillmentRequest, OfferConfig, OfferFlow} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReOffer} from "./LibOnReOffer.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {LibOnReVault} from "./LibOnReVault.sol";
import {OnReIds} from "./OnReIds.sol";

/// @notice Escrowed worker requests that execute against reverse-pair Worker OfferConfigs.
library LibOnReFulfillment {
    function createFulfillmentRequest(bytes32 offerConfigId, uint64 requestId, uint256 inputAmount)
        internal
        returns (bytes32 fulfillmentRequestId)
    {
        OfferConfig storage offer = LibOnReValidation.requireExecutableOfferConfig(offerConfigId);
        _requireWorkerFlow(offer);
        if (inputAmount == 0) revert InvalidAmountError();

        fulfillmentRequestId = OnReIds.fulfillmentRequestId(offerConfigId, msg.sender, requestId);
        FulfillmentRequest storage request = LibOnReStorage.appStorage().fulfillmentRequests[fulfillmentRequestId];
        if (request.exists) {
            revert FulfillmentRequestAlreadyExistsError(fulfillmentRequestId);
        }

        request.offerConfigId = offerConfigId;
        request.requestId = requestId;
        request.user = msg.sender;
        request.inputAmount = inputAmount;
        request.exists = true;

        LibOnReVault.pullExactTokenAmount(offer.tokenIn, msg.sender, inputAmount);
        emit FulfillmentRequested(fulfillmentRequestId, offerConfigId, msg.sender, requestId, inputAmount);
    }

    function cancelFulfillmentRequest(bytes32 fulfillmentRequestId) internal {
        FulfillmentRequest storage request = LibOnReValidation.requireFulfillmentRequest(fulfillmentRequestId);
        address sender = msg.sender;
        if (sender != request.user && !LibOnReAccessControl.hasRole(LibOnReRoles.WORKER_ROLE, sender)) {
            revert UnauthorizedError(sender);
        }

        bytes32 offerConfigId = request.offerConfigId;
        address user = request.user;
        uint256 returnedAmount = request.inputAmount - request.fulfilledInputAmount;
        address tokenIn = LibOnReValidation.requireOfferConfig(offerConfigId).tokenIn;
        delete LibOnReStorage.appStorage().fulfillmentRequests[fulfillmentRequestId];

        if (returnedAmount > 0) LibOnReVault.transferExactTokenAmount(tokenIn, user, returnedAmount);
        emit FulfillmentRequestCancelled(fulfillmentRequestId, offerConfigId, user, returnedAmount, sender);
    }

    function fulfillWorkerRequest(bytes32 fulfillmentRequestId, uint256 inputAmount)
        internal
        returns (uint256 amountOut)
    {
        LibOnReAccessControl.checkRole(LibOnReRoles.WORKER_ROLE);
        FulfillmentRequest storage request = LibOnReValidation.requireFulfillmentRequest(fulfillmentRequestId);
        OfferConfig storage offer = LibOnReValidation.requireExecutableOfferConfig(request.offerConfigId);
        _requireWorkerFlow(offer);
        if (inputAmount == 0) revert InvalidAmountError();

        uint256 remainingAmount = request.inputAmount - request.fulfilledInputAmount;
        if (inputAmount > remainingAmount) {
            revert FulfillmentAmountExceedsRemainingError(fulfillmentRequestId, inputAmount, remainingAmount);
        }

        bytes32 offerConfigId = request.offerConfigId;
        address user = request.user;
        uint256 totalFulfilledInputAmount = request.fulfilledInputAmount + inputAmount;
        bool fullyFulfilled = totalFulfilledInputAmount == request.inputAmount;
        if (fullyFulfilled) {
            delete LibOnReStorage.appStorage().fulfillmentRequests[fulfillmentRequestId];
        } else {
            request.fulfilledInputAmount = totalFulfilledInputAmount;
        }

        ExecutionAccounting memory accounting =
            LibOnReOffer.settleEscrowedWorkerInput(offerConfigId, offer, user, inputAmount);
        emit FulfillmentRequestFilled(
            fulfillmentRequestId,
            offerConfigId,
            user,
            inputAmount,
            totalFulfilledInputAmount,
            accounting.feeAmount,
            accounting.amountOut,
            accounting.price,
            fullyFulfilled
        );
        return accounting.amountOut;
    }

    function _requireWorkerFlow(OfferConfig storage offer) private view {
        if (offer.flow != OfferFlow.Worker) revert InvalidFlowQuoterError();
    }
}
