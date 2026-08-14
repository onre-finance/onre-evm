// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    InvalidAmountError,
    InvalidPropRfqPairError,
    InvalidQuoterKindError,
    InvalidTokenError,
    NoChangeError,
    QuoterAlreadyExistsError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
import {PropRfqQuoterConfigured, QuoterCreated, QuoterEnabledSet} from "../types/OnReAppEvents.sol";
import {
    OfferConfig,
    OfferDirection,
    PropRfqQuoterConfig,
    PropRfqQuoterState,
    QuoteResult,
    Quoter,
    QuoterKind
} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnRePropRfq} from "./LibOnRePropRfq.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Reusable NAV and proprietary request-for-quote amount-out dispatch.
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

    function _configurePropRfqQuoter(
        bytes32 quoterId,
        address assetToken,
        address onReToken,
        PropRfqQuoterConfig calldata config
    ) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        Quoter storage quoter = LibOnReValidation._requireQuoter(quoterId);
        if (quoter.kind != QuoterKind.PropRfq) {
            revert InvalidQuoterKindError(quoterId, uint8(QuoterKind.PropRfq), uint8(quoter.kind));
        }

        LibOnRePropRfq._validateConfig(config);
        PropRfqQuoterState storage state = LibOnReStorage._appStorage().propRfqQuoterStates[quoterId];
        if (state.assetToken == address(0) && state.onReToken == address(0)) {
            if (assetToken == address(0) || onReToken == address(0)) revert ZeroAddressError();
            if (assetToken == onReToken) revert InvalidTokenError();
            LibOnReValidation._requireEnabledOnReToken(onReToken);
            state.assetToken = assetToken;
            state.onReToken = onReToken;
            // forge-lint: disable-next-line(unsafe-typecast)
            state.epochStart = uint64(block.timestamp);
        } else {
            if (assetToken != state.assetToken || onReToken != state.onReToken) {
                revert InvalidPropRfqPairError(quoterId, assetToken, onReToken);
            }
            if (keccak256(abi.encode(state.config)) == keccak256(abi.encode(config))) revert NoChangeError();
        }

        state.config = config;
        _emitPropRfqConfigured(quoterId, state);
    }

    function _setQuoterEnabled(bytes32 quoterId, bool enabled) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        Quoter storage quoter = LibOnReValidation._requireQuoter(quoterId);
        bool disabled = !enabled;
        if (quoter.disabled == disabled) revert NoChangeError();
        quoter.disabled = disabled;
        emit QuoterEnabledSet(quoterId, enabled);
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
        } else if (quoter.kind == QuoterKind.NavPermissionless) {
            amountOut = _quoteNavPermissionless(offer, netInputAmount, price);
        } else {
            uint256 rawAmountOut = _quoteByDirection(offer, netInputAmount, price);
            amountOut = offer.direction == OfferDirection.OnReToAsset
                ? LibOnRePropRfq._quoteSell(
                    LibOnReStorage._appStorage().propRfqQuoterStates[offer.quoterId], offer, rawAmountOut
                )
                : rawAmountOut;
        }
        if (amountOut == 0) revert InvalidAmountError();
        result = QuoteResult({price: price, amountOut: amountOut});
    }

    function _adjustedFee(OfferConfig storage offer, uint256 grossInputAmount, uint256 feeAmount)
        internal
        view
        returns (uint256)
    {
        Quoter storage quoter = LibOnReValidation._requireExecutableQuoter(offer.quoterId);
        if (quoter.kind != QuoterKind.PropRfq) return feeAmount;
        return LibOnRePropRfq._adjustedFee(
            LibOnReStorage._appStorage().propRfqQuoterStates[offer.quoterId], offer, grossInputAmount, feeAmount
        );
    }

    function _recordExecution(OfferConfig storage offer, uint256 netInputAmount, uint256 price) internal {
        Quoter storage quoter = LibOnReStorage._appStorage().quoters[offer.quoterId];
        if (quoter.kind != QuoterKind.PropRfq) return;

        PropRfqQuoterState storage state = LibOnReStorage._appStorage().propRfqQuoterStates[offer.quoterId];
        if (offer.direction == OfferDirection.AssetToOnRe) {
            LibOnRePropRfq._recordBuy(state, netInputAmount);
        } else {
            LibOnRePropRfq._recordSell(state, _quoteByDirection(offer, netInputAmount, price));
        }
    }

    function _emitPropRfqConfigured(bytes32 quoterId, PropRfqQuoterState storage state) private {
        PropRfqQuoterConfig storage config = state.config;
        emit PropRfqQuoterConfigured(
            quoterId,
            state.assetToken,
            state.onReToken,
            config.curvePegHaircutBps,
            config.curveExponentScaled,
            config.cadenceThreshold,
            config.cadenceWaveScaled,
            config.epochDurationSeconds,
            config.wallSensitivityScaled,
            config.minimumSellHaircutOnRe
        );
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
