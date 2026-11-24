// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    FulfillmentAmountExceedsRemainingError,
    FulfillmentRequestAlreadyExistsError,
    InvalidAmountError,
    InvalidApprovalError,
    InvalidFlowQuoterError,
    UnauthorizedError
} from "../types/OnReAppErrors.sol";
import {FulfillmentRequestCancelled, FulfillmentRequestFilled, FulfillmentRequested} from "../types/OnReAppEvents.sol";
import {
    ApprovalMessage,
    ExecutionAccounting,
    FulfillmentRequest,
    OfferAccess,
    OfferConfig,
    OfferExecution
} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReApproval} from "./LibOnReApproval.sol";
import {LibOnReOffer} from "./LibOnReOffer.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {LibOnReVault} from "./LibOnReVault.sol";
import {OnReIds} from "./OnReIds.sol";

/// @notice Escrowed requests that the worker fills against offers with Worker execution.
library LibOnReFulfillment {
    function _createFulfillmentRequest(bytes32 offerConfigId, uint64 requestId, uint256 inputAmount)
        internal
        returns (bytes32 fulfillmentRequestId)
    {
        OfferConfig storage offer = LibOnReValidation._requireExecutableOfferConfig(offerConfigId);
        _requireWorkerExecution(offer);
        // A permissioned offer only takes requests through `_createFulfillmentRequestWithApproval`.
        if (offer.access != OfferAccess.Permissionless) revert InvalidApprovalError();
        fulfillmentRequestId = _escrowRequest(offerConfigId, offer, requestId, inputAmount);
    }

    /// @dev Access is checked once, when the request is created; fills and cancellation need no approval.
    function _createFulfillmentRequestWithApproval(
        bytes32 offerConfigId,
        uint64 requestId,
        uint256 inputAmount,
        ApprovalMessage calldata approval,
        bytes calldata signature
    ) internal returns (bytes32 fulfillmentRequestId) {
        OfferConfig storage offer = LibOnReValidation._requireExecutableOfferConfig(offerConfigId);
        _requireWorkerExecution(offer);
        // A permissionless offer rejects an approval, as `takeOffer` does.
        if (
            offer.access != OfferAccess.Permissioned
                || !LibOnReApproval._isValidForUser(msg.sender, approval, signature)
        ) {
            revert InvalidApprovalError();
        }
        fulfillmentRequestId = _escrowRequest(offerConfigId, offer, requestId, inputAmount);
    }

    function _escrowRequest(bytes32 offerConfigId, OfferConfig storage offer, uint64 requestId, uint256 inputAmount)
        private
        returns (bytes32 fulfillmentRequestId)
    {
        if (inputAmount == 0) revert InvalidAmountError();

        fulfillmentRequestId = OnReIds._fulfillmentRequestId(offerConfigId, msg.sender, requestId);
        FulfillmentRequest storage request = LibOnReStorage._appStorage().fulfillmentRequests[fulfillmentRequestId];
        if (request.exists) {
            revert FulfillmentRequestAlreadyExistsError(fulfillmentRequestId);
        }

        request.offerConfigId = offerConfigId;
        request.requestId = requestId;
        request.user = msg.sender;
        request.inputAmount = inputAmount;
        request.exists = true;

        LibOnReVault._transferExactTokenAmountFrom(offer.tokenIn, msg.sender, address(this), inputAmount);
        emit FulfillmentRequested(fulfillmentRequestId, offerConfigId, msg.sender, requestId, inputAmount);
    }

    function _cancelFulfillmentRequest(bytes32 fulfillmentRequestId) internal {
        FulfillmentRequest storage request = LibOnReValidation._requireFulfillmentRequest(fulfillmentRequestId);
        address sender = msg.sender;
        if (sender != request.user && !LibOnReAccessControl._hasRole(LibOnReRoles.WORKER_ROLE, sender)) {
            revert UnauthorizedError(sender);
        }

        bytes32 offerConfigId = request.offerConfigId;
        address user = request.user;
        uint256 returnedAmount = request.inputAmount - request.fulfilledInputAmount;
        address tokenIn = LibOnReValidation._requireOfferConfig(offerConfigId).tokenIn;
        delete LibOnReStorage._appStorage().fulfillmentRequests[fulfillmentRequestId];

        if (returnedAmount > 0) LibOnReVault._transferExactTokenAmount(tokenIn, user, returnedAmount);
        emit FulfillmentRequestCancelled(fulfillmentRequestId, offerConfigId, user, returnedAmount, sender);
    }

    function _fulfillWorkerRequest(bytes32 fulfillmentRequestId, uint256 inputAmount)
        internal
        returns (uint256 amountOut)
    {
        LibOnReAccessControl._checkRole(LibOnReRoles.WORKER_ROLE);
        FulfillmentRequest storage request = LibOnReValidation._requireFulfillmentRequest(fulfillmentRequestId);
        OfferConfig storage offer = LibOnReValidation._requireExecutableOfferConfig(request.offerConfigId);
        _requireWorkerExecution(offer);
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
            delete LibOnReStorage._appStorage().fulfillmentRequests[fulfillmentRequestId];
        } else {
            request.fulfilledInputAmount = totalFulfilledInputAmount;
        }

        ExecutionAccounting memory accounting =
            LibOnReOffer._settleEscrowedWorkerInput(offerConfigId, offer, user, inputAmount);
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
        amountOut = accounting.amountOut;
    }

    function _requireWorkerExecution(OfferConfig storage offer) private view {
        if (offer.execution != OfferExecution.Worker) revert InvalidFlowQuoterError();
    }
}
