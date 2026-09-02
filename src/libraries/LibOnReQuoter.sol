// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    InvalidAmountError,
    InvalidOfferDirectionError,
    InvalidPropAmmPairError,
    InvalidQuoterKindError,
    InvalidTokenError,
    NoChangeError,
    QuoterAlreadyExistsError,
    UnsupportedQuoterKindError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
import {PropAmmConfigured, QuoterCreated, QuoterEnabledSet} from "../types/OnReAppEvents.sol";
import {
    OfferConfig,
    OfferDirection,
    PropAmmConfig,
    PropAmmState,
    QuoteResult,
    Quoter,
    QuoterKind
} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnRePropAmm} from "./LibOnRePropAmm.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Reusable NAV and proprietary automated market maker amount-out dispatch.
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

    function _configurePropAmm(
        bytes32 quoterId,
        address assetToken,
        address managedToken,
        PropAmmConfig calldata config
    ) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        Quoter storage quoter = LibOnReValidation._requireQuoter(quoterId);
        if (quoter.kind != QuoterKind.PropAmm) {
            revert InvalidQuoterKindError(quoterId, uint8(QuoterKind.PropAmm), uint8(quoter.kind));
        }

        LibOnRePropAmm._validateConfig(config);
        PropAmmState storage state = LibOnReStorage._appStorage().propAmmStates[quoterId];
        if (state.assetToken == address(0) && state.managedToken == address(0)) {
            if (assetToken == address(0) || managedToken == address(0)) revert ZeroAddressError();
            if (assetToken == managedToken) revert InvalidTokenError();
            LibOnReValidation._requireEnabledManagedToken(managedToken);
            state.assetToken = assetToken;
            state.managedToken = managedToken;
            // forge-lint: disable-next-line(unsafe-typecast)
            state.epochStart = uint64(block.timestamp);
        } else {
            if (assetToken != state.assetToken || managedToken != state.managedToken) {
                revert InvalidPropAmmPairError(quoterId, assetToken, managedToken);
            }
            if (keccak256(abi.encode(state.config)) == keccak256(abi.encode(config))) revert NoChangeError();
        }

        state.config = config;
        _emitPropAmmConfigured(quoterId, state);
    }

    function _setQuoterEnabled(bytes32 quoterId, bool enabled) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        Quoter storage quoter = LibOnReValidation._requireQuoter(quoterId);
        bool disabled = !enabled;
        if (quoter.disabled == disabled) revert NoChangeError();
        quoter.disabled = disabled;
        emit QuoterEnabledSet(quoterId, enabled);
    }

    function _quote(OfferConfig storage offer, uint256 netInputAmount) internal view returns (QuoteResult memory) {
        Quoter storage quoter = LibOnReValidation._requireExecutableQuoter(offer.quoterId);
        QuoterKind kind = quoter.kind;
        address managedToken = LibOnReValidation._offerManagedToken(offer);
        uint256 price = LibOnRePricer._currentPrice(OnReIds._usdPricerId(managedToken));

        if (kind == QuoterKind.Nav) {
            return _quoteNav(offer, netInputAmount, price);
        }
        if (kind == QuoterKind.NavPermissionless) {
            return _quoteNavPermissionless(offer, netInputAmount, price);
        }
        if (kind == QuoterKind.PropAmm) {
            return _quotePropAmm(offer, netInputAmount, price);
        }

        revert UnsupportedQuoterKindError(offer.quoterId, uint8(kind));
    }

    function _recordExecution(OfferConfig storage offer, uint256 netInputAmount, uint256 price) internal {
        Quoter storage quoter = LibOnReStorage._appStorage().quoters[offer.quoterId];
        QuoterKind kind = quoter.kind;
        if (kind == QuoterKind.Nav || kind == QuoterKind.NavPermissionless) return;
        if (kind != QuoterKind.PropAmm) revert UnsupportedQuoterKindError(offer.quoterId, uint8(kind));

        PropAmmState storage state = LibOnReStorage._appStorage().propAmmStates[offer.quoterId];
        if (offer.direction == OfferDirection.AssetToManaged) {
            LibOnRePropAmm._recordBuy(state, netInputAmount);
            return;
        }
        if (offer.direction == OfferDirection.ManagedToAsset) {
            LibOnRePropAmm._recordSell(state, _quoteByDirection(offer, netInputAmount, price));
            return;
        }
        revert InvalidOfferDirectionError();
    }

    function _emitPropAmmConfigured(bytes32 quoterId, PropAmmState storage state) private {
        PropAmmConfig storage config = state.config;
        emit PropAmmConfigured(
            quoterId,
            state.assetToken,
            state.managedToken,
            config.curvePegHaircutBps,
            config.curveExponentScaled,
            config.cadenceThreshold,
            config.cadenceWaveScaled,
            config.epochDurationSeconds,
            config.wallSensitivityScaled
        );
    }

    function _quoteNav(OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (QuoteResult memory)
    {
        uint256 amountOut = _quoteByDirection(offer, netInputAmount, price);
        return _quoteResult(price, amountOut);
    }

    function _quoteNavPermissionless(OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (QuoteResult memory)
    {
        // Kept as a distinct dispatch branch so permissionless policy can evolve independently.
        uint256 amountOut = _quoteByDirection(offer, netInputAmount, price);
        return _quoteResult(price, amountOut);
    }

    function _quotePropAmm(OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (QuoteResult memory)
    {
        uint256 rawAmountOut = _quoteByDirection(offer, netInputAmount, price);
        if (offer.direction == OfferDirection.AssetToManaged) return _quoteResult(price, rawAmountOut);
        if (offer.direction == OfferDirection.ManagedToAsset) {
            PropAmmState storage state = LibOnReStorage._appStorage().propAmmStates[offer.quoterId];
            uint256 amountOut = LibOnRePropAmm._quoteSell(state, offer, rawAmountOut);
            return _quoteResult(price, amountOut);
        }
        revert InvalidOfferDirectionError();
    }

    function _quoteResult(uint256 price, uint256 amountOut) private pure returns (QuoteResult memory) {
        if (amountOut == 0) revert InvalidAmountError();
        return QuoteResult({price: price, amountOut: amountOut});
    }

    function _quoteByDirection(OfferConfig storage offer, uint256 netInputAmount, uint256 price)
        private
        view
        returns (uint256)
    {
        if (offer.direction == OfferDirection.AssetToManaged) {
            return
                OnReMath._calculateTokenOutAmount(netInputAmount, price, offer.tokenInDecimals, offer.tokenOutDecimals);
        }
        if (offer.direction == OfferDirection.ManagedToAsset) {
            return OnReMath._calculateRedemptionAssetOutAmount(
                netInputAmount, price, offer.tokenInDecimals, offer.tokenOutDecimals
            );
        }
        revert InvalidOfferDirectionError();
    }
}
