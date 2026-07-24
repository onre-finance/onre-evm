// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {IOnReAppEvents} from "../interfaces/IOnReAppEvents.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnReQuoter} from "./LibOnReQuoter.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Pair-and-flow offer configuration and reference validation.
library LibOnReOfferConfig {
    function makeOfferConfig(OnReTypes.MakeOfferConfigParams calldata params) internal returns (bytes32 offerConfigId) {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (params.tokenIn == address(0) || params.tokenOut == address(0)) {
            revert IOnReAppErrors.ZeroAddressError();
        }
        if (params.tokenIn == params.tokenOut) revert IOnReAppErrors.InvalidTokenError();

        OnReTypes.OfferDirection direction = _deriveDirection(params.tokenIn, params.tokenOut);
        uint8 tokenInDecimals = IERC20Metadata(params.tokenIn).decimals();
        uint8 tokenOutDecimals = IERC20Metadata(params.tokenOut).decimals();
        if (tokenInDecimals > OnReMath.MAX_TOKEN_DECIMALS || tokenOutDecimals > OnReMath.MAX_TOKEN_DECIMALS) {
            revert IOnReAppErrors.InvalidDecimalsError();
        }

        offerConfigId = OnReIds.offerConfigId(params.tokenIn, params.tokenOut, params.flow);
        OnReTypes.OfferConfig storage offer = LibOnReStorage.appStorage().offerConfigs[offerConfigId];
        if (offer.exists) revert IOnReAppErrors.OfferConfigAlreadyExistsError(offerConfigId);

        offer.tokenIn = params.tokenIn;
        offer.tokenOut = params.tokenOut;
        offer.flow = params.flow;
        offer.direction = direction;
        offer.tokenInDecimals = tokenInDecimals;
        offer.tokenOutDecimals = tokenOutDecimals;
        offer.exists = true;
        _setOfferReferences(
            offerConfigId, offer, params.quoterId, params.feeConfigId, params.proceedsVaultId, params.liquidityVaultId
        );

        emit IOnReAppEvents.OfferConfigCreated(
            offerConfigId,
            params.tokenIn,
            params.tokenOut,
            params.flow,
            direction,
            params.quoterId,
            params.feeConfigId,
            params.proceedsVaultId,
            params.liquidityVaultId
        );
    }

    function updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireOfferConfig(offerConfigId);
        if (
            offer.quoterId == quoterId && offer.feeConfigId == feeConfigId && offer.proceedsVaultId == proceedsVaultId
                && offer.liquidityVaultId == liquidityVaultId
        ) {
            revert IOnReAppErrors.NoChangeError();
        }
        _setOfferReferences(offerConfigId, offer, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId);
        emit IOnReAppEvents.OfferConfigReferencesUpdated(
            offerConfigId, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
    }

    function setOfferConfigDisabled(bytes32 offerConfigId, bool disabled) internal {
        LibOnReAccessControl.checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OnReTypes.OfferConfig storage offer = LibOnReValidation.requireOfferConfig(offerConfigId);
        if (offer.disabled == disabled) revert IOnReAppErrors.NoChangeError();
        offer.disabled = disabled;
        emit IOnReAppEvents.OfferConfigDisabledSet(offerConfigId, disabled);
    }

    function _setOfferReferences(
        bytes32 offerConfigId,
        OnReTypes.OfferConfig storage offer,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) private {
        LibOnReValidation.requirePricer(OnReIds.usdPricerId(_onReToken(offer)));
        LibOnReValidation.requireQuoter(quoterId);
        OnReTypes.FeeConfig storage feeConfig = LibOnReValidation.requireFeeConfig(feeConfigId);
        LibOnReValidation.requireVaultKind(feeConfig.feeVaultId, OnReTypes.ConfigurableVaultKind.Fee);
        LibOnReValidation.requireVaultKind(proceedsVaultId, OnReTypes.ConfigurableVaultKind.Proceeds);
        if (liquidityVaultId != bytes32(0)) {
            LibOnReValidation.requireVaultKind(liquidityVaultId, OnReTypes.ConfigurableVaultKind.Liquidity);
        }
        if (offer.direction == OnReTypes.OfferDirection.OnReToAsset && liquidityVaultId == bytes32(0)) {
            revert IOnReAppErrors.LiquidityVaultRequiredError(offerConfigId);
        }

        offer.quoterId = quoterId;
        offer.feeConfigId = feeConfigId;
        offer.proceedsVaultId = proceedsVaultId;
        offer.liquidityVaultId = liquidityVaultId;
        LibOnReQuoter.validateFlowQuoter(offerConfigId, offer);
    }

    function _deriveDirection(address tokenIn, address tokenOut) private view returns (OnReTypes.OfferDirection) {
        bool inputIsOnRe = LibOnReStorage.appStorage().onReTokenConfigs[tokenIn].decimals != 0;
        bool outputIsOnRe = LibOnReStorage.appStorage().onReTokenConfigs[tokenOut].decimals != 0;
        if (inputIsOnRe == outputIsOnRe) revert IOnReAppErrors.InvalidOfferDirectionError();
        address onReToken = inputIsOnRe ? tokenIn : tokenOut;
        LibOnReValidation.requireEnabledOnReToken(onReToken);
        return inputIsOnRe ? OnReTypes.OfferDirection.OnReToAsset : OnReTypes.OfferDirection.AssetToOnRe;
    }

    function _onReToken(OnReTypes.OfferConfig storage offer) private view returns (address) {
        return offer.direction == OnReTypes.OfferDirection.AssetToOnRe ? offer.tokenOut : offer.tokenIn;
    }
}
