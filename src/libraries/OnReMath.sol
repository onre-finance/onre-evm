// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";

library OnReMath {
    uint256 internal constant PRICE_DECIMALS = 9;
    uint256 internal constant INT_SCALE = 1e18;
    uint256 internal constant APR_SCALE = 1_000_000;
    uint256 internal constant SECONDS_IN_DAY = 86_400;
    uint8 internal constant MAX_TOKEN_DECIMALS = 18;

    function calculateFee(uint256 amount, uint16 feeBasisPoints, uint16 maxBasisPoints)
        internal
        pure
        returns (uint256)
    {
        return Math.mulDiv(amount, feeBasisPoints, maxBasisPoints, Math.Rounding.Ceil);
    }

    function calculateFees(uint256 amount, uint16 feeBasisPoints, uint16 maxBasisPoints)
        internal
        pure
        returns (uint256 feeAmount, uint256 netAmount)
    {
        feeAmount = calculateFee(amount, feeBasisPoints, maxBasisPoints);
        netAmount = amount - feeAmount;
    }

    function calculateTokenOutAmount(
        uint256 tokenInAmount,
        uint256 price,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals
    ) internal pure returns (uint256) {
        if (tokenOutDecimals >= tokenInDecimals) {
            uint256 decimalMultiplier =
                10 ** (uint256(tokenOutDecimals) - uint256(tokenInDecimals) + PRICE_DECIMALS);
            return Math.mulDiv(tokenInAmount, decimalMultiplier, price);
        }

        uint256 decimalDivisor = 10 ** (uint256(tokenInDecimals) - uint256(tokenOutDecimals));
        return Math.mulDiv(tokenInAmount, 10 ** PRICE_DECIMALS, price * decimalDivisor);
    }

    function calculateRedemptionAssetOutAmount(
        uint256 onReTokenNetAmount,
        uint256 price,
        uint8 onReTokenDecimals,
        uint8 assetDecimals
    ) internal pure returns (uint256) {
        if (assetDecimals >= onReTokenDecimals) {
            uint256 decimalMultiplier =
                10 ** (uint256(assetDecimals) - uint256(onReTokenDecimals));
            return Math.mulDiv(onReTokenNetAmount, price * decimalMultiplier, 10 ** PRICE_DECIMALS);
        }

        uint256 decimalDivisor = 10 ** (uint256(onReTokenDecimals) - uint256(assetDecimals) + PRICE_DECIMALS);
        return Math.mulDiv(onReTokenNetAmount, price, decimalDivisor);
    }

    function calculateVectorPrice(uint256 apr, uint256 basePrice, uint256 elapsedTime) internal pure returns (uint256) {
        if (apr == 0 || elapsedTime == 0) {
            return basePrice;
        }

        uint256 dailyIncrement = _mulDivHalfUp(INT_SCALE, apr, APR_SCALE * 365);
        uint256 dailyFactor = INT_SCALE + dailyIncrement;
        uint256 fullDays = elapsedTime / SECONDS_IN_DAY;
        uint256 remainingSeconds = elapsedTime % SECONDS_IN_DAY;

        uint256 fullDayFactor = _powFixed(dailyFactor, fullDays, INT_SCALE);
        uint256 fullDayPrice = _mulDivHalfUp(basePrice, fullDayFactor, INT_SCALE);

        if (remainingSeconds == 0) {
            return fullDayPrice;
        }

        uint256 nextDayPrice = _mulDivHalfUp(fullDayPrice, dailyFactor, INT_SCALE);
        uint256 dailyDelta = nextDayPrice - fullDayPrice;
        uint256 partialDayDelta = _mulDivHalfUp(dailyDelta, remainingSeconds, SECONDS_IN_DAY);
        return fullDayPrice + partialDayDelta;
    }

    function calculateStepPrice(
        uint256 apr,
        uint256 basePrice,
        uint64 baseTime,
        uint64 priceFixDuration,
        uint256 currentTime
    ) internal pure returns (uint256) {
        uint256 elapsedSinceStart = currentTime - baseTime;
        uint256 currentStep = elapsedSinceStart / priceFixDuration;
        uint256 stepEndTime = (currentStep + 1) * priceFixDuration;

        return calculateVectorPrice(apr, basePrice, stepEndTime);
    }

    function calculateApyFromApr(uint256 apr) internal pure returns (uint256) {
        if (apr == 0) {
            return 0;
        }

        uint256 dailyIncrement = _mulDivHalfUp(INT_SCALE, apr, APR_SCALE * 365);
        uint256 compounded = _powFixed(INT_SCALE + dailyIncrement, 365, INT_SCALE);
        return _mulDivHalfUp(compounded - INT_SCALE, APR_SCALE, INT_SCALE);
    }

    function calculateTvl(uint256 circulatingSupply, uint256 nav, uint256 priceScale) internal pure returns (uint256) {
        return Math.mulDiv(circulatingSupply, nav, priceScale);
    }

    function calculateRedemptionVaultRefillAmount(
        uint256 tvl,
        uint16 vaultTargetBps,
        uint16 maxBasisPoints,
        uint8 assetDecimals,
        uint8 onReTokenDecimals,
        uint256 currentRedemptionVaultBalance,
        uint256 assetNetAmount
    ) internal pure returns (uint256) {
        if (vaultTargetBps == 0 || assetNetAmount == 0) {
            return 0;
        }

        uint256 targetInAssetDecimals = Math.mulDiv(
            tvl, uint256(vaultTargetBps) * 10 ** assetDecimals, uint256(maxBasisPoints) * 10 ** onReTokenDecimals
        );

        if (targetInAssetDecimals <= currentRedemptionVaultBalance) {
            return 0;
        }

        uint256 deficit = targetInAssetDecimals - currentRedemptionVaultBalance;
        return deficit < assetNetAmount ? deficit : assetNetAmount;
    }

    function _powFixed(uint256 base, uint256 exp, uint256 scale) private pure returns (uint256) {
        uint256 acc = scale;
        while (exp > 0) {
            if ((exp & 1) == 1) {
                acc = _mulDivHalfUp(acc, base, scale);
            }
            exp >>= 1;
            if (exp > 0) {
                base = _mulDivHalfUp(base, base, scale);
            }
        }

        return acc;
    }

    function _mulDivHalfUp(uint256 a, uint256 b, uint256 denominator) private pure returns (uint256) {
        uint256 result = Math.mulDiv(a, b, denominator);
        uint256 remainder = mulmod(a, b, denominator);
        uint256 halfDenominator = denominator / 2 + denominator % 2;
        if (remainder >= halfDenominator) {
            return result + 1;
        }
        return result;
    }
}
