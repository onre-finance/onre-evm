// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "../src/types/OnReAppErrors.sol";
import "../src/types/OnReTypes.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import "./helpers/OnReAppTestBase.sol";

contract OnRePropRfqTest is OnReAppTestBase {
    function test_QuoterIdentitySupportsIndependentInstancesOfTheSameKind() public {
        bytes32 secondNavQuoterId = app.createQuoter(QuoterKind.Nav, 1);

        assertEq(secondNavQuoterId, OnReIds.quoterId(QuoterKind.Nav, 1));
        assertNotEq(secondNavQuoterId, navQuoterId);
        assertEq(app.getQuoter(secondNavQuoterId).instanceId, 1);

        app.setQuoterEnabled(secondNavQuoterId, false);
        assertTrue(app.getQuoter(secondNavQuoterId).disabled);
        assertFalse(app.getQuoter(navQuoterId).disabled);
    }

    function test_PropRfqQuoterSupportsIndependentConfiguredInstances() public {
        PropRfqQuoterConfig memory firstConfig = _basePropRfqTestConfig();
        PropRfqQuoterConfig memory secondConfig = _basePropRfqTestConfig();
        secondConfig.curvePegHaircutBps = 1_200;
        secondConfig.cadenceThreshold = 7;

        bytes32 firstId = app.createQuoter(QuoterKind.PropRfq, 0);
        bytes32 secondId = app.createQuoter(QuoterKind.PropRfq, 1);
        app.configurePropRfqQuoter(firstId, address(usd), address(onReToken), firstConfig);
        app.configurePropRfqQuoter(secondId, address(usd), address(onReToken), secondConfig);

        assertEq(firstId, OnReIds.quoterId(QuoterKind.PropRfq, 0));
        assertEq(secondId, OnReIds.quoterId(QuoterKind.PropRfq, 1));
        assertNotEq(firstId, secondId);

        PropRfqQuoterState memory first = app.getPropRfqQuoter(firstId);
        PropRfqQuoterState memory second = app.getPropRfqQuoter(secondId);
        assertEq(first.assetToken, address(usd));
        assertEq(first.onReToken, address(onReToken));
        assertEq(first.config.curvePegHaircutBps, 700);
        assertEq(second.config.curvePegHaircutBps, 1_200);
        assertEq(second.config.cadenceThreshold, 7);

        firstConfig.curveExponentScaled = 30_000;
        app.configurePropRfqQuoter(firstId, address(usd), address(onReToken), firstConfig);
        assertEq(app.getPropRfqQuoter(firstId).config.curveExponentScaled, 30_000);
        assertEq(app.getPropRfqQuoter(secondId).config.curveExponentScaled, 25_000);

        vm.expectRevert(NoChangeError.selector);
        app.configurePropRfqQuoter(firstId, address(usd), address(onReToken), firstConfig);
        MockUsd alternativeUsd = new MockUsd();
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidPropRfqPairError.selector, firstId, address(alternativeUsd), address(onReToken)
            )
        );
        app.configurePropRfqQuoter(firstId, address(alternativeUsd), address(onReToken), firstConfig);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidQuoterKindError.selector, navQuoterId, uint8(QuoterKind.PropRfq), uint8(QuoterKind.Nav)
            )
        );
        app.configurePropRfqQuoter(navQuoterId, address(usd), address(onReToken), firstConfig);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidQuoterKindError.selector, navQuoterId, uint8(QuoterKind.PropRfq), uint8(QuoterKind.Nav)
            )
        );
        app.getPropRfqQuoter(navQuoterId);
    }

    function test_PropRfqQuoterRequiresDedicatedConfigurationAndValidPairTokens() public {
        bytes32 propRfqId = app.createQuoter(QuoterKind.PropRfq, 0);
        assertEq(propRfqId, OnReIds.quoterId(QuoterKind.PropRfq, 0));
        assertTrue(app.getQuoter(propRfqId).exists);
        assertEq(app.getPropRfqQuoter(propRfqId).assetToken, address(0));

        vm.expectRevert(PropRfqConfigurationRequiredError.selector);
        app.updateOfferConfigReferences(
            permissionlessOfferId, propRfqId, feeConfigId, proceedsVaultId, liquidityVaultId
        );

        PropRfqQuoterConfig memory config = _basePropRfqTestConfig();
        vm.expectRevert(ZeroAddressError.selector);
        app.configurePropRfqQuoter(propRfqId, address(0), address(onReToken), config);
        vm.expectRevert(ZeroAddressError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(0), config);
        vm.expectRevert(InvalidTokenError.selector);
        app.configurePropRfqQuoter(propRfqId, address(onReToken), address(onReToken), config);

        MockUsd unregisteredOnReToken = new MockUsd();
        vm.expectRevert(abi.encodeWithSelector(TokenNotRegisteredError.selector, address(unregisteredOnReToken)));
        app.configurePropRfqQuoter(propRfqId, address(usd), address(unregisteredOnReToken), config);

        app.setOnReTokenEnabled(address(onReToken), false);
        vm.expectRevert(InvalidTokenError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);
    }

    function test_PropRfqQuoterValidatesEveryConfigBound() public {
        bytes32 propRfqId = app.createQuoter(QuoterKind.PropRfq, 0);
        PropRfqQuoterConfig memory config = _basePropRfqTestConfig();
        config.curveExponentScaled = 25_001;
        vm.expectRevert(InvalidAmountError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);

        config = _basePropRfqTestConfig();
        config.curveExponentScaled = 0;
        vm.expectRevert(InvalidAmountError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);

        config = _basePropRfqTestConfig();
        config.curveExponentScaled = 101_000;
        vm.expectRevert(InvalidAmountError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);

        config = _basePropRfqTestConfig();
        config.cadenceThreshold = 0;
        vm.expectRevert(InvalidAmountError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);

        config = _basePropRfqTestConfig();
        config.cadenceWaveScaled = 10_001;
        vm.expectRevert(InvalidAmountError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);

        config = _basePropRfqTestConfig();
        config.cadenceWaveScaled = 51_000;
        vm.expectRevert(InvalidAmountError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);

        config = _basePropRfqTestConfig();
        config.epochDurationSeconds = 0;
        vm.expectRevert(InvalidAmountError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);

        config = _basePropRfqTestConfig();
        config.wallSensitivityScaled = 0;
        vm.expectRevert(InvalidAmountError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);

        config = _basePropRfqTestConfig();
        config.curvePegHaircutBps = 10_001;
        vm.expectRevert(InvalidBasisPointsError.selector);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), config);
    }

    function test_PropRfqMathMatchesSolanaCurveAndCadenceVectors() public {
        PropRfqMathHarness harness = new PropRfqMathHarness();
        assertEq(harness.baseCurveOutput(100_000, 10_000_000, 700, 25_000), 99_999);
        assertEq(harness.baseCurveOutput(5_000_000, 10_000_000, 700, 25_000), 4_938_128);
        assertEq(harness.baseCurveOutput(5_000_000, 10_000_000, 700, 10_000), 4_825_000);
        assertEq(harness.baseCurveOutput(5_000_000, 10_000_000, 700, 20_000), 4_912_500);
        assertEq(harness.utilizationPower(0, 25_000), 0);
        assertEq(harness.utilizationPower(1_000_000_000_000, 25_000), 1_000_000_000_000);

        uint256[8] memory utilizations = [
            uint256(0),
            10_000_000_000,
            100_000_000_000,
            250_000_000_000,
            500_000_000_000,
            750_000_000_000,
            1_000_000_000_000,
            2_000_000_000_000
        ];
        uint256[8] memory expected = [
            uint256(0),
            24_922_118_380,
            156_862_745_098,
            242_424_242_424,
            296_296_296_296,
            320_000_000_000,
            333_333_333_333,
            333_333_333_333
        ];
        for (uint256 i; i < utilizations.length; ++i) {
            assertEq(harness.cadenceTarget(utilizations[i], 10_000), expected[i]);
        }
        assertEq(harness.cadenceTarget(250_000_000_000, 50_000), 1_000_000_000_000);
    }

    function testFuzz_PropRfqIntegerUtilizationPowerMatchesRepeatedFixedPointMultiplication(
        uint96 utilizationSeed,
        uint8 exponentSeed
    ) public {
        PropRfqMathHarness harness = new PropRfqMathHarness();
        uint256 scale = 1_000_000_000_000;
        uint256 utilization = bound(uint256(utilizationSeed), 1, 2 * scale);
        uint32 exponentSteps = uint32(bound(uint256(exponentSeed), 1, 10));

        uint256 expected = scale;
        for (uint32 i; i < exponentSteps; ++i) {
            expected = expected * utilization / scale;
        }

        assertEq(harness.utilizationPower(utilization, exponentSteps * 10_000), expected);
    }

    function test_PropRfqQuoterIsPermissionlessAndBoundToItsPair() public {
        bytes32 propRfqId = _createConfiguredPropRfqQuoter(0, _basePropRfqTestConfig());

        vm.expectRevert(InvalidFlowQuoterError.selector);
        app.updateOfferConfigReferences(permissionedOfferId, propRfqId, feeConfigId, proceedsVaultId, liquidityVaultId);

        MockUsd alternativeUsd = new MockUsd();
        bytes32 expectedOfferId =
            OnReIds.offerConfigId(address(alternativeUsd), address(onReToken), OfferFlow.Permissionless);
        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidPropRfqPairError.selector, propRfqId, address(alternativeUsd), address(onReToken)
            )
        );
        app.makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: address(alternativeUsd),
                tokenOut: address(onReToken),
                flow: OfferFlow.Permissionless,
                quoterId: propRfqId,
                feeConfigId: feeConfigId,
                proceedsVaultId: proceedsVaultId,
                liquidityVaultId: liquidityVaultId
            })
        );
        assertFalse(app.getOfferConfig(expectedOfferId).exists);
    }

    function test_PropRfqSellUsesFeeConfigMinimumHardWallAndRecordsPressure() public {
        PropRfqQuoterConfig memory config = _basePropRfqTestConfig();
        config.cadenceThreshold = 1;
        bytes32 propRfqId = _createConfiguredPropRfqQuoter(0, config);
        bytes32 sellOfferId = _makeOffer(
            address(onReToken), address(usd), OfferFlow.Permissionless, propRfqId, feeConfigId, liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, 100_000_000, feeVaultId);

        _depositLiquidity(10_000_000);
        ExecutionAccounting memory firstPreview = app.previewExecution(sellOfferId, 1_000_000_000);
        assertEq(firstPreview.feeAmount, 100_000_000);
        assertEq(firstPreview.netInputAmount, 900_000_000);
        assertLt(firstPreview.amountOut, 900_000);
        assertGt(firstPreview.amountOut, 0);

        onReToken.mint(user, 2_000_000_000);
        vm.startPrank(user);
        onReToken.approve(address(app), 2_000_000_000);
        app.takeOffer(_takeOfferParams(sellOfferId, 1_000_000_000));
        vm.stopPrank();

        PropRfqQuoterState memory afterFirstSell = app.getPropRfqQuoter(propRfqId);
        assertEq(afterFirstSell.currentSellValueStable, 900_000);
        assertEq(afterFirstSell.currentSellTradeCount, 1);
        assertLt(app.previewExecution(sellOfferId, 1_000_000_000).amountOut, firstPreview.amountOut);
    }

    function test_PropRfqSellHardWallUsesLiquidityVaultTvlTarget() public {
        bytes32 propRfqId = _createConfiguredPropRfqQuoter(0, _basePropRfqTestConfig());
        bytes32 sellOfferId = _makeOffer(
            address(onReToken), address(usd), OfferFlow.Permissionless, propRfqId, feeConfigId, liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, 0, feeVaultId);
        _depositLiquidity(20_000_000);
        onReToken.mint(user, 1_000_000_000);

        uint256 uncappedAmountOut = app.previewExecution(sellOfferId, 1_000_000_000).amountOut;
        app.updateConfigurableVault(liquidityVaultId, vaultDestination, 5_000);
        uint256 cappedAmountOut = app.previewExecution(sellOfferId, 1_000_000_000).amountOut;
        assertLt(cappedAmountOut, uncappedAmountOut);
    }

    function test_PropRfqBuyUsesNavAndRelievesSharedInstancePressure() public {
        bytes32 propRfqId = _createConfiguredPropRfqQuoter(0, _basePropRfqTestConfig());
        app.updateOfferConfigReferences(
            permissionlessOfferId, propRfqId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
        bytes32 sellOfferId = _makeOffer(
            address(onReToken), address(usd), OfferFlow.Permissionless, propRfqId, feeConfigId, liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, 0, feeVaultId);

        assertEq(app.previewExecution(permissionlessOfferId, 1_000_000).amountOut, 1_000_000_000);
        _depositLiquidity(10_000_000);
        onReToken.mint(user, 1_000_000_000);
        vm.startPrank(user);
        onReToken.approve(address(app), 1_000_000_000);
        app.takeOffer(_takeOfferParams(sellOfferId, 1_000_000_000));
        vm.stopPrank();
        uint256 pressuredAmountOut = app.previewExecution(sellOfferId, 1_000_000_000).amountOut;

        _fundAndApproveUsd(user, 1_000_000);
        vm.prank(user);
        app.takeOffer(_takeOfferParams(permissionlessOfferId, 1_000_000));

        PropRfqQuoterState memory state = app.getPropRfqQuoter(propRfqId);
        assertEq(state.currentBuyValueStable, 1_000_000);
        assertEq(state.currentSellValueStable, 1_000_000);
        assertEq(state.currentSellTradeCount, 1);
        assertGt(app.previewExecution(sellOfferId, 1_000_000_000).amountOut, pressuredAmountOut);
    }

    function test_PropRfqSellRejectsEveryLiquidityBoundary() public {
        bytes32 propRfqId = _createConfiguredPropRfqQuoter(0, _basePropRfqTestConfig());
        bytes32 sellOfferId = _makeOffer(
            address(onReToken), address(usd), OfferFlow.Permissionless, propRfqId, feeConfigId, liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, 0, feeVaultId);

        vm.expectPartialRevert(InsufficientLiquidityError.selector);
        app.previewExecution(sellOfferId, 1_000_000_000);

        _depositLiquidity(500_000);
        vm.expectPartialRevert(InsufficientLiquidityError.selector);
        app.previewExecution(sellOfferId, 1_000_000_000);

        _depositLiquidity(1_500_000);
        onReToken.mint(user, 1);
        app.updateConfigurableVault(liquidityVaultId, vaultDestination, 1);
        vm.expectPartialRevert(InsufficientLiquidityError.selector);
        app.previewExecution(sellOfferId, 1_000_000_000);
    }

    function test_PropRfqSellRejectsDustThatRoundsToZeroOutput() public {
        bytes32 propRfqId = _createConfiguredPropRfqQuoter(0, _basePropRfqTestConfig());
        bytes32 sellOfferId = _makeOffer(
            address(onReToken), address(usd), OfferFlow.Permissionless, propRfqId, feeConfigId, liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, 0, feeVaultId);

        vm.expectPartialRevert(InsufficientLiquidityError.selector);
        app.previewExecution(sellOfferId, 1);

        _depositLiquidity(1_000_000);
        vm.expectRevert(InvalidAmountError.selector);
        app.previewExecution(sellOfferId, 1);
    }

    function test_PropRfqVolumeTrackerRollsAndExpiresEpochPressure() public {
        PropRfqQuoterConfig memory config = _basePropRfqTestConfig();
        config.epochDurationSeconds = 100;
        bytes32 propRfqId = _createConfiguredPropRfqQuoter(0, config);
        app.updateOfferConfigReferences(
            permissionlessOfferId, propRfqId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
        bytes32 sellOfferId = _makeOffer(
            address(onReToken), address(usd), OfferFlow.Permissionless, propRfqId, feeConfigId, liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, 0, feeVaultId);
        _depositLiquidity(10_000_000);

        onReToken.mint(user, 1_000_000_000);
        vm.prank(user);
        onReToken.approve(address(app), 1_000_000_000);
        _fundAndApproveUsd(user, 350_000);

        vm.prank(user);
        app.takeOffer(_takeOfferParams(sellOfferId, 1_000_000_000));

        vm.warp(101);
        vm.prank(user);
        app.takeOffer(_takeOfferParams(permissionlessOfferId, 250_000));

        PropRfqQuoterState memory rolled = app.getPropRfqQuoter(propRfqId);
        assertEq(rolled.epochStart, 101);
        assertEq(rolled.previousNetSellValueStable, 1_000_000);
        assertEq(rolled.currentSellValueStable, 0);
        assertEq(rolled.currentBuyValueStable, 250_000);
        assertEq(rolled.currentSellTradeCount, 0);

        vm.warp(301);
        vm.prank(user);
        app.takeOffer(_takeOfferParams(permissionlessOfferId, 100_000));

        PropRfqQuoterState memory expired = app.getPropRfqQuoter(propRfqId);
        assertEq(expired.epochStart, 301);
        assertEq(expired.previousNetSellValueStable, 0);
        assertEq(expired.currentSellValueStable, 0);
        assertEq(expired.currentBuyValueStable, 100_000);
        assertEq(expired.currentSellTradeCount, 0);
    }

    function test_PropRfqPressureUpdateRollsBackWhenTokenCollectionFails() public {
        bytes32 propRfqId = _createConfiguredPropRfqQuoter(0, _basePropRfqTestConfig());
        bytes32 sellOfferId = _makeOffer(
            address(onReToken), address(usd), OfferFlow.Permissionless, propRfqId, feeConfigId, liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, 0, feeVaultId);
        _depositLiquidity(10_000_000);
        onReToken.mint(user, 1_000_000_000);

        vm.prank(user);
        vm.expectRevert();
        app.takeOffer(_takeOfferParams(sellOfferId, 1_000_000_000));

        PropRfqQuoterState memory state = app.getPropRfqQuoter(propRfqId);
        assertEq(state.currentSellValueStable, 0);
        assertEq(state.currentSellTradeCount, 0);
    }
}
