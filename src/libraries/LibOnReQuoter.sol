// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {InvalidAmountError, NoChangeError, QuoterAlreadyExistsError} from "../types/OnReAppErrors.sol";
import {QuoterCreated, QuoterEnabledSet} from "../types/OnReAppEvents.sol";
import {OfferConfig, OfferDirection, QuoteResult, Quoter, QuoterKind} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Reusable stateless NAV amount-out dispatch.
library LibOnReQuoter {
    function _createQuoter(QuoterKind kind, uint64 quoterInstanceId) internal returns (bytes32 quoterId) {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        quoterId = OnReIds._quoterId(kind, quoterInstanceId);
        Quoter storage quoter = LibOnReStorage._appStorage().quoters[quoterId];
        if (quoter.exists) revert QuoterAlreadyExistsError(quoterId);

        quoter.kind = kind;
        quoter.instanceId = quoterInstanceId;
        quoter.exists = true;
        emit QuoterCreated(quoterId, kind, quoterInstanceId);
    }

    function _setQuoterEnabled(bytes32 quoterId, bool enabled) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        Quoter storage quoter = LibOnReValidation._requireQuoter(quoterId);
        bool disabled = !enabled;
        if (quoter.disabled == disabled) revert NoChangeError();
        quoter.disabled = disabled;
        emit QuoterEnabledSet(quoterId, enabled);
    }

    function _quote(bytes32 offerConfigId, uint256 netInputAmount) internal view returns (QuoteResult memory result) {
        if (netInputAmount == 0) revert InvalidAmountError();
        OfferConfig storage offer = LibOnReValidation._requireExecutableOfferConfig(offerConfigId);
        result = _quote(offer, netInputAmount);
    }

    function _quote(OfferConfig storage offer, uint256 netInputAmount)
        internal
        view
        returns (QuoteResult memory result)
    {
        Quoter storage quoter = LibOnReValidation._requireExecutableQuoter(offer.quoterId);

        address onReToken = offer.direction == OfferDirection.AssetToOnRe ? offer.tokenOut : offer.tokenIn;
        uint256 price = LibOnRePricer._currentPrice(OnReIds._usdPricerId(onReToken));
        uint256 amountOut;
        if (quoter.kind == QuoterKind.Nav) {
            amountOut = _quoteNav(offer, netInputAmount, price);
        } else {
            amountOut = _quoteNavPermissionless(offer, netInputAmount, price);
        }
        result = QuoteResult({price: price, amountOut: amountOut});
    }

    function _quoteNav(OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (uint256)
    {
        return _quoteByDirection(offer, netInputAmount, price);
    }

    function _quoteNavPermissionless(OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (uint256)
    {
        // Kept as a distinct dispatch branch so permissionless policy can evolve independently.
        return _quoteByDirection(offer, netInputAmount, price);
    }

    function _quoteByDirection(OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (uint256)
    {
        if (offer.direction == OfferDirection.AssetToOnRe) {
            return
                OnReMath._calculateTokenOutAmount(netInputAmount, price, offer.tokenInDecimals, offer.tokenOutDecimals);
        }
        return OnReMath._calculateRedemptionAssetOutAmount(
            netInputAmount, price, offer.tokenInDecimals, offer.tokenOutDecimals
        );
    }
}
