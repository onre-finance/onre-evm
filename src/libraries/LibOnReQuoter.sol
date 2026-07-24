// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Reusable stateless NAV amount-out dispatch.
library LibOnReQuoter {
    function createQuoter(OnReTypes.QuoterKind kind, uint64 quoterInstanceId) internal returns (bytes32 quoterId) {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        quoterId = OnReIds.quoterId(kind, quoterInstanceId);
        OnReTypes.Quoter storage quoter = LibOnReStorage.appStorage().quoters[quoterId];
        if (quoter.exists) revert IOnReAppErrors.QuoterAlreadyExistsError(quoterId);

        quoter.kind = kind;
        quoter.instanceId = quoterInstanceId;
        quoter.exists = true;
        emit IOnReAppEvents.QuoterCreated(quoterId, kind, quoterInstanceId);
    }

    function setQuoterDisabled(bytes32 quoterId, bool disabled) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OnReTypes.Quoter storage quoter = LibOnReValidation.requireQuoter(quoterId);
        if (quoter.disabled == disabled) revert IOnReAppErrors.NoChangeError();
        quoter.disabled = disabled;
        emit IOnReAppEvents.QuoterDisabledSet(quoterId, disabled);
    }

    function quote(bytes32 offerConfigId, uint256 netInputAmount)
        internal
        view
        returns (OnReTypes.QuoteResult memory result)
    {
        if (netInputAmount == 0) revert IOnReAppErrors.InvalidAmountError();
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireExecutableOfferConfig(offerConfigId);
        return quote(offerConfigId, offer, netInputAmount);
    }

    function quote(bytes32 offerConfigId, OnReTypes.OfferConfig storage offer, uint256 netInputAmount)
        internal
        view
        returns (OnReTypes.QuoteResult memory result)
    {
        OnReTypes.Quoter storage quoter = LibOnReValidation.requireExecutableQuoter(offer.quoterId);
        _validateFlowQuoter(offerConfigId, offer, quoter.kind);

        address onReToken = offer.direction == OnReTypes.OfferDirection.AssetToOnRe ? offer.tokenOut : offer.tokenIn;
        uint256 price = LibOnRePricer.currentPrice(OnReIds.usdPricerId(onReToken));
        uint256 amountOut;
        if (quoter.kind == OnReTypes.QuoterKind.Nav) {
            amountOut = _quoteNav(offer, netInputAmount, price);
        } else {
            amountOut = _quoteNavPermissionless(offer, netInputAmount, price);
        }
        return OnReTypes.QuoteResult({price: price, amountOut: amountOut});
    }

    function validateFlowQuoter(bytes32 offerConfigId, OnReTypes.OfferConfig storage offer) internal view {
        _validateFlowQuoter(offerConfigId, offer, LibOnReValidation.requireQuoter(offer.quoterId).kind);
    }

    function _validateFlowQuoter(bytes32 offerConfigId, OnReTypes.OfferConfig storage offer, OnReTypes.QuoterKind kind)
        private
        view
    {
        if (offer.flow == OnReTypes.OfferFlow.Permissionless) {
            if (kind != OnReTypes.QuoterKind.NavPermissionless) {
                revert IOnReAppErrors.InvalidFlowQuoterError();
            }
            return;
        }

        if (kind != OnReTypes.QuoterKind.Nav) revert IOnReAppErrors.InvalidFlowQuoterError();
        if (offer.flow == OnReTypes.OfferFlow.Worker && offer.direction != OnReTypes.OfferDirection.OnReToAsset) {
            revert IOnReAppErrors.InvalidOfferDirectionError();
        }

        // Use the id so static analyzers and future branches cannot silently drop the route context.
        if (offerConfigId == bytes32(0)) revert IOnReAppErrors.OfferConfigNotFoundError(offerConfigId);
    }

    function _quoteNav(OnReTypes.OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (uint256)
    {
        return _quoteByDirection(offer, netInputAmount, price);
    }

    function _quoteNavPermissionless(OnReTypes.OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (uint256)
    {
        // Kept as a distinct dispatch branch so permissionless policy can evolve independently.
        return _quoteByDirection(offer, netInputAmount, price);
    }

    function _quoteByDirection(OnReTypes.OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (uint256)
    {
        if (offer.direction == OnReTypes.OfferDirection.AssetToOnRe) {
            return
                OnReMath.calculateTokenOutAmount(netInputAmount, price, offer.tokenInDecimals, offer.tokenOutDecimals);
        }
        return OnReMath.calculateRedemptionAssetOutAmount(
            netInputAmount, price, offer.tokenInDecimals, offer.tokenOutDecimals
        );
    }
}
