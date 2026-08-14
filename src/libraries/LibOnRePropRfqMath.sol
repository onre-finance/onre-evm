// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

/// @notice Pure fixed-point curve and cadence math for the proprietary request-for-quote quoter.
/// @dev Mirrors `onre-sol` Prop AMM hard-wall math. Values use a 1e12 fixed-point scale.
library LibOnRePropRfqMath {
    uint256 internal constant HARD_WALL_SCALE = 1_000_000_000_000;

    uint32 private constant CURVE_EXPONENT_SCALE = 10_000;
    uint256 private constant CADENCE_WAVE_SCALE = 10_000;
    uint256 private constant CADENCE_WAVE_EASE = 8;
    uint256 private constant CADENCE_WAVE_CAP_DIVISOR = 3;
    uint256 private constant MAX_BASIS_POINTS = 10_000;

    uint256 private constant POW_APPROX_Q_SHIFT = 40;
    uint256 private constant POW_APPROX_Q = 1_099_511_627_776;
    uint256 private constant POW_APPROX_LN2_Q = 762_123_384_786;
    uint256 private constant POW_APPROX_LOG2_E_Q = 1_586_259_972_792;
    int256 private constant LOG2_HARD_WALL_SCALE_Q = 43_829_982_801_540;
    int256 private constant CURVE_EXPONENT_SCALE_I256 = 10_000;
    int256 private constant POW_APPROX_Q_I256 = 1_099_511_627_776;

    function _redemptionHaircutScaled(uint256 utilization, uint16 pegHaircutBps, uint32 exponentScaled)
        internal
        pure
        returns (uint256)
    {
        uint256 pegHaircut = Math.mulDiv(HARD_WALL_SCALE, pegHaircutBps, MAX_BASIS_POINTS);
        if (pegHaircut == 0) return 0;
        return Math.mulDiv(pegHaircut, _utilizationPowerScaled(utilization, exponentScaled), HARD_WALL_SCALE);
    }

    function _cadenceWaveTargetHaircutScaled(uint256 utilization, uint256 waveYScaled) internal pure returns (uint256) {
        if (waveYScaled == 0) return 0;
        uint256 normalized = utilization < HARD_WALL_SCALE ? utilization : HARD_WALL_SCALE;
        if (normalized == 0) return 0;

        uint256 easedNumerator = normalized * CADENCE_WAVE_EASE;
        uint256 easedRise = Math.mulDiv(easedNumerator, HARD_WALL_SCALE, easedNumerator + HARD_WALL_SCALE - normalized);
        uint256 target = Math.mulDiv(easedRise, waveYScaled, CADENCE_WAVE_SCALE * CADENCE_WAVE_CAP_DIVISOR);
        return target < HARD_WALL_SCALE ? target : HARD_WALL_SCALE;
    }

    function _utilizationPowerScaled(uint256 utilization, uint32 exponentScaled) internal pure returns (uint256) {
        if (utilization == 0) return 0;
        if (utilization == HARD_WALL_SCALE) return HARD_WALL_SCALE;
        if (exponentScaled % CURVE_EXPONENT_SCALE == 0) {
            return _integerUtilizationPowerScaled(utilization, exponentScaled / CURVE_EXPONENT_SCALE);
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
            --integerPart;
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
