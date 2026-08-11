// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Math} from "@openzeppelin/contracts/utils/math/Math.sol";
import {Test} from "forge-std/Test.sol";
import {OnReMath} from "../src/libraries/OnReMath.sol";

contract OnReMathTest is Test {
    uint16 private constant MAX_BASIS_POINTS = 10_000;
    uint8 private constant ONRE_DECIMALS = 9;
    uint8 private constant USDC_DECIMALS = 6;
    uint8 private constant DAI_DECIMALS = 18;
    uint256 private constant PRICE_SCALE = 1e9;
    uint256 private constant APR_SCALE = 1_000_000;
    uint256 private constant MAX_OPERATIONAL_PRICE = 100e9;
    uint256 private constant MAX_OPERATIONAL_ONRE_SUPPLY = 18_000_000_000e9;
    uint256 private constant MAX_OPERATIONAL_USDC_AMOUNT = 18_000_000_000e6;
    uint256 private constant MAX_OPERATIONAL_DAI_AMOUNT = 18_000_000_000e18;

    OnReMathFuzzHarness private math;

    function setUp() public {
        math = new OnReMathFuzzHarness();
    }

    function test_OperationalEighteenBillionValuesDoNotOverflow() public view {
        assertEq(
            math.calculateTokenOutAmount(MAX_OPERATIONAL_USDC_AMOUNT, PRICE_SCALE, USDC_DECIMALS, ONRE_DECIMALS),
            MAX_OPERATIONAL_ONRE_SUPPLY
        );
        assertEq(
            math.calculateRedemptionAssetOutAmount(
                MAX_OPERATIONAL_ONRE_SUPPLY, PRICE_SCALE, ONRE_DECIMALS, USDC_DECIMALS
            ),
            MAX_OPERATIONAL_USDC_AMOUNT
        );
        assertEq(math.calculateTvl(MAX_OPERATIONAL_ONRE_SUPPLY, PRICE_SCALE, PRICE_SCALE), MAX_OPERATIONAL_ONRE_SUPPLY);
        assertEq(
            math.calculateRedemptionVaultRefillAmount(
                MAX_OPERATIONAL_ONRE_SUPPLY,
                MAX_BASIS_POINTS,
                MAX_BASIS_POINTS,
                USDC_DECIMALS,
                ONRE_DECIMALS,
                0,
                MAX_OPERATIONAL_USDC_AMOUNT
            ),
            MAX_OPERATIONAL_USDC_AMOUNT
        );
    }

    function testFuzz_FeesMatchCeilAndNeverExceedAmount(uint256 amount, uint16 rawFeeBps) public view {
        uint16 feeBps = uint16(bound(uint256(rawFeeBps), 0, MAX_BASIS_POINTS));

        (uint256 feeAmount, uint256 netAmount) = math.calculateFees(amount, feeBps, MAX_BASIS_POINTS);
        uint256 expectedFeeAmount = Math.mulDiv(amount, feeBps, MAX_BASIS_POINTS, Math.Rounding.Ceil);

        assertEq(feeAmount, expectedFeeAmount);
        assertEq(netAmount, amount - feeAmount);
        assertEq(feeAmount + netAmount, amount);
        assertLe(feeAmount, amount);

        if (amount == 0 || feeBps == 0) {
            assertEq(feeAmount, 0);
            assertEq(netAmount, amount);
        }
        if (feeBps == MAX_BASIS_POINTS) {
            assertEq(feeAmount, amount);
            assertEq(netAmount, 0);
        }
    }

    function test_FeesHandleMaxUintWithoutProductOverflow() public view {
        (uint256 feeAmount, uint256 netAmount) =
            math.calculateFees(type(uint256).max, MAX_BASIS_POINTS, MAX_BASIS_POINTS);

        assertEq(feeAmount, type(uint256).max);
        assertEq(netAmount, 0);
    }

    function testFuzz_OfferQuoteSupportsEighteenBillionUsdcInputs(uint96 rawAssetAmount, uint64 rawPrice) public view {
        uint256 assetAmount = bound(uint256(rawAssetAmount), 1, MAX_OPERATIONAL_USDC_AMOUNT);
        uint256 price = bound(uint256(rawPrice), 1, MAX_OPERATIONAL_PRICE);

        uint256 tokenOut = math.calculateTokenOutAmount(assetAmount, price, USDC_DECIMALS, ONRE_DECIMALS);
        uint256 expectedTokenOut = Math.mulDiv(assetAmount, 1e12, price);

        assertEq(tokenOut, expectedTokenOut);
    }

    function testFuzz_OfferQuoteSupportsEighteenBillionDaiInputs(uint96 rawAssetAmount, uint64 rawPrice) public view {
        uint256 assetAmount = bound(uint256(rawAssetAmount), 1, MAX_OPERATIONAL_DAI_AMOUNT);
        uint256 price = bound(uint256(rawPrice), 1, MAX_OPERATIONAL_PRICE);

        uint256 tokenOut = math.calculateTokenOutAmount(assetAmount, price, DAI_DECIMALS, ONRE_DECIMALS);
        uint256 expectedTokenOut = Math.mulDiv(assetAmount, PRICE_SCALE, price * 1e9);

        assertEq(tokenOut, expectedTokenOut);
    }

    function testFuzz_RedemptionQuoteSupportsEighteenBillionUsdcOutputs(uint96 rawOnReAmount, uint64 rawPrice)
        public
        view
    {
        uint256 onReAmount = bound(uint256(rawOnReAmount), 1, MAX_OPERATIONAL_ONRE_SUPPLY);
        uint256 price = bound(uint256(rawPrice), 1, MAX_OPERATIONAL_PRICE);

        uint256 assetOut = math.calculateRedemptionAssetOutAmount(onReAmount, price, ONRE_DECIMALS, USDC_DECIMALS);
        uint256 expectedAssetOut = Math.mulDiv(onReAmount, price, 1e12);

        assertEq(assetOut, expectedAssetOut);
    }

    function testFuzz_RedemptionQuoteSupportsEighteenBillionDaiOutputs(uint96 rawOnReAmount, uint64 rawPrice)
        public
        view
    {
        uint256 onReAmount = bound(uint256(rawOnReAmount), 1, MAX_OPERATIONAL_ONRE_SUPPLY);
        uint256 price = bound(uint256(rawPrice), 1, MAX_OPERATIONAL_PRICE);

        uint256 assetOut = math.calculateRedemptionAssetOutAmount(onReAmount, price, ONRE_DECIMALS, DAI_DECIMALS);
        uint256 expectedAssetOut = Math.mulDiv(onReAmount, price * 1e9, PRICE_SCALE);

        assertEq(assetOut, expectedAssetOut);
    }

    function testFuzz_TvlUsesFullPrecisionForOperationalSupply(uint96 rawSupply, uint64 rawNav) public view {
        uint256 circulatingSupply = bound(uint256(rawSupply), 0, MAX_OPERATIONAL_ONRE_SUPPLY);
        uint256 nav = bound(uint256(rawNav), 1, MAX_OPERATIONAL_PRICE);

        uint256 tvl = math.calculateTvl(circulatingSupply, nav, PRICE_SCALE);

        assertEq(tvl, Math.mulDiv(circulatingSupply, nav, PRICE_SCALE));
    }

    function testFuzz_RedemptionVaultRefillSupportsEighteenBillionTvl(
        uint96 rawTvl,
        uint16 rawVaultTargetBps,
        uint96 rawCurrentVault,
        uint96 rawAssetNet
    ) public view {
        uint256 tvl = bound(uint256(rawTvl), 1, MAX_OPERATIONAL_ONRE_SUPPLY);
        uint16 vaultTargetBps = uint16(bound(uint256(rawVaultTargetBps), 0, MAX_BASIS_POINTS));
        uint256 currentVault = bound(uint256(rawCurrentVault), 0, MAX_OPERATIONAL_USDC_AMOUNT);
        uint256 assetNetAmount = bound(uint256(rawAssetNet), 1, MAX_OPERATIONAL_USDC_AMOUNT);

        uint256 refill = math.calculateRedemptionVaultRefillAmount(
            tvl, vaultTargetBps, MAX_BASIS_POINTS, USDC_DECIMALS, ONRE_DECIMALS, currentVault, assetNetAmount
        );
        uint256 target = Math.mulDiv(tvl, uint256(vaultTargetBps) * 1e6, uint256(MAX_BASIS_POINTS) * 1e9);

        assertLe(refill, assetNetAmount);

        uint256 expectedRefill;
        if (vaultTargetBps > 0 && target > currentVault) {
            uint256 deficit = target - currentVault;
            expectedRefill = deficit < assetNetAmount ? deficit : assetNetAmount;
        }

        assertEq(refill, expectedRefill);
    }

    function testFuzz_VectorPriceCompoundsWithinOperationalBounds(
        uint64 rawApr,
        uint64 rawBasePrice,
        uint32 rawElapsedDays
    ) public view {
        uint256 apr = bound(uint256(rawApr), 0, APR_SCALE);
        uint256 basePrice = bound(uint256(rawBasePrice), 1, MAX_OPERATIONAL_PRICE);
        uint256 elapsedTime = bound(uint256(rawElapsedDays), 0, 3_650) * 1 days;

        uint256 price = math.calculateVectorPrice(apr, basePrice, elapsedTime);

        assertGe(price, basePrice);
        if (apr == 0 || elapsedTime == 0) {
            assertEq(price, basePrice);
        }
    }

    function test_VectorPriceCalculation() public view {
        uint256 apr = APR_SCALE / 10;
        uint256 basePrice = 1.086e9;
        uint256 elapsedTime = 150 days;

        uint256 price = math.calculateVectorPrice(apr, basePrice, elapsedTime);

        assertEq(price, 1.131553518e9);
    }

    function test_VectorPriceCalculationRoundsHalfUp() public view {
        uint256 price = math.calculateVectorPrice(APR_SCALE / 10, PRICE_SCALE, 1 days);

        assertEq(price, 1_000_273_973);
    }

    function testFuzz_ApyFromAprIsZeroOrAtLeastApr(uint64 rawApr) public view {
        uint256 apr = bound(uint256(rawApr), 0, APR_SCALE);

        uint256 apy = math.calculateApyFromApr(apr);

        if (apr == 0) {
            assertEq(apy, 0);
        } else {
            assertGe(apy, apr);
        }
    }

    function test_ExtremeInputsRevertInsteadOfWrapping() public {
        vm.expectRevert();
        math.calculateTokenOutAmount(type(uint256).max, 1, 0, 18);

        vm.expectRevert();
        math.calculateRedemptionAssetOutAmount(type(uint256).max, type(uint256).max, ONRE_DECIMALS, DAI_DECIMALS);

        vm.expectRevert();
        math.calculateTvl(type(uint256).max, type(uint256).max, PRICE_SCALE);

        vm.expectRevert();
        math.calculateRedemptionVaultRefillAmount(
            type(uint256).max, MAX_BASIS_POINTS, MAX_BASIS_POINTS, DAI_DECIMALS, 0, 0, type(uint256).max
        );
    }
}

contract OnReMathFuzzHarness {
    function calculateFees(uint256 amount, uint16 feeBasisPoints, uint16 maxBasisPoints)
        external
        pure
        returns (uint256 feeAmount, uint256 netAmount)
    {
        return OnReMath.calculateFees(amount, feeBasisPoints, maxBasisPoints);
    }

    function calculateTokenOutAmount(
        uint256 tokenInAmount,
        uint256 price,
        uint8 tokenInDecimals,
        uint8 tokenOutDecimals
    ) external pure returns (uint256) {
        return OnReMath.calculateTokenOutAmount(tokenInAmount, price, tokenInDecimals, tokenOutDecimals);
    }

    function calculateRedemptionAssetOutAmount(
        uint256 onReTokenNetAmount,
        uint256 price,
        uint8 onReTokenDecimals,
        uint8 assetDecimals
    ) external pure returns (uint256) {
        return OnReMath.calculateRedemptionAssetOutAmount(onReTokenNetAmount, price, onReTokenDecimals, assetDecimals);
    }

    function calculateVectorPrice(uint256 apr, uint256 basePrice, uint256 elapsedTime) external pure returns (uint256) {
        return OnReMath.calculateVectorPrice(apr, basePrice, elapsedTime);
    }

    function calculateApyFromApr(uint256 apr) external pure returns (uint256) {
        return OnReMath.calculateApyFromApr(apr);
    }

    function calculateTvl(uint256 circulatingSupply, uint256 nav, uint256 priceScale) external pure returns (uint256) {
        return OnReMath.calculateTvl(circulatingSupply, nav, priceScale);
    }

    function calculateRedemptionVaultRefillAmount(
        uint256 tvl,
        uint16 vaultTargetBps,
        uint16 maxBasisPoints,
        uint8 assetDecimals,
        uint8 onReTokenDecimals,
        uint256 currentRedemptionVaultBalance,
        uint256 assetNetAmount
    ) external pure returns (uint256) {
        return OnReMath.calculateRedemptionVaultRefillAmount(
            tvl,
            vaultTargetBps,
            maxBasisPoints,
            assetDecimals,
            onReTokenDecimals,
            currentRedemptionVaultBalance,
            assetNetAmount
        );
    }
}
