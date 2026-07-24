// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReOffer} from "./LibOnReOffer.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {LibOnReVault} from "./LibOnReVault.sol";
import {OnReIds} from "./OnReIds.sol";

/// @notice Escrowed worker requests that execute against reverse-pair Worker OfferConfigs.
library LibOnReFulfillment {
    using SafeERC20 for IERC20;

    function createFulfillmentRequest(bytes32 offerConfigId, uint64 requestId, uint256 inputAmount)
        internal
        returns (bytes32 fulfillmentRequestId)
    {
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireExecutableOfferConfig(offerConfigId);
        _requireWorkerOffer(offer);
        if (inputAmount == 0) revert IOnReAppErrors.InvalidAmountError();

        fulfillmentRequestId = OnReIds.fulfillmentRequestId(offerConfigId, msg.sender, requestId);
        OnReTypes.FulfillmentRequest storage request =
            LibOnReStorage.appStorage().fulfillmentRequests[fulfillmentRequestId];
        if (request.exists) {
            revert IOnReAppErrors.FulfillmentRequestAlreadyExistsError(fulfillmentRequestId);
        }

        request.offerConfigId = offerConfigId;
        request.requestId = requestId;
        request.user = msg.sender;
        request.inputAmount = inputAmount;
        request.exists = true;

        LibOnReVault.pullExactTokenAmount(offer.tokenIn, msg.sender, inputAmount);
        emit IOnReAppEvents.FulfillmentRequested(
            fulfillmentRequestId, offerConfigId, msg.sender, requestId, inputAmount
        );
    }

    function cancelFulfillmentRequest(bytes32 fulfillmentRequestId) internal {
        OnReTypes.FulfillmentRequest storage request = LibOnReValidation.requireFulfillmentRequest(fulfillmentRequestId);
        address sender = msg.sender;
        if (sender != request.user && !LibOnReAccessControl.hasRole(LibOnReRoles.WORKER_ROLE, sender)) {
            revert IOnReAppErrors.UnauthorizedError(sender);
        }

        bytes32 offerConfigId = request.offerConfigId;
        address user = request.user;
        uint256 returnedAmount = request.inputAmount - request.fulfilledInputAmount;
        address tokenIn = LibOnReValidation.requireOfferConfig(offerConfigId).tokenIn;
        delete LibOnReStorage.appStorage().fulfillmentRequests[fulfillmentRequestId];

        if (returnedAmount > 0) IERC20(tokenIn).safeTransfer(user, returnedAmount);
        emit IOnReAppEvents.FulfillmentRequestCancelled(
            fulfillmentRequestId, offerConfigId, user, returnedAmount, sender
        );
    }

    function fulfillWorkerRequest(bytes32 fulfillmentRequestId, uint256 inputAmount)
        internal
        returns (uint256 amountOut)
    {
        LibOnReAccessControl.checkRole(LibOnReRoles.WORKER_ROLE);
        OnReTypes.FulfillmentRequest storage request = LibOnReValidation.requireFulfillmentRequest(fulfillmentRequestId);
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireExecutableOfferConfig(request.offerConfigId);
        _requireWorkerOffer(offer);
        if (inputAmount == 0) revert IOnReAppErrors.InvalidAmountError();

        uint256 remainingAmount = request.inputAmount - request.fulfilledInputAmount;
        if (inputAmount > remainingAmount) {
            revert IOnReAppErrors.FulfillmentAmountExceedsRemainingError(
                fulfillmentRequestId, inputAmount, remainingAmount
            );
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

        OnReTypes.ExecutionAccounting memory accounting =
            LibOnReOffer.settleEscrowedWorkerInput(offerConfigId, offer, user, inputAmount);
        emit IOnReAppEvents.FulfillmentRequestFilled(
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

    function _requireWorkerOffer(OnReTypes.OfferConfig storage offer) private view {
        if (offer.flow != OnReTypes.OfferFlow.Worker || offer.direction != OnReTypes.OfferDirection.OnReToAsset) {
            revert IOnReAppErrors.InvalidFlowQuoterError();
        }
    }
}
