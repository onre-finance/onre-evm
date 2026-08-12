// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    InvalidDecimalsError,
    InvalidFlowQuoterError,
    InvalidOfferDirectionError,
    InvalidTokenError,
    LiquidityVaultRequiredError,
    NoChangeError,
    OfferConfigAlreadyExistsError,
    ZeroAddressError
} from "../types/OnReAppErrors.sol";
import {OfferConfigCreated, OfferConfigEnabledSet, OfferConfigReferencesUpdated} from "../types/OnReAppEvents.sol";
import {
    ConfigurableVaultKind,
    FeeConfig,
    MakeOfferConfigParams,
    OfferConfig,
    OfferDirection,
    OfferFlow,
    Quoter,
    QuoterKind
} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {LibOnRePropRfq} from "./LibOnRePropRfq.sol";
import {LibOnReRoles} from "./LibOnReRoles.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Pair-and-flow offer configuration and reference validation.
library LibOnReOfferConfig {
    function _makeOfferConfig(MakeOfferConfigParams calldata params) internal returns (bytes32 offerConfigId) {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        if (params.tokenIn == address(0) || params.tokenOut == address(0)) {
            revert ZeroAddressError();
        }
        if (params.tokenIn == params.tokenOut) revert InvalidTokenError();

        OfferDirection direction = _deriveDirection(params.tokenIn, params.tokenOut);
        uint8 tokenInDecimals = IERC20Metadata(params.tokenIn).decimals();
        uint8 tokenOutDecimals = IERC20Metadata(params.tokenOut).decimals();
        if (tokenInDecimals > OnReMath.MAX_TOKEN_DECIMALS || tokenOutDecimals > OnReMath.MAX_TOKEN_DECIMALS) {
            revert InvalidDecimalsError();
        }

        offerConfigId = OnReIds._offerConfigId(params.tokenIn, params.tokenOut, params.flow);
        OfferConfig storage offer = LibOnReStorage._appStorage().offerConfigs[offerConfigId];
        if (offer.exists) revert OfferConfigAlreadyExistsError(offerConfigId);

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

        emit OfferConfigCreated(
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

    function _updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OfferConfig storage offer = LibOnReValidation._requireOfferConfig(offerConfigId);
        if (
            offer.quoterId == quoterId && offer.feeConfigId == feeConfigId && offer.proceedsVaultId == proceedsVaultId
                && offer.liquidityVaultId == liquidityVaultId
        ) {
            revert NoChangeError();
        }
        _setOfferReferences(offerConfigId, offer, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId);
        emit OfferConfigReferencesUpdated(offerConfigId, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId);
    }

    function _setOfferConfigEnabled(bytes32 offerConfigId, bool enabled) internal {
        LibOnReAccessControl._checkRole(LibOnReRoles.DEFAULT_ADMIN_ROLE);
        OfferConfig storage offer = LibOnReValidation._requireOfferConfig(offerConfigId);
        bool disabled = !enabled;
        if (offer.disabled == disabled) revert NoChangeError();
        offer.disabled = disabled;
        emit OfferConfigEnabledSet(offerConfigId, enabled);
    }

    function _setOfferReferences(
        bytes32 offerConfigId,
        OfferConfig storage offer,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) private {
        LibOnReValidation._requirePricer(OnReIds._usdPricerId(_onReToken(offer)));
        Quoter storage quoter = LibOnReValidation._requireQuoter(quoterId);
        _validateFlowQuoter(offer, quoterId, quoter);
        FeeConfig storage feeConfig = LibOnReValidation._requireFeeConfig(feeConfigId);
        LibOnReValidation._requireVaultKind(feeConfig.feeVaultId, ConfigurableVaultKind.Fee);
        LibOnReValidation._requireVaultKind(proceedsVaultId, ConfigurableVaultKind.Proceeds);
        if (liquidityVaultId != bytes32(0)) {
            LibOnReValidation._requireVaultKind(liquidityVaultId, ConfigurableVaultKind.Liquidity);
        }
        if (offer.direction == OfferDirection.OnReToAsset && liquidityVaultId == bytes32(0)) {
            revert LiquidityVaultRequiredError(offerConfigId);
        }

        offer.quoterId = quoterId;
        offer.feeConfigId = feeConfigId;
        offer.proceedsVaultId = proceedsVaultId;
        offer.liquidityVaultId = liquidityVaultId;
    }

    function _validateFlowQuoter(OfferConfig storage offer, bytes32 quoterId, Quoter storage quoter) private view {
        if (offer.flow == OfferFlow.Permissionless) {
            if (quoter.kind != QuoterKind.NavPermissionless && quoter.kind != QuoterKind.PropRfq) {
                revert InvalidFlowQuoterError();
            }
            if (quoter.kind == QuoterKind.PropRfq) {
                LibOnRePropRfq._validatePair(
                    quoterId, LibOnReStorage._appStorage().propRfqQuoterStates[quoterId], offer
                );
            }
            return;
        }

        if (quoter.kind != QuoterKind.Nav) revert InvalidFlowQuoterError();
        if (offer.flow == OfferFlow.Worker && offer.direction != OfferDirection.OnReToAsset) {
            revert InvalidOfferDirectionError();
        }
    }

    function _deriveDirection(address tokenIn, address tokenOut) private view returns (OfferDirection) {
        bool inputIsOnRe = LibOnReStorage._appStorage().onReTokenConfigs[tokenIn].decimals != 0;
        bool outputIsOnRe = LibOnReStorage._appStorage().onReTokenConfigs[tokenOut].decimals != 0;
        if (inputIsOnRe == outputIsOnRe) revert InvalidOfferDirectionError();
        address onReToken = inputIsOnRe ? tokenIn : tokenOut;
        LibOnReValidation._requireEnabledOnReToken(onReToken);
        return inputIsOnRe ? OfferDirection.OnReToAsset : OfferDirection.AssetToOnRe;
    }

    function _onReToken(OfferConfig storage offer) private view returns (address) {
        return offer.direction == OfferDirection.AssetToOnRe ? offer.tokenOut : offer.tokenIn;
    }
}
