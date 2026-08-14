// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    InsufficientLiquidityError,
    InvalidAmountError,
    InvalidBasisPointsError,
    InvalidPropRfqPairError,
    PropRfqConfigurationRequiredError
} from "../types/OnReAppErrors.sol";
import {ConfigurableVault, OfferConfig, PropRfqConfig, PropRfqState} from "../types/OnReTypes.sol";
import {LibOnReMarketStats} from "./LibOnReMarketStats.sol";
import {LibOnRePropRfqMath} from "./LibOnRePropRfqMath.sol";

/// @notice Stateful pricing for the Proprietary Request for Quote (Prop RFQ) pricing.
/// @dev The fixed-point formulas mirror the corresponding Solana implementation.
library LibOnRePropRfq {
    uint256 internal constant HARD_WALL_SCALE = 1_000_000_000_000;
    uint256 internal constant CURVE_EXPONENT_SCALE = 10_000;
    uint256 internal constant CURVE_EXPONENT_STEP = 1_000;
    uint256 internal constant MAX_CURVE_EXPONENT_SCALED = 100_000;
    uint256 internal constant CADENCE_WAVE_SCALE = 10_000;
    uint256 internal constant CADENCE_WAVE_STEP = 1_000;
    uint256 internal constant MAX_CADENCE_WAVE_SCALED = 50_000;
    uint256 internal constant WALL_SENSITIVITY_SCALE = 10_000;
    uint256 internal constant MAX_BASIS_POINTS = 10_000;

    function _validateConfig(PropRfqConfig memory config) internal pure {
        if (config.curvePegHaircutBps > MAX_BASIS_POINTS) {
            revert InvalidBasisPointsError();
        }
        if (
            config.curveExponentScaled < CURVE_EXPONENT_STEP || config.curveExponentScaled > MAX_CURVE_EXPONENT_SCALED
                || config.curveExponentScaled % CURVE_EXPONENT_STEP != 0
        ) {
            revert InvalidAmountError();
        }
        if (config.cadenceThreshold == 0) revert InvalidAmountError();
        if (config.cadenceWaveScaled > MAX_CADENCE_WAVE_SCALED || config.cadenceWaveScaled % CADENCE_WAVE_STEP != 0) {
            revert InvalidAmountError();
        }
        if (config.epochDurationSeconds == 0 || config.wallSensitivityScaled == 0) {
            revert InvalidAmountError();
        }
    }

    function _validatePair(bytes32 quoterId, PropRfqState storage state, OfferConfig storage offer) internal view {
        if (state.assetToken == address(0) || state.onReToken == address(0)) {
            revert PropRfqConfigurationRequiredError();
        }
        bool isBuy = offer.tokenIn == state.assetToken && offer.tokenOut == state.onReToken;
        bool isSell = offer.tokenIn == state.onReToken && offer.tokenOut == state.assetToken;
        if (!isBuy && !isSell) {
            revert InvalidPropRfqPairError(quoterId, offer.tokenIn, offer.tokenOut);
        }
    }

    function _quoteSell(PropRfqState storage state, OfferConfig storage offer, uint256 rawAmountOut)
        internal
        view
        returns (uint256)
    {
        uint256 actualLiquidity =
            LibOnReStorage._appStorage().configurableVaultBalances[offer.liquidityVaultId][offer.tokenOut];
        if (rawAmountOut > actualLiquidity) {
            revert InsufficientLiquidityError(offer.liquidityVaultId, offer.tokenOut, actualLiquidity, rawAmountOut);
        }
        if (actualLiquidity == 0) {
            revert InsufficientLiquidityError(offer.liquidityVaultId, offer.tokenOut, 0, rawAmountOut);
        }

        uint256 hardWallReserve = _hardWallReserve(state, offer, actualLiquidity);
        if (hardWallReserve == 0) {
            revert InsufficientLiquidityError(offer.liquidityVaultId, offer.tokenOut, 0, rawAmountOut);
        }

        uint256 effectiveLiquidity =
            _dynamicWallLiquidity(state, rawAmountOut, actualLiquidity, hardWallReserve, block.timestamp);
        uint256 utilizationScaled = Math.mulDiv(rawAmountOut, HARD_WALL_SCALE, effectiveLiquidity);
        uint256 baseHaircut = LibOnRePropRfqMath._redemptionHaircutScaled(
            utilizationScaled, state.config.curvePegHaircutBps, state.config.curveExponentScaled
        );
        uint256 cadenceTarget = LibOnRePropRfqMath._cadenceWaveTargetHaircutScaled(
            utilizationScaled, _cadenceWaveYForQuote(state, block.timestamp)
        );
        uint256 haircut = baseHaircut > cadenceTarget ? baseHaircut : cadenceTarget;
        uint256 liquidityFactor = haircut >= HARD_WALL_SCALE ? 0 : HARD_WALL_SCALE - haircut;

        return Math.mulDiv(rawAmountOut, liquidityFactor, HARD_WALL_SCALE);
    }

    function _recordBuy(PropRfqState storage state, uint256 buyValueStable) internal {
        _rollVolumeTracker(state, block.timestamp);
        state.currentBuyValueStable += buyValueStable;
    }

    function _recordSell(PropRfqState storage state, uint256 sellValueStable) internal {
        _rollVolumeTracker(state, block.timestamp);
        state.currentSellValueStable += sellValueStable;
        ++state.currentSellTradeCount;
    }

    function _hardWallReserve(PropRfqState storage state, OfferConfig storage offer, uint256 actualLiquidity)
        private
        view
        returns (uint256)
    {
        ConfigurableVault storage vault = LibOnReStorage._appStorage().configurableVaults[offer.liquidityVaultId];
        if (vault.refillTargetBps == 0) return actualLiquidity;

        uint256 tvl = LibOnReMarketStats._currentTvl(state.onReToken);
        uint8 onReDecimals = LibOnReStorage._appStorage().onReTokenConfigs[state.onReToken].decimals;
        uint256 targetReserve = Math.mulDiv(
            tvl, uint256(vault.refillTargetBps) * 10 ** offer.tokenOutDecimals, MAX_BASIS_POINTS * 10 ** onReDecimals
        );
        return actualLiquidity < targetReserve ? actualLiquidity : targetReserve;
    }

    function _dynamicWallLiquidity(
        PropRfqState storage state,
        uint256 currentSellValueStable,
        uint256 actualLiquidity,
        uint256 hardWallReserve,
        uint256 currentTime
    ) private view returns (uint256) {
        uint256 effectiveSellVolume = _previewEffectiveSellVolume(state, currentSellValueStable, currentTime);
        if (effectiveSellVolume == 0) {
            return actualLiquidity < hardWallReserve ? actualLiquidity : hardWallReserve;
        }

        uint256 sensitivityComponent =
            Math.mulDiv(state.config.wallSensitivityScaled, effectiveSellVolume, actualLiquidity);
        if (sensitivityComponent > type(uint256).max - WALL_SENSITIVITY_SCALE) return 1;
        uint256 wallPosition =
            Math.mulDiv(actualLiquidity, WALL_SENSITIVITY_SCALE, WALL_SENSITIVITY_SCALE + sensitivityComponent);
        if (wallPosition == 0) wallPosition = 1;
        return wallPosition < hardWallReserve ? wallPosition : hardWallReserve;
    }

    function _previewEffectiveSellVolume(
        PropRfqState storage state,
        uint256 currentSellValueStable,
        uint256 currentTime
    ) private view returns (uint256) {
        uint256 currentNet = state.currentSellValueStable > state.currentBuyValueStable
            ? state.currentSellValueStable - state.currentBuyValueStable
            : 0;
        uint256 previousNet = 0;
        uint256 effectiveCurrentNet = 0;
        uint256 elapsed = 0;
        uint256 epochDuration = state.config.epochDurationSeconds;

        if (state.epochStart == 0 || currentTime < state.epochStart) {
            previousNet = 0;
            effectiveCurrentNet = 0;
        } else {
            elapsed = currentTime - state.epochStart;
            if (elapsed >= epochDuration * 2) {
                elapsed = 0;
            } else if (elapsed >= epochDuration) {
                previousNet = currentNet;
                elapsed = 0;
            } else {
                previousNet = state.previousNetSellValueStable;
                effectiveCurrentNet = currentNet;
            }
        }

        uint256 decayedPrevious = Math.mulDiv(previousNet, epochDuration - elapsed, epochDuration);
        return decayedPrevious + effectiveCurrentNet + currentSellValueStable;
    }

    function _rollVolumeTracker(PropRfqState storage state, uint256 currentTime) private {
        uint256 epochDuration = state.config.epochDurationSeconds;
        if (state.epochStart == 0 || currentTime < state.epochStart) {
            _resetCurrentEpoch(state, currentTime);
            state.previousNetSellValueStable = 0;
            return;
        }

        uint256 elapsed = currentTime - state.epochStart;
        if (elapsed >= epochDuration * 2) {
            state.previousNetSellValueStable = 0;
            _resetCurrentEpoch(state, currentTime);
        } else if (elapsed >= epochDuration) {
            state.previousNetSellValueStable = state.currentSellValueStable > state.currentBuyValueStable
                ? state.currentSellValueStable - state.currentBuyValueStable
                : 0;
            _resetCurrentEpoch(state, currentTime);
        }
    }

    function _resetCurrentEpoch(PropRfqState storage state, uint256 currentTime) private {
        state.currentSellValueStable = 0;
        state.currentBuyValueStable = 0;
        state.currentSellTradeCount = 0;
        // block.timestamp remains far below uint64 max for the lifetime of the EVM.
        // forge-lint: disable-next-line(unsafe-typecast)
        state.epochStart = uint64(currentTime);
    }

    function _cadenceWaveYForQuote(PropRfqState storage state, uint256 currentTime) private view returns (uint256) {
        uint256 maxWaveY = state.config.cadenceWaveScaled;
        if (maxWaveY == 0 || state.epochStart == 0 || currentTime < state.epochStart) return 0;
        if (currentTime - state.epochStart >= state.config.epochDurationSeconds) return 0;

        uint256 tradeCount = state.currentSellTradeCount;
        if (tradeCount == 0) return 0;
        uint256 ramp = tradeCount >= state.config.cadenceThreshold
            ? CADENCE_WAVE_SCALE
            : Math.mulDiv(tradeCount, CADENCE_WAVE_SCALE, state.config.cadenceThreshold);
        return Math.mulDiv(maxWaveY, ramp, CADENCE_WAVE_SCALE);
    }
}
