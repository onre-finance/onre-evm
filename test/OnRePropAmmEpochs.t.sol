// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "../src/types/OnReTypes.sol";
import "./helpers/OnReAppTestBase.sol";

contract OnRePropAmmEpochsTest is OnReAppTestBase {
    uint256 private constant START = 1_000;
    uint256 private constant D = 100;
    bytes32 private pairId;
    bytes32 private sellOfferId;

    function setUp() public override {
        super.setUp();
        vm.warp(START);
        PropAmmConfig memory config = _basePropAmmTestConfig();
        config.epochDurationSeconds = uint64(D);
        config.cadenceWaveScaled = 0;
        config.curvePegHaircutBps = 100;
        config.curveExponentScaled = 10_000;
        config.wallSensitivityScaled = 10_000;
        pairId = _createConfiguredPropAmm(0, config);
        app.updateOfferConfigReferences(permissionlessOfferId, pairId, feeConfigId, proceedsVaultId, liquidityVaultId);
        sellOfferId = _makeOffer(
            address(managedToken), address(usd), OfferFlow.Permissionless, pairId, feeConfigId, liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, 0, feeVaultId);
        _depositLiquidity(1_000e6);
        managedToken.mint(user, 500e9);
        vm.prank(user);
        managedToken.approve(address(app), type(uint256).max);
        _fundAndApproveUsd(user, 100e6);
    }

    function test_QuotesDecayAtFixedBoundariesWithoutExecution() public {
        _sell(100e9);
        uint256[6] memory offsets = [uint256(0), 99, 100, 150, 199, 200];
        uint256[6] memory history = [uint256(100e6), 100e6, 100e6, 50e6, 1e6, 0];
        for (uint256 i; i < offsets.length; ++i) {
            vm.warp(START + offsets[i]);
            _assertQuote(20e9, history[i] + 20e6);
        }
        // Read-only quotes project the rollover without changing storage.
        PropAmmState memory state = app.getPropAmmState(pairId);
        assertEq(state.epochStart, START);
        assertEq(state.currentSellValueStable, 100e6);
        assertEq(state.previousNetSellValueStable, 0);
    }

    function test_SellAt199UsesOnePercentAndDoesNotExtendOldPressure() public {
        _sell(100e9);
        vm.warp(START + 199);
        _assertQuote(20e9, 21e6); // 1 historical + 20 pending.
        uint256 quoted = app.previewExecution(sellOfferId, 20e9).amountOut;
        uint256 beforeBalance = usd.balanceOf(user);
        assertEq(_sell(20e9), quoted);
        assertEq(usd.balanceOf(user) - beforeBalance, quoted);
        PropAmmState memory state = app.getPropAmmState(pairId);
        assertEq(state.epochStart, START + D);
        assertEq(state.previousNetSellValueStable, 100e6);
        assertEq(state.currentSellValueStable, 20e6);
        assertEq(state.currentSellTradeCount, 1);
        _assertQuote(5e9, 26e6); // 1 historical + 20 current + 5 pending.

        vm.warp(START + 200);
        _assertQuote(5e9, 25e6); // Original 100 is gone; the late 20 now decays.
        _sell(5e9);
        state = app.getPropAmmState(pairId);
        assertEq(state.epochStart, START + 200);
        assertEq(state.previousNetSellValueStable, 20e6);
        assertEq(state.currentSellValueStable, 5e6);
        assertEq(state.currentSellTradeCount, 1);
        vm.warp(START + 299);
        _assertQuote(1e9, 6_200_000); // 0.2 historical + 5 current + 1 pending.
        vm.warp(START + 300);
        _assertQuote(1e9, 6e6);
    }

    function test_BuyAt199KeepsBoundaryAndExpiresBuyReliefAt200() public {
        _sell(100e9);
        vm.warp(START + 199);
        _buy(30e6);
        PropAmmState memory state = app.getPropAmmState(pairId);
        assertEq(state.epochStart, START + D);
        assertEq(state.previousNetSellValueStable, 100e6);
        assertEq(state.currentBuyValueStable, 30e6);
        assertEq(state.currentSellValueStable, 0);
        assertEq(state.currentSellTradeCount, 0);
        _assertQuote(20e9, 21e6);
        vm.warp(START + 200);
        _assertQuote(20e9, 20e6);
        _sell(20e9);
        state = app.getPropAmmState(pairId);
        assertEq(state.epochStart, START + 200);
        assertEq(state.previousNetSellValueStable, 0);
        assertEq(state.currentBuyValueStable, 0);
    }

    function test_MultipleTradesAccumulateWithoutShiftingBoundaries() public {
        _sell(40e9);
        vm.warp(START + 30);
        _sell(30e9);
        vm.warp(START + 80);
        _sell(30e9);
        assertEq(app.getPropAmmState(pairId).epochStart, START);
        vm.warp(START + 199);
        _assertQuote(20e9, 21e6);
    }

    function test_CurrentBuysReduceNetPressureBeforeItsScheduledDecay() public {
        _sell(100e9);
        vm.warp(START + 99);
        _buy(40e6);
        vm.warp(START + 150);
        _assertQuote(20e9, 50e6); // (100 - 40) * 50% + 20 pending.
        vm.warp(START + 199);
        _assertQuote(20e9, 20_600_000);
        _sell(20e9);
        assertEq(app.getPropAmmState(pairId).previousNetSellValueStable, 60e6);
    }

    function test_LongInactivityResetsCountersButPreservesEpochAlignment() public {
        _sell(100e9);
        vm.warp(START + 349);
        _assertQuote(20e9, 20e6);
        _buy(10e6);
        PropAmmState memory state = app.getPropAmmState(pairId);
        assertEq(state.epochStart, START + 300);
        assertEq(state.previousNetSellValueStable, 0);
        assertEq(state.currentSellValueStable, 0);
        assertEq(state.currentBuyValueStable, 10e6);
        assertEq(state.currentSellTradeCount, 0);
        vm.warp(START + 400);
        _sell(20e9);
        state = app.getPropAmmState(pairId);
        assertEq(state.epochStart, START + 400);
        assertEq(state.currentBuyValueStable, 0);
        assertEq(state.previousNetSellValueStable, 0);
    }

    function test_CadenceResetsAtScheduledBoundaryAfterLateSell() public {
        PropAmmConfig memory config = _basePropAmmTestConfig();
        config.epochDurationSeconds = uint64(D);
        config.cadenceThreshold = 2;
        config.cadenceWaveScaled = 5_000;
        config.curvePegHaircutBps = 100;
        config.curveExponentScaled = 10_000;
        config.wallSensitivityScaled = 10_000;
        app.configurePropAmm(pairId, address(usd), address(managedToken), config);
        _sell(100e9);
        vm.warp(START + 199);
        _assertQuote(20e9, 21e6); // Expired cadence contributes nothing to this quote.
        _sell(20e9);
        assertEq(app.getPropAmmState(pairId).currentSellTradeCount, 1);
        vm.warp(START + 200);
        _assertQuote(5e9, 25e6); // The late sell's cadence also expires at the boundary.
        _sell(5e9);
        assertEq(app.getPropAmmState(pairId).currentSellTradeCount, 1);
    }

    function testFuzz_LateSellUsesScheduledDecayAndAlignedEpoch(uint32 offset) public {
        offset = uint32(bound(offset, D, 10_000));
        _sell(100e9);
        vm.warp(START + offset);
        uint256 remainingHistory = offset < 2 * D ? (2 * D - offset) * 1e6 : 0;
        _assertQuote(20e9, remainingHistory + 20e6);
        uint256 quoted = app.previewExecution(sellOfferId, 20e9).amountOut;
        assertEq(_sell(20e9), quoted);
        PropAmmState memory state = app.getPropAmmState(pairId);
        assertEq(state.epochStart, START + offset - offset % D);
        assertEq(state.previousNetSellValueStable, offset < 2 * D ? 100e6 : 0);
        assertEq(state.currentSellValueStable, 20e6);
        _assertQuote(1e9, remainingHistory + 21e6);
    }

    function _sell(uint256 amount) private returns (uint256) {
        vm.prank(user);
        return app.takeOffer(_takeOfferParams(sellOfferId, amount));
    }

    function _buy(uint256 amount) private {
        vm.prank(user);
        app.takeOffer(_takeOfferParams(permissionlessOfferId, amount));
    }

    function _assertQuote(uint256 input, uint256 expectedPressure) private view {
        // Independent linear-curve fixture: 1% peg, exponent 1, sensitivity 1,
        // no cadence/fees/reserve cap, NAV $1, 9-decimal ONyc and 6-decimal USD.
        uint256 liquidity = app.configurableVaultBalance(liquidityVaultId, address(usd));
        uint256 rawOutput = input / 1_000;
        uint256 wall = liquidity * 10_000 / (10_000 + 10_000 * expectedPressure / liquidity);
        uint256 utilization = rawOutput * 1e12 / wall;
        uint256 haircut = utilization / 100;
        uint256 expectedOutput = rawOutput * (1e12 - haircut) / 1e12;
        assertEq(app.previewExecution(sellOfferId, input).amountOut, expectedOutput);
    }
}
