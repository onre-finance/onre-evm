// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    InsufficientLiquidityError,
    InvalidAmountError,
    InvalidBasisPointsError,
    InvalidPropRfqPairError,
    OfferConfigNotFoundError
} from "../types/OnReAppErrors.sol";
import {
    ConfigurableVault,
    OfferConfig,
    OfferDirection,
    PropRfqQuoterConfig,
    PropRfqQuoterState
} from "../types/OnReTypes.sol";
import {LibOnReMarketStats} from "./LibOnReMarketStats.sol";

/// @notice Stateful pricing for the proprietary request-for-quote (Prop RFQ) quoter.
/// @dev The fixed-point formulas mirror the corresponding Solana implementation.
library LibOnRePropRfq {
    uint256 internal constant HARD_WALL_SCALE = 1_000_000_000_000;
    uint256 internal constant CURVE_EXPONENT_SCALE = 10_000;
    uint256 internal constant CURVE_EXPONENT_STEP = 1_000;
    uint256 internal constant MAX_CURVE_EXPONENT_SCALED = 100_000;
    uint256 internal constant CADENCE_WAVE_SCALE = 10_000;
    uint256 internal constant CADENCE_WAVE_STEP = 1_000;
    uint256 internal constant MAX_CADENCE_WAVE_SCALED = 50_000;
    uint256 internal constant CADENCE_WAVE_EASE = 8;
    uint256 internal constant CADENCE_WAVE_CAP_DIVISOR = 3;
    uint256 internal constant WALL_SENSITIVITY_SCALE = 10_000;
    uint256 internal constant MAX_BASIS_POINTS = 10_000;

    uint256 private constant POW_APPROX_Q_SHIFT = 40;
    uint256 private constant POW_APPROX_Q = 1_099_511_627_776;
    uint256 private constant POW_APPROX_LN2_Q = 762_123_384_786;
    uint256 private constant POW_APPROX_LOG2_E_Q = 1_586_259_972_792;
    int256 private constant LOG2_HARD_WALL_SCALE_Q = 43_829_982_801_540;
    int256 private constant CURVE_EXPONENT_SCALE_I256 = 10_000;
    int256 private constant POW_APPROX_Q_I256 = 1_099_511_627_776;

    function validateConfig(PropRfqQuoterConfig memory config) internal pure {
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

    function configure(PropRfqQuoterState storage state, PropRfqQuoterConfig memory config) internal {
        validateConfig(config);
        state.config = config;
    }

    function validatePair(bytes32 quoterId, PropRfqQuoterState storage state, OfferConfig storage offer) internal view {
        bool isBuy = offer.tokenIn == state.assetToken && offer.tokenOut == state.onReToken;
        bool isSell = offer.tokenIn == state.onReToken && offer.tokenOut == state.assetToken;
        if (!isBuy && !isSell) {
            revert InvalidPropRfqPairError(quoterId, offer.tokenIn, offer.tokenOut);
        }
    }

    function adjustedFee(
        PropRfqQuoterState storage state,
        OfferConfig storage offer,
        uint256 grossInputAmount,
        uint256 feeAmount
    ) internal view returns (uint256) {
        if (offer.direction != OfferDirection.OnReToAsset) return feeAmount;
        uint256 minimumFee = state.config.minimumSellHaircutOnRe;
        if (minimumFee <= feeAmount) return feeAmount;
        if (minimumFee >= grossInputAmount) revert InvalidAmountError();
        return minimumFee;
    }

    function quoteSell(
        bytes32 offerConfigId,
        PropRfqQuoterState storage state,
        OfferConfig storage offer,
        uint256 rawAmountOut
    ) internal view returns (uint256) {
        uint256 actualLiquidity = LibOnReStorage.appStorage()
        .configurableVaultBalances[offer.liquidityVaultId][offer.tokenOut];
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
        uint256 baseHaircut = redemptionHaircutScaled(
            utilizationScaled, state.config.curvePegHaircutBps, state.config.curveExponentScaled
        );
        uint256 cadenceTarget =
            cadenceWaveTargetHaircutScaled(utilizationScaled, _cadenceWaveYForQuote(state, block.timestamp));
        uint256 haircut = baseHaircut > cadenceTarget ? baseHaircut : cadenceTarget;
        uint256 liquidityFactor = haircut >= HARD_WALL_SCALE ? 0 : HARD_WALL_SCALE - haircut;

        // Keep the route identifier live in this branch so future refactors cannot
        // silently detach hard-wall failures from the selected offer.
        if (offerConfigId == bytes32(0)) revert OfferConfigNotFoundError(offerConfigId);
        return Math.mulDiv(rawAmountOut, liquidityFactor, HARD_WALL_SCALE);
    }

    function recordBuy(PropRfqQuoterState storage state, uint256 buyValueStable) internal {
        _rollVolumeTracker(state, block.timestamp);
        state.currentBuyValueStable += buyValueStable;
    }

    function recordSell(PropRfqQuoterState storage state, uint256 sellValueStable) internal {
        _rollVolumeTracker(state, block.timestamp);
        state.currentSellValueStable += sellValueStable;
        state.currentSellTradeCount += 1;
    }

    function _hardWallReserve(PropRfqQuoterState storage state, OfferConfig storage offer, uint256 actualLiquidity)
        private
        view
        returns (uint256)
    {
        ConfigurableVault storage vault = LibOnReStorage.appStorage().configurableVaults[offer.liquidityVaultId];
        if (vault.refillTargetBps == 0) return actualLiquidity;

        uint256 tvl = LibOnReMarketStats.currentTvl(state.onReToken);
        uint8 onReDecimals = LibOnReStorage.appStorage().onReTokenConfigs[state.onReToken].decimals;
        uint256 targetReserve = Math.mulDiv(
            tvl, uint256(vault.refillTargetBps) * 10 ** offer.tokenOutDecimals, MAX_BASIS_POINTS * 10 ** onReDecimals
        );
        return actualLiquidity < targetReserve ? actualLiquidity : targetReserve;
    }

    function _dynamicWallLiquidity(
        PropRfqQuoterState storage state,
        uint256 currentSellValueStable,
        uint256 actualLiquidity,
        uint256 hardWallReserve,
        uint256 now_
    ) private view returns (uint256) {
        uint256 effectiveSellVolume = _previewEffectiveSellVolume(state, currentSellValueStable, now_);
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

    function _previewEffectiveSellVolume(PropRfqQuoterState storage state, uint256 currentSellValueStable, uint256 now_)
        private
        view
        returns (uint256)
    {
        uint256 currentNet = state.currentSellValueStable > state.currentBuyValueStable
            ? state.currentSellValueStable - state.currentBuyValueStable
            : 0;
        uint256 previousNet = 0;
        uint256 effectiveCurrentNet = 0;
        uint256 elapsed = 0;
        uint256 epochDuration = state.config.epochDurationSeconds;

        if (state.epochStart == 0 || now_ < state.epochStart) {
            previousNet = 0;
            effectiveCurrentNet = 0;
        } else {
            elapsed = now_ - state.epochStart;
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

    function _rollVolumeTracker(PropRfqQuoterState storage state, uint256 now_) private {
        uint256 epochDuration = state.config.epochDurationSeconds;
        if (state.epochStart == 0 || now_ < state.epochStart) {
            _resetCurrentEpoch(state, now_);
            state.previousNetSellValueStable = 0;
            return;
        }

        uint256 elapsed = now_ - state.epochStart;
        if (elapsed >= epochDuration * 2) {
            state.previousNetSellValueStable = 0;
            _resetCurrentEpoch(state, now_);
        } else if (elapsed >= epochDuration) {
            state.previousNetSellValueStable = state.currentSellValueStable > state.currentBuyValueStable
                ? state.currentSellValueStable - state.currentBuyValueStable
                : 0;
            _resetCurrentEpoch(state, now_);
        }
    }

    function _resetCurrentEpoch(PropRfqQuoterState storage state, uint256 now_) private {
        state.currentSellValueStable = 0;
        state.currentBuyValueStable = 0;
        state.currentSellTradeCount = 0;
        // block.timestamp remains far below uint64 max for the lifetime of the EVM.
        // forge-lint: disable-next-line(unsafe-typecast)
        state.epochStart = uint64(now_);
    }

    function redemptionHaircutScaled(uint256 utilization, uint16 pegHaircutBps, uint32 exponentScaled)
        internal
        pure
        returns (uint256)
    {
        uint256 pegHaircut = Math.mulDiv(HARD_WALL_SCALE, pegHaircutBps, MAX_BASIS_POINTS);
        if (pegHaircut == 0) return 0;
        return Math.mulDiv(pegHaircut, _utilizationPowerScaled(utilization, exponentScaled), HARD_WALL_SCALE);
    }

    function _cadenceWaveYForQuote(PropRfqQuoterState storage state, uint256 now_) private view returns (uint256) {
        uint256 maxWaveY = state.config.cadenceWaveScaled;
        if (maxWaveY == 0 || state.epochStart == 0 || now_ < state.epochStart) return 0;
        if (now_ - state.epochStart >= state.config.epochDurationSeconds) return 0;

        uint256 tradeCount = state.currentSellTradeCount;
        if (tradeCount == 0) return 0;
        uint256 ramp = tradeCount >= state.config.cadenceThreshold
            ? CADENCE_WAVE_SCALE
            : Math.mulDiv(tradeCount, CADENCE_WAVE_SCALE, state.config.cadenceThreshold);
        return Math.mulDiv(maxWaveY, ramp, CADENCE_WAVE_SCALE);
    }

    function cadenceWaveTargetHaircutScaled(uint256 utilization, uint256 waveYScaled) internal pure returns (uint256) {
        if (waveYScaled == 0) return 0;
        uint256 normalized = utilization < HARD_WALL_SCALE ? utilization : HARD_WALL_SCALE;
        if (normalized == 0) return 0;

        uint256 easedNumerator = normalized * CADENCE_WAVE_EASE;
        uint256 easedRise = Math.mulDiv(easedNumerator, HARD_WALL_SCALE, easedNumerator + HARD_WALL_SCALE - normalized);
        uint256 target = Math.mulDiv(easedRise, waveYScaled, CADENCE_WAVE_SCALE * CADENCE_WAVE_CAP_DIVISOR);
        return target < HARD_WALL_SCALE ? target : HARD_WALL_SCALE;
    }

    function _utilizationPowerScaled(uint256 utilization, uint32 exponentScaled) private pure returns (uint256) {
        if (utilization == 0) return 0;
        if (utilization == HARD_WALL_SCALE) return HARD_WALL_SCALE;
        if (exponentScaled % CURVE_EXPONENT_SCALE == 0) {
            return _integerUtilizationPowerScaled(utilization, exponentScaled / 10_000);
        }

        int256 log2UtilizationQ = _log2IntegerQ(utilization) - LOG2_HARD_WALL_SCALE_Q;
        int256 exponentiatedLogQ = log2UtilizationQ * int256(uint256(exponentScaled)) / CURVE_EXPONENT_SCALE_I256;
        return _exp2HardWallScaledQ(exponentiatedLogQ);
    }

    function _integerUtilizationPowerScaled(uint256 utilization, uint32 exponent) private pure returns (uint256 value) {
        value = HARD_WALL_SCALE;
        for (uint32 i; i < exponent; ++i) {
            value = _mulScaledSaturating(value, utilization);
        }
    }

    function _log2IntegerQ(uint256 value) private pure returns (int256) {
        uint256 msb = Math.log2(value);
        uint256 mantissaQ =
            msb >= POW_APPROX_Q_SHIFT ? value >> (msb - POW_APPROX_Q_SHIFT) : value << (POW_APPROX_Q_SHIFT - msb);
        uint256 z = Math.mulDiv(mantissaQ - POW_APPROX_Q, POW_APPROX_Q, mantissaQ + POW_APPROX_Q);
        uint256 z2 = Math.mulDiv(z, z, POW_APPROX_Q);

        uint256 term = z;
        uint256 sum = term;
        uint256[6] memory divisors = [uint256(3), 5, 7, 9, 11, 13];
        for (uint256 i; i < divisors.length; ++i) {
            term = Math.mulDiv(term, z2, POW_APPROX_Q);
            sum += term / divisors[i];
        }

        uint256 fractionalQ = Math.mulDiv(sum * 2, POW_APPROX_LOG2_E_Q, POW_APPROX_Q);
        // msb is at most 255 and the Q40 fractional term is below one Q unit.
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(msb * POW_APPROX_Q + fractionalQ);
    }

    function _exp2HardWallScaledQ(int256 log2ValueQ) private pure returns (uint256) {
        int256 q = POW_APPROX_Q_I256;
        int256 integerPart = log2ValueQ / q;
        int256 fractionalPart = log2ValueQ - integerPart * q;
        if (fractionalPart < 0) {
            fractionalPart += q;
            integerPart -= 1;
        }

        // The normalization above guarantees fractionalPart is in [0, Q).
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 xQ = Math.mulDiv(uint256(fractionalPart), POW_APPROX_LN2_Q, POW_APPROX_Q);
        uint256 term = POW_APPROX_Q;
        uint256 expFractionQ = POW_APPROX_Q;
        for (uint256 divisor = 1; divisor <= 10; ++divisor) {
            term = Math.mulDiv(term, xQ, POW_APPROX_Q) / divisor;
            expFractionQ += term;
        }

        uint256 scaled = Math.mulDiv(expFractionQ, HARD_WALL_SCALE, POW_APPROX_Q);
        if (integerPart >= 0) {
            // This branch guarantees integerPart is nonnegative.
            // forge-lint: disable-next-line(unsafe-typecast)
            uint256 shift = uint256(integerPart);
            if (shift >= 256 || scaled > type(uint256).max >> shift) return type(uint256).max;
            return scaled << shift;
        }

        // This branch guarantees -integerPart is nonnegative.
        // forge-lint: disable-next-line(unsafe-typecast)
        uint256 negativeShift = uint256(-integerPart);
        return negativeShift >= 256 ? 0 : scaled >> negativeShift;
    }

    function _mulScaledSaturating(uint256 lhs, uint256 rhs) private pure returns (uint256) {
        if (lhs == 0 || rhs == 0) return 0;
        if (rhs <= HARD_WALL_SCALE) return Math.mulDiv(lhs, rhs, HARD_WALL_SCALE);
        uint256 maxLhs = Math.mulDiv(type(uint256).max, HARD_WALL_SCALE, rhs);
        if (lhs > maxLhs) return type(uint256).max;
        return Math.mulDiv(lhs, rhs, HARD_WALL_SCALE);
    }
}
