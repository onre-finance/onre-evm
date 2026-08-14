// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {
    ApproverAlreadyExistsError,
    BothApproversFilledError,
    ConfigurableVaultAlreadyExistsError,
    ConfigurableVaultNotFoundError,
    DuplicateVectorStartTimeError,
    ExactAssetDebitRequiredError,
    ExactAssetTransferRequiredError,
    ExcludedSupplyAddressAlreadyExistsError,
    ExcludedSupplyAddressNotFoundError,
    FeeConfigAlreadyExistsError,
    FeeConfigDisabledError,
    FeeConfigNotFoundError,
    FulfillmentAmountExceedsRemainingError,
    FulfillmentRequestAlreadyExistsError,
    FulfillmentRequestNotFoundError,
    InsufficientBalanceError,
    InsufficientLiquidityError,
    InvalidAmountError,
    InvalidApprovalError,
    InvalidBasisPointsError,
    InvalidConfigurableVaultKindError,
    InvalidDecimalsError,
    InvalidFeeError,
    InvalidFlowQuoterError,
    InvalidOfferDirectionError,
    InvalidPropRfqPairError,
    InvalidQuoterKindError,
    InvalidTokenError,
    InvalidVectorOrderError,
    KilledError,
    LiquidityVaultRequiredError,
    MinimumAmountOutNotMetError,
    MissingConfigurableVaultDestinationError,
    NoActiveVectorError,
    NoChangeError,
    NotApproverError,
    OfferConfigAlreadyExistsError,
    OfferConfigDisabledError,
    OfferConfigNotFoundError,
    PricerAlreadyExistsError,
    PricerDisabledError,
    PricerNotFoundError,
    PropRfqConfigurationRequiredError,
    QuoterAlreadyExistsError,
    QuoterDisabledError,
    QuoterNotFoundError,
    TakeOfferDeadlineExpiredError,
    TokenAlreadyRegisteredError,
    TokenNotRegisteredError,
    TooManyExcludedSupplyAddressesError,
    TooManyVectorsError,
    UnauthorizedError,
    VectorBaseTimeAfterStartTimeError,
    VectorIndexOutOfBoundsError,
    VectorNotFoundError,
    VectorStartTimeInPastError,
    WorkerOfferRequiresFulfillmentRequestError,
    ZeroAddressError,
    ZeroBalanceError
} from "../src/types/OnReAppErrors.sol";
import {IOnReToken} from "../src/IOnReToken.sol";
import {OnReToken} from "../src/OnReToken.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {LibOnRePropRfqMath} from "../src/libraries/LibOnRePropRfqMath.sol";
import {
    ApprovalMessage,
    ConfigurableVault,
    ConfigurableVaultKind,
    ExecutionAccounting,
    FeeConfig,
    FulfillmentRequest,
    InitializeParams,
    MakeOfferConfigParams,
    MarketStats,
    OfferConfig,
    OfferDirection,
    OfferFlow,
    OnReTokenConfig,
    Pricer,
    PricingDenomination,
    PricingVector,
    PropRfqQuoterConfig,
    PropRfqQuoterState,
    Quoter,
    QuoterKind,
    TakeOfferParams
} from "../src/types/OnReTypes.sol";
import {OnReDiamondTestHelper} from "./helpers/OnReDiamondTestHelper.sol";

contract OnReAppTest is Test, OnReDiamondTestHelper {
    bytes32 private constant APPROVAL_TYPEHASH = keccak256("ApprovalMessage(address user,uint64 expiry)");
    bytes32 private constant APP_STORAGE_LOCATION = 0x31164558df59313d3ca3903acf513b2eda293f9424839a72cebf9d8c78813700;
    uint256 private constant APPROVER_KEY = 0xA11CE;
    uint256 private constant INVENTORY_AMOUNT = 1_000_000_000e9;

    IDiamondProxy private app;
    OnReToken private onReToken;
    MockUsd private usd;

    address private worker = makeAddr("worker");
    address private admin = makeAddr("admin");
    address private user = makeAddr("user");
    address private vaultDestination = makeAddr("vaultDestination");
    address private inventorySource = makeAddr("inventorySource");
    address private approver;

    bytes32 private pricerId;
    bytes32 private navQuoterId;
    bytes32 private navPermissionlessQuoterId;
    bytes32 private feeVaultId;
    bytes32 private proceedsVaultId;
    bytes32 private liquidityVaultId;
    bytes32 private feeConfigId;
    bytes32 private permissionedOfferId;
    bytes32 private permissionlessOfferId;
    bytes32 private workerOfferId;

    function setUp() public {
        vm.warp(1);
        approver = vm.addr(APPROVER_KEY);

        address[] memory approvers = new address[](1);
        approvers[0] = approver;
        app = _deployDiamondApp(
            InitializeParams({
                boss: address(this), admin: admin, worker: worker, upgrader: makeAddr("upgrader"), approvers: approvers
            })
        );

        onReToken = _deployToken(address(app));
        usd = new MockUsd();

        onReToken.mint(inventorySource, INVENTORY_AMOUNT);
        vm.prank(inventorySource);
        onReToken.approve(address(app), type(uint256).max);
        app.registerOnReToken(address(onReToken), inventorySource);

        pricerId = app.createPricer(address(onReToken), PricingDenomination.Usd);
        app.addPricingVector(
            pricerId, PricingVector({startTime: 1, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );

        navQuoterId = app.createQuoter(QuoterKind.Nav, 0);
        navPermissionlessQuoterId = app.createQuoter(QuoterKind.NavPermissionless, 0);

        feeVaultId = app.createConfigurableVault(ConfigurableVaultKind.Fee, 0, vaultDestination, 0);
        proceedsVaultId = app.createConfigurableVault(ConfigurableVaultKind.Proceeds, 0, vaultDestination, 0);
        liquidityVaultId = app.createConfigurableVault(ConfigurableVaultKind.Liquidity, 0, vaultDestination, 0);
        feeConfigId = app.createFeeConfig(0, 100, 0, feeVaultId);

        permissionedOfferId = _makeOffer(
            address(usd), address(onReToken), OfferFlow.Permissioned, navQuoterId, feeConfigId, liquidityVaultId
        );
        permissionlessOfferId = _makeOffer(
            address(usd),
            address(onReToken),
            OfferFlow.Permissionless,
            navPermissionlessQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        workerOfferId =
            _makeOffer(address(onReToken), address(usd), OfferFlow.Worker, navQuoterId, feeConfigId, liquidityVaultId);
    }

    function test_InitializesRolesAndCanonicalDomainRecords() public view {
        assertTrue(app.hasRole(app.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(app.hasRole(app.ADMIN_ROLE(), admin));
        assertTrue(app.hasRole(app.WORKER_ROLE(), worker));
        assertFalse(app.hasRole(app.ADMIN_ROLE(), address(this)));
        assertFalse(app.hasRole(app.WORKER_ROLE(), address(this)));

        OnReTokenConfig memory tokenConfig = app.getOnReTokenConfig(address(onReToken));
        assertTrue(tokenConfig.enabled);
        assertEq(tokenConfig.decimals, 9);
        assertEq(tokenConfig.inventorySource, inventorySource);

        Pricer memory pricer = app.getPricer(pricerId);
        assertEq(pricerId, OnReIds._pricerId(address(onReToken), PricingDenomination.Usd));
        assertEq(pricer.onReToken, address(onReToken));
        assertEq(uint8(pricer.denomination), uint8(PricingDenomination.Usd));
        assertEq(pricer.vectorCount, 1);
        assertTrue(pricer.exists);

        Quoter memory nav = app.getQuoter(navQuoterId);
        assertEq(uint8(nav.kind), uint8(QuoterKind.Nav));
        assertEq(nav.instanceId, 0);

        FeeConfig memory fee = app.getFeeConfig(feeConfigId);
        assertEq(fee.basisPoints, 100);
        assertEq(fee.feeVaultId, feeVaultId);
        assertTrue(fee.enabled);

        ConfigurableVault memory liquidity = app.getConfigurableVault(liquidityVaultId);
        assertEq(uint8(liquidity.kind), uint8(ConfigurableVaultKind.Liquidity));
    }

    function test_QuoterIdentitySupportsIndependentInstancesOfTheSameKind() public {
        bytes32 secondNavQuoterId = app.createQuoter(QuoterKind.Nav, 1);

        assertEq(secondNavQuoterId, OnReIds._quoterId(QuoterKind.Nav, 1));
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

    function test_FeeConfigRejectsMinimumThatConsumesGrossInput() public {
        app.updateFeeConfig(feeConfigId, 0, 1_000_000, feeVaultId);

        vm.expectRevert(InvalidAmountError.selector);
        app.previewExecution(permissionlessOfferId, 1_000_000);
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

    function test_OfferIdentityIncludesDirectedPairAndFlow() public view {
        assertEq(permissionedOfferId, OnReIds._offerConfigId(address(usd), address(onReToken), OfferFlow.Permissioned));
        assertEq(
            permissionlessOfferId, OnReIds._offerConfigId(address(usd), address(onReToken), OfferFlow.Permissionless)
        );
        assertEq(workerOfferId, OnReIds._offerConfigId(address(onReToken), address(usd), OfferFlow.Worker));
        assertTrue(permissionedOfferId != permissionlessOfferId);

        OfferConfig memory permissioned = app.getOfferConfig(permissionedOfferId);
        OfferConfig memory workerConfig = app.getOfferConfig(workerOfferId);
        assertEq(uint8(permissioned.direction), uint8(OfferDirection.AssetToOnRe));
        assertEq(uint8(workerConfig.direction), uint8(OfferDirection.OnReToAsset));
        assertEq(permissioned.tokenInDecimals, 6);
        assertEq(permissioned.tokenOutDecimals, 9);
        assertEq(workerConfig.tokenInDecimals, 9);
        assertEq(workerConfig.tokenOutDecimals, 6);
    }

    function test_OfferCreationRejectsWrongFlowQuoterAndWorkerDirection() public {
        MockUsd alternativeUsd = new MockUsd();
        vm.expectRevert(InvalidFlowQuoterError.selector);
        _makeOffer(
            address(alternativeUsd),
            address(onReToken),
            OfferFlow.Permissionless,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );

        bytes32 secondFee = app.createFeeConfig(1, 0, 0, feeVaultId);
        vm.expectRevert(InvalidOfferDirectionError.selector);
        _makeOffer(
            address(alternativeUsd), address(onReToken), OfferFlow.Worker, navQuoterId, secondFee, liquidityVaultId
        );
    }

    function test_OfferReferenceUpdateRejectsWrongFlowQuoter() public {
        vm.expectRevert(InvalidFlowQuoterError.selector);
        app.updateOfferConfigReferences(
            permissionedOfferId, navPermissionlessQuoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
        assertEq(app.getOfferConfig(permissionedOfferId).quoterId, navQuoterId);

        vm.expectRevert(InvalidFlowQuoterError.selector);
        app.updateOfferConfigReferences(
            permissionlessOfferId, navQuoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
        assertEq(app.getOfferConfig(permissionlessOfferId).quoterId, navPermissionlessQuoterId);
    }

    function test_PricerOwnsVectorsAndDrivesMarketStats() public {
        assertEq(app.currentPrice(pricerId), 1e9);
        PricingVector memory vector = app.getPricingVector(pricerId, 0);
        assertEq(vector.basePrice, 1e9);

        onReToken.mint(user, 250e9);
        MarketStats memory stats = app.marketStats(address(onReToken));
        assertEq(stats.nav, 1e9);
        assertEq(stats.circulatingSupply, 250e9);
        assertEq(stats.tvl, 250e9);

        app.addPricingVector(
            pricerId, PricingVector({startTime: 2, baseTime: 2, basePrice: 2e9, apr: 0, priceFixDuration: 1 days})
        );
        vm.warp(2);
        assertEq(app.currentPrice(pricerId), 2e9);
        assertEq(app.marketStats(address(onReToken)).nav, 2e9);
    }

    function test_PricingVectorLifecycleAndValidationBranches() public {
        vm.expectRevert(abi.encodeWithSelector(PricerAlreadyExistsError.selector, pricerId));
        app.createPricer(address(onReToken), PricingDenomination.Usd);

        vm.expectRevert(InvalidAmountError.selector);
        app.addPricingVector(
            pricerId, PricingVector({startTime: 2, baseTime: 1, basePrice: 0, apr: 0, priceFixDuration: 1 days})
        );

        vm.expectRevert(abi.encodeWithSelector(VectorBaseTimeAfterStartTimeError.selector, uint64(3), uint64(2)));
        app.addPricingVector(
            pricerId, PricingVector({startTime: 2, baseTime: 3, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );

        PricingVector memory futureVector =
            PricingVector({startTime: 5, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days});
        app.addPricingVector(pricerId, futureVector);

        vm.expectRevert(abi.encodeWithSelector(DuplicateVectorStartTimeError.selector, uint64(5)));
        app.addPricingVector(pricerId, futureVector);

        vm.expectRevert(InvalidVectorOrderError.selector);
        app.addPricingVector(
            pricerId, PricingVector({startTime: 4, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );

        vm.expectRevert(abi.encodeWithSelector(VectorNotFoundError.selector, uint64(6)));
        app.deletePricingVector(pricerId, 6);
        app.deletePricingVector(pricerId, 5);

        vm.expectRevert(abi.encodeWithSelector(VectorStartTimeInPastError.selector, uint64(1), uint64(1)));
        app.deletePricingVector(pricerId, 1);

        for (uint64 startTime = 2; startTime <= 10; ++startTime) {
            app.addPricingVector(
                pricerId,
                PricingVector({startTime: startTime, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
            );
        }
        vm.expectRevert(TooManyVectorsError.selector);
        app.addPricingVector(
            pricerId, PricingVector({startTime: 11, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );

        app.deleteAllPricingVectors(pricerId);
        assertEq(app.getPricer(pricerId).vectorCount, 0);
        vm.expectRevert(abi.encodeWithSelector(NoActiveVectorError.selector, pricerId));
        app.currentPrice(pricerId);
    }

    function test_TakeOfferPermissionedRequiresApprovalAndRoutesInputFee() public {
        uint256 inputAmount = 100e6;
        _fundAndApproveUsd(user, inputAmount);

        ApprovalMessage memory approval = ApprovalMessage({user: user, expiry: 1 days});
        bytes memory signature = _signApproval(approval);

        vm.prank(user);
        uint256 amountOut =
            app.takeOffer(_permissionedTakeOfferParams(permissionedOfferId, inputAmount, approval, signature));

        assertEq(amountOut, 99e9);
        assertEq(onReToken.balanceOf(user), 99e9);
        assertEq(app.configurableVaultBalance(feeVaultId, address(usd)), 1e6);
        assertEq(app.configurableVaultBalance(proceedsVaultId, address(usd)), 99e6);
        assertEq(usd.balanceOf(address(app)), inputAmount);
        assertEq(onReToken.balanceOf(inventorySource), INVENTORY_AMOUNT - amountOut);
        assertEq(onReToken.allowance(inventorySource, address(app)), type(uint256).max);

        _fundAndApproveUsd(user, inputAmount);
        TakeOfferParams memory missingSignature =
            _permissionedTakeOfferParams(permissionedOfferId, inputAmount, approval, "");
        vm.expectRevert(InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(missingSignature);
    }

    function test_TakeOfferPermissionlessUsesConfiguredQuoterWithoutApproval() public {
        uint256 inputAmount = 50e6;
        _fundAndApproveUsd(user, inputAmount);
        vm.prank(user);
        uint256 amountOut = app.takeOffer(_takeOfferParams(permissionlessOfferId, inputAmount));

        assertEq(amountOut, 49_500_000_000);
        assertEq(onReToken.balanceOf(user), amountOut);

        ExecutionAccounting memory preview = app.previewExecution(permissionlessOfferId, inputAmount);
        assertEq(preview.price, 1e9);
        assertEq(preview.amountOut, amountOut);

        TakeOfferParams memory unexpectedApproval = _takeOfferParams(permissionlessOfferId, 1);
        unexpectedApproval.approval = ApprovalMessage({user: user, expiry: 1 days});
        unexpectedApproval.signature = hex"01";
        vm.expectRevert(InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(unexpectedApproval);
    }

    function test_TakeOfferDispatchRejectsWorkerAndEnforcesUserProtections() public {
        TakeOfferParams memory workerParams = _takeOfferParams(workerOfferId, 1);
        vm.expectRevert(abi.encodeWithSelector(WorkerOfferRequiresFulfillmentRequestError.selector, workerOfferId));
        vm.prank(user);
        app.takeOffer(workerParams);

        TakeOfferParams memory expiredParams = _takeOfferParams(permissionlessOfferId, 50e6);
        expiredParams.deadline = 0;
        vm.expectRevert(abi.encodeWithSelector(TakeOfferDeadlineExpiredError.selector, uint64(0)));
        vm.prank(user);
        app.takeOffer(expiredParams);

        TakeOfferParams memory slippageParams = _takeOfferParams(permissionlessOfferId, 50e6);
        slippageParams.minimumAmountOut = 49_500_000_001;
        vm.expectRevert(abi.encodeWithSelector(MinimumAmountOutNotMetError.selector, 49_500_000_001, 49_500_000_000));
        vm.prank(user);
        app.takeOffer(slippageParams);
    }

    function test_TakeOfferPermissionedReverseBurnsInputAndPaysFromLiquidity() public {
        bytes32 reversePermissioned = _makeOffer(
            address(onReToken), address(usd), OfferFlow.Permissioned, navQuoterId, feeConfigId, liquidityVaultId
        );
        _depositLiquidity(200e6);
        onReToken.mint(user, 100e9);
        vm.prank(user);
        onReToken.approve(address(app), 100e9);

        ApprovalMessage memory approval = ApprovalMessage({user: user, expiry: 1 days});
        vm.prank(user);
        uint256 amountOut =
            app.takeOffer(_permissionedTakeOfferParams(reversePermissioned, 100e9, approval, _signApproval(approval)));

        assertEq(amountOut, 99e6);
        assertEq(usd.balanceOf(user), 99e6);
        assertEq(onReToken.totalSupply(), INVENTORY_AMOUNT + 1e9);
        assertEq(app.configurableVaultBalance(feeVaultId, address(onReToken)), 1e9);
        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), 101e6);
    }

    function test_WorkerRequestPartiallyFillsAtCurrentPriceAndFullyCloses() public {
        _depositLiquidity(300e6);
        onReToken.mint(user, 100e9);
        vm.prank(user);
        onReToken.approve(address(app), 100e9);

        vm.prank(user);
        bytes32 requestKey = app.createFulfillmentRequest(workerOfferId, 7, 100e9);
        assertEq(requestKey, OnReIds._fulfillmentRequestId(workerOfferId, user, 7));
        assertEq(onReToken.balanceOf(address(app)), 100e9);

        vm.prank(worker);
        uint256 firstAmountOut = app.fulfillWorkerRequest(requestKey, 40e9);
        assertEq(firstAmountOut, 39_600_000);
        FulfillmentRequest memory request = app.getFulfillmentRequest(requestKey);
        assertEq(request.fulfilledInputAmount, 40e9);

        app.addPricingVector(
            pricerId, PricingVector({startTime: 2, baseTime: 2, basePrice: 2e9, apr: 0, priceFixDuration: 1 days})
        );
        vm.warp(2);
        vm.prank(worker);
        uint256 secondAmountOut = app.fulfillWorkerRequest(requestKey, 60e9);

        assertEq(secondAmountOut, 118_800_000);
        assertEq(usd.balanceOf(user), 158_400_000);
        assertEq(onReToken.totalSupply(), INVENTORY_AMOUNT + 1e9);
        assertEq(app.configurableVaultBalance(feeVaultId, address(onReToken)), 1e9);
        assertFalse(app.getFulfillmentRequest(requestKey).exists);
    }

    function test_WorkerRequestCancellationReturnsOnlyUnfilledInput() public {
        _depositLiquidity(100e6);
        onReToken.mint(user, 100e9);
        vm.startPrank(user);
        onReToken.approve(address(app), 100e9);
        bytes32 requestKey = app.createFulfillmentRequest(workerOfferId, 8, 100e9);
        vm.stopPrank();

        vm.prank(worker);
        app.fulfillWorkerRequest(requestKey, 40e9);
        vm.prank(user);
        app.cancelFulfillmentRequest(requestKey);

        assertEq(onReToken.balanceOf(user), 60e9);
        assertFalse(app.getFulfillmentRequest(requestKey).exists);
    }

    function test_WorkerCancellationRejectsExcessDiamondDebit() public {
        MockSenderPaysFeeToken taxedToken = new MockSenderPaysFeeToken(address(app));
        app.registerOnReToken(address(taxedToken), inventorySource);
        bytes32 taxedPricerId = app.createPricer(address(taxedToken), PricingDenomination.Usd);
        app.addPricingVector(
            taxedPricerId, PricingVector({startTime: 1, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );
        bytes32 taxedWorkerOfferId =
            _makeOffer(address(taxedToken), address(usd), OfferFlow.Worker, navQuoterId, feeConfigId, liquidityVaultId);

        taxedToken.mint(user, 100e9);
        vm.startPrank(user);
        taxedToken.approve(address(app), 100e9);
        bytes32 requestKey = app.createFulfillmentRequest(taxedWorkerOfferId, 88, 100e9);
        vm.stopPrank();
        taxedToken.mint(address(app), 1);

        vm.expectRevert(
            abi.encodeWithSelector(ExactAssetDebitRequiredError.selector, address(taxedToken), 100e9, 100e9 + 1)
        );
        vm.prank(user);
        app.cancelFulfillmentRequest(requestKey);

        assertTrue(app.getFulfillmentRequest(requestKey).exists);
        assertEq(taxedToken.balanceOf(address(app)), 100e9 + 1);
        assertEq(taxedToken.balanceOf(user), 0);
    }

    function test_WorkerFlowEnforcesRoleAndRemainingAmount() public {
        onReToken.mint(user, 10e9);
        vm.startPrank(user);
        onReToken.approve(address(app), 10e9);
        bytes32 requestKey = app.createFulfillmentRequest(workerOfferId, 9, 10e9);

        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, app.WORKER_ROLE())
        );
        app.fulfillWorkerRequest(requestKey, 1e9);
        vm.stopPrank();

        vm.expectRevert(abi.encodeWithSelector(FulfillmentAmountExceedsRemainingError.selector, requestKey, 11e9, 10e9));
        vm.prank(worker);
        app.fulfillWorkerRequest(requestKey, 11e9);
    }

    function test_FeeConfigIsReusableAndMutable() public {
        app.updateFeeConfig(feeConfigId, 200, 300_000, feeVaultId);
        ExecutionAccounting memory preview = app.previewExecution(permissionlessOfferId, 10e6);
        assertEq(app.getFeeConfig(feeConfigId).minimumFeeAmount, 300_000);
        assertEq(preview.feeAmount, 300_000);
        assertEq(preview.netInputAmount, 9_700_000);
        assertEq(preview.amountOut, 9_700_000_000);

        app.setFeeConfigEnabled(feeConfigId, false);
        vm.expectRevert(abi.encodeWithSelector(FeeConfigDisabledError.selector, feeConfigId));
        app.previewExecution(permissionedOfferId, 10e6);
    }

    function test_FeeConfigMinimumAppendPreservesMainStorageLayout() public {
        uint64 legacyInstanceId = 77;
        uint16 legacyBasisPoints = 250;
        bytes32 legacyFeeConfigId = OnReIds.feeConfigId(legacyInstanceId);
        bytes32 feeConfigsMappingSlot = bytes32(uint256(APP_STORAGE_LOCATION) + 3);
        bytes32 legacyFeeConfigSlot = keccak256(abi.encode(legacyFeeConfigId, feeConfigsMappingSlot));
        uint256 packedMainFields =
            uint256(legacyInstanceId) | uint256(legacyBasisPoints) << 64 | uint256(1) << 80 | uint256(1) << 88;

        vm.store(address(app), legacyFeeConfigSlot, feeVaultId);
        vm.store(address(app), bytes32(uint256(legacyFeeConfigSlot) + 1), bytes32(packedMainFields));

        FeeConfig memory legacyFeeConfig = app.getFeeConfig(legacyFeeConfigId);
        assertEq(legacyFeeConfig.feeVaultId, feeVaultId);
        assertEq(legacyFeeConfig.feeConfigId, legacyInstanceId);
        assertEq(legacyFeeConfig.basisPoints, legacyBasisPoints);
        assertTrue(legacyFeeConfig.enabled);
        assertTrue(legacyFeeConfig.exists);
        assertEq(legacyFeeConfig.minimumFeeAmount, 0);

        app.updateFeeConfig(legacyFeeConfigId, legacyBasisPoints, 300_000, feeVaultId);
        legacyFeeConfig = app.getFeeConfig(legacyFeeConfigId);
        assertEq(legacyFeeConfig.feeConfigId, legacyInstanceId);
        assertEq(legacyFeeConfig.basisPoints, legacyBasisPoints);
        assertTrue(legacyFeeConfig.enabled);
        assertTrue(legacyFeeConfig.exists);
        assertEq(legacyFeeConfig.minimumFeeAmount, 300_000);
    }

    function test_ForwardExecutionRefillsLiquidityBeforeProceeds() public {
        onReToken.mint(address(this), 1_000e9);
        bytes32 refillVault = app.createConfigurableVault(ConfigurableVaultKind.Liquidity, 1, vaultDestination, 1_000);
        bytes32 zeroFee = app.createFeeConfig(2, 0, 0, feeVaultId);
        app.updateOfferConfigReferences(
            permissionlessOfferId, navPermissionlessQuoterId, zeroFee, proceedsVaultId, refillVault
        );

        _fundAndApproveUsd(user, 150e6);
        vm.prank(user);
        app.takeOffer(_takeOfferParams(permissionlessOfferId, 150e6));

        assertEq(app.configurableVaultBalance(refillVault, address(usd)), 100e6);
        assertEq(app.configurableVaultBalance(proceedsVaultId, address(usd)), 50e6);
    }

    function test_ConfigurableVaultWithdrawalCanOnlyUseConfiguredDestination() public {
        usd.mint(address(this), 25e6);
        usd.approve(address(app), 25e6);
        app.depositConfigurableVault(proceedsVaultId, address(usd), 25e6);

        vm.prank(user);
        uint256 withdrawn = app.withdrawConfigurableVault(proceedsVaultId, address(usd), 0);
        assertEq(withdrawn, 25e6);
        assertEq(usd.balanceOf(vaultDestination), 25e6);
        assertEq(app.configurableVaultBalance(proceedsVaultId, address(usd)), 0);

        bytes32 noDestinationVault = app.createConfigurableVault(ConfigurableVaultKind.Fee, 5, address(0), 0);
        usd.mint(address(this), 1);
        usd.approve(address(app), 1);
        app.depositConfigurableVault(noDestinationVault, address(usd), 1);
        vm.expectRevert(abi.encodeWithSelector(MissingConfigurableVaultDestinationError.selector, noDestinationVault));
        app.withdrawConfigurableVault(noDestinationVault, address(usd), 1);
    }

    function test_ExactDepositRejectsExcessSenderDebit() public {
        MockSenderPaysFeeToken taxedToken = new MockSenderPaysFeeToken(user);
        bytes32 taxedVault = app.createConfigurableVault(ConfigurableVaultKind.Fee, 20, vaultDestination, 0);
        taxedToken.mint(user, 101);

        vm.startPrank(user);
        taxedToken.approve(address(app), 100);
        vm.expectRevert(abi.encodeWithSelector(ExactAssetDebitRequiredError.selector, address(taxedToken), 100, 101));
        app.depositConfigurableVault(taxedVault, address(taxedToken), 100);
        vm.stopPrank();

        assertEq(taxedToken.balanceOf(user), 101);
        assertEq(taxedToken.balanceOf(address(app)), 0);
        assertEq(app.configurableVaultBalance(taxedVault, address(taxedToken)), 0);
    }

    function test_ExactDepositRejectsShortRecipientCredit() public {
        MockRecipientPaysFeeToken taxedToken = new MockRecipientPaysFeeToken(address(app));
        bytes32 taxedVault = app.createConfigurableVault(ConfigurableVaultKind.Fee, 22, vaultDestination, 0);
        taxedToken.mint(user, 100);

        vm.startPrank(user);
        taxedToken.approve(address(app), 100);
        vm.expectRevert(abi.encodeWithSelector(ExactAssetTransferRequiredError.selector, address(taxedToken), 100, 99));
        app.depositConfigurableVault(taxedVault, address(taxedToken), 100);
        vm.stopPrank();

        assertEq(taxedToken.balanceOf(user), 100);
        assertEq(taxedToken.balanceOf(address(app)), 0);
        assertEq(app.configurableVaultBalance(taxedVault, address(taxedToken)), 0);
    }

    function test_ExactWithdrawalRejectsExcessDiamondDebit() public {
        MockSenderPaysFeeToken taxedToken = new MockSenderPaysFeeToken(address(app));
        bytes32 taxedVault = app.createConfigurableVault(ConfigurableVaultKind.Fee, 21, vaultDestination, 0);
        taxedToken.mint(address(this), 100);
        taxedToken.approve(address(app), 100);
        app.depositConfigurableVault(taxedVault, address(taxedToken), 100);
        taxedToken.mint(address(app), 1);

        vm.expectRevert(abi.encodeWithSelector(ExactAssetDebitRequiredError.selector, address(taxedToken), 50, 51));
        app.withdrawConfigurableVault(taxedVault, address(taxedToken), 50);

        assertEq(taxedToken.balanceOf(address(app)), 101);
        assertEq(taxedToken.balanceOf(vaultDestination), 0);
        assertEq(app.configurableVaultBalance(taxedVault, address(taxedToken)), 100);
    }

    function test_LiquidityVaultWithdrawalRequiresBoss() public {
        usd.mint(address(this), 25e6);
        usd.approve(address(app), 25e6);
        app.depositConfigurableVault(liquidityVaultId, address(usd), 25e6);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, app.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(admin);
        app.withdrawConfigurableVault(liquidityVaultId, address(usd), 0);

        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), 25e6);
        assertEq(usd.balanceOf(vaultDestination), 0);

        uint256 withdrawn = app.withdrawConfigurableVault(liquidityVaultId, address(usd), 0);
        assertEq(withdrawn, 25e6);
        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), 0);
        assertEq(usd.balanceOf(vaultDestination), 25e6);
    }

    function test_ConfigurableVaultAndFeeConfigurationGuards() public {
        vm.expectRevert(InvalidBasisPointsError.selector);
        app.createConfigurableVault(ConfigurableVaultKind.Fee, 12, vaultDestination, 1);

        vm.expectRevert(InvalidBasisPointsError.selector);
        app.updateConfigurableVault(liquidityVaultId, vaultDestination, 10_001);

        vm.expectRevert(abi.encodeWithSelector(ConfigurableVaultAlreadyExistsError.selector, feeVaultId));
        app.createConfigurableVault(ConfigurableVaultKind.Fee, 0, vaultDestination, 0);

        vm.expectRevert(InvalidFeeError.selector);
        app.createFeeConfig(12, 1_001, 0, feeVaultId);

        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidConfigurableVaultKindError.selector,
                proceedsVaultId,
                uint8(ConfigurableVaultKind.Fee),
                uint8(ConfigurableVaultKind.Proceeds)
            )
        );
        app.createFeeConfig(12, 0, 0, proceedsVaultId);

        vm.expectRevert(NoChangeError.selector);
        app.updateFeeConfig(feeConfigId, 100, 0, feeVaultId);
        vm.expectRevert(NoChangeError.selector);
        app.updateConfigurableVault(liquidityVaultId, vaultDestination, 0);

        vm.expectRevert(InvalidAmountError.selector);
        app.depositConfigurableVault(liquidityVaultId, address(usd), 0);
        vm.expectRevert(ZeroBalanceError.selector);
        app.withdrawConfigurableVault(liquidityVaultId, address(usd), 0);

        usd.mint(address(this), 1e6);
        usd.approve(address(app), 1e6);
        app.depositConfigurableVault(liquidityVaultId, address(usd), 1e6);
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceError.selector, 1e6, 2e6));
        app.withdrawConfigurableVault(liquidityVaultId, address(usd), 2e6);
    }

    function test_OfferAndComponentNoChangeDuplicateAndLiquidityGuards() public {
        vm.expectRevert(abi.encodeWithSelector(OfferConfigAlreadyExistsError.selector, permissionedOfferId));
        _makeOffer(address(usd), address(onReToken), OfferFlow.Permissioned, navQuoterId, feeConfigId, liquidityVaultId);

        vm.expectRevert(NoChangeError.selector);
        app.updateOfferConfigReferences(
            permissionedOfferId, navQuoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );

        vm.expectRevert(NoChangeError.selector);
        app.setOfferConfigEnabled(permissionedOfferId, true);
        vm.expectRevert(NoChangeError.selector);
        app.setPricerEnabled(pricerId, true);
        vm.expectRevert(NoChangeError.selector);
        app.setQuoterEnabled(navQuoterId, true);
        vm.expectRevert(NoChangeError.selector);
        app.setFeeConfigEnabled(feeConfigId, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                LiquidityVaultRequiredError.selector,
                OnReIds._offerConfigId(address(onReToken), address(usd), OfferFlow.Permissionless)
            )
        );
        _makeOffer(
            address(onReToken),
            address(usd),
            OfferFlow.Permissionless,
            navPermissionlessQuoterId,
            feeConfigId,
            bytes32(0)
        );
    }

    function test_FulfillmentRequestIdentityAuthorizationAndDuplicateGuards() public {
        onReToken.mint(user, 20e9);
        vm.startPrank(user);
        onReToken.approve(address(app), 20e9);
        bytes32 requestKey = app.createFulfillmentRequest(workerOfferId, 55, 10e9);
        vm.expectRevert(abi.encodeWithSelector(FulfillmentRequestAlreadyExistsError.selector, requestKey));
        app.createFulfillmentRequest(workerOfferId, 55, 10e9);
        vm.stopPrank();

        address stranger = makeAddr("stranger");
        vm.expectRevert(abi.encodeWithSelector(UnauthorizedError.selector, stranger));
        vm.prank(stranger);
        app.cancelFulfillmentRequest(requestKey);

        bytes32 missing = keccak256("missing request");
        vm.expectRevert(abi.encodeWithSelector(FulfillmentRequestNotFoundError.selector, missing));
        vm.prank(worker);
        app.fulfillWorkerRequest(missing, 1);

        vm.prank(worker);
        app.cancelFulfillmentRequest(requestKey);
        assertEq(onReToken.balanceOf(user), 20e9);
    }

    function test_TokenApproverAndEmergencyConfigurationLifecycle() public {
        address excluded = makeAddr("excluded");
        app.addExcludedSupplyAddress(address(onReToken), excluded);
        assertEq(app.getExcludedSupplyAccounts(address(onReToken)).length, 1);
        vm.expectRevert(
            abi.encodeWithSelector(ExcludedSupplyAddressAlreadyExistsError.selector, address(onReToken), excluded)
        );
        app.addExcludedSupplyAddress(address(onReToken), excluded);
        app.removeExcludedSupplyAddress(address(onReToken), excluded);

        address secondApprover = makeAddr("secondApprover");
        app.addApprover(secondApprover);
        app.removeApprover(secondApprover);
        vm.expectRevert(abi.encodeWithSelector(NotApproverError.selector, secondApprover));
        app.removeApprover(secondApprover);

        address newInventorySource = makeAddr("newInventorySource");
        app.setOnReTokenInventorySource(address(onReToken), newInventorySource);
        assertEq(app.getOnReTokenConfig(address(onReToken)).inventorySource, newInventorySource);
        vm.expectRevert(NoChangeError.selector);
        app.setOnReTokenInventorySource(address(onReToken), newInventorySource);
        app.setOnReTokenEnabled(address(onReToken), false);
        vm.expectRevert(NoChangeError.selector);
        app.setOnReTokenEnabled(address(onReToken), false);

        app.setKillSwitch(true);
        vm.expectRevert(NoChangeError.selector);
        app.setKillSwitch(true);
    }

    function test_TokenRegistrationRejectsInvalidInputsAndSupportsReenable() public {
        vm.expectRevert(ZeroAddressError.selector);
        app.registerOnReToken(address(0), inventorySource);

        OnReToken secondToken = _deployToken(address(app));
        vm.expectRevert(ZeroAddressError.selector);
        app.registerOnReToken(address(secondToken), address(0));

        vm.expectRevert(InvalidTokenError.selector);
        app.registerOnReToken(address(usd), inventorySource);

        app.setOnReTokenEnabled(address(onReToken), false);
        vm.expectRevert(abi.encodeWithSelector(TokenAlreadyRegisteredError.selector, address(onReToken)));
        app.registerOnReToken(address(onReToken), inventorySource);

        vm.expectRevert(InvalidTokenError.selector);
        app.createPricer(address(onReToken), PricingDenomination.Usd);
        app.setOnReTokenEnabled(address(onReToken), true);

        vm.expectRevert(ZeroAddressError.selector);
        app.setOnReTokenInventorySource(address(onReToken), address(0));

        vm.expectRevert(abi.encodeWithSelector(TokenNotRegisteredError.selector, address(usd)));
        app.setOnReTokenEnabled(address(usd), true);
        vm.expectRevert(abi.encodeWithSelector(TokenNotRegisteredError.selector, address(usd)));
        app.createPricer(address(usd), PricingDenomination.Usd);
    }

    function test_ExcludedSupplyAddressCapacityRemovalAndInventoryDeduplication() public {
        vm.expectRevert(ZeroAddressError.selector);
        app.addExcludedSupplyAddress(address(onReToken), address(0));
        vm.expectRevert(ZeroAddressError.selector);
        app.removeExcludedSupplyAddress(address(onReToken), address(0));

        address missing = makeAddr("missingExcluded");
        vm.expectRevert(
            abi.encodeWithSelector(ExcludedSupplyAddressNotFoundError.selector, address(onReToken), missing)
        );
        app.removeExcludedSupplyAddress(address(onReToken), missing);

        app.addExcludedSupplyAddress(address(onReToken), inventorySource);
        for (uint160 i = 1; i < 20; ++i) {
            app.addExcludedSupplyAddress(address(onReToken), address(10_000 + i));
        }
        vm.expectRevert(abi.encodeWithSelector(TooManyExcludedSupplyAddressesError.selector, address(onReToken)));
        app.addExcludedSupplyAddress(address(onReToken), address(20_000));

        assertEq(app.marketStats(address(onReToken)).circulatingSupply, 0);
        app.removeExcludedSupplyAddress(address(onReToken), inventorySource);
        app.removeExcludedSupplyAddress(address(onReToken), address(10_018));
        assertEq(app.getExcludedSupplyAccounts(address(onReToken)).length, 18);
    }

    function test_ApproverSlotValidationAndReuse() public {
        vm.expectRevert(ZeroAddressError.selector);
        app.addApprover(address(0));
        vm.expectRevert(ZeroAddressError.selector);
        app.removeApprover(address(0));

        vm.expectRevert(abi.encodeWithSelector(ApproverAlreadyExistsError.selector, approver));
        app.addApprover(approver);

        address secondApprover = makeAddr("secondApprover");
        app.addApprover(secondApprover);
        vm.expectRevert(abi.encodeWithSelector(ApproverAlreadyExistsError.selector, secondApprover));
        app.addApprover(secondApprover);

        vm.expectRevert(BothApproversFilledError.selector);
        app.addApprover(makeAddr("thirdApprover"));

        app.removeApprover(approver);
        address replacement = makeAddr("replacementApprover");
        app.addApprover(replacement);
        (, address approver1, address approver2) = app.appConfig();
        assertEq(approver1, replacement);
        assertEq(approver2, secondApprover);

        app.removeApprover(secondApprover);
    }

    function test_MissingComponentsZeroAmountsAndViewBoundsRevert() public {
        bytes32 missing = keccak256("missing");

        vm.expectRevert(abi.encodeWithSelector(PricerNotFoundError.selector, missing));
        app.currentPrice(missing);
        vm.expectRevert(abi.encodeWithSelector(QuoterNotFoundError.selector, missing));
        app.setQuoterEnabled(missing, false);
        vm.expectRevert(abi.encodeWithSelector(FeeConfigNotFoundError.selector, missing));
        app.updateFeeConfig(missing, 0, 0, feeVaultId);
        vm.expectRevert(abi.encodeWithSelector(ConfigurableVaultNotFoundError.selector, missing));
        app.updateConfigurableVault(missing, vaultDestination, 0);
        vm.expectRevert(abi.encodeWithSelector(OfferConfigNotFoundError.selector, missing));
        app.setOfferConfigEnabled(missing, false);
        vm.expectRevert(abi.encodeWithSelector(TokenNotRegisteredError.selector, address(usd)));
        app.marketStats(address(usd));

        vm.expectRevert(abi.encodeWithSelector(VectorIndexOutOfBoundsError.selector, uint8(1), uint8(1)));
        app.getPricingVector(pricerId, 1);
        vm.expectRevert(InvalidAmountError.selector);
        app.previewExecution(permissionlessOfferId, 0);

        vm.expectRevert(ZeroAddressError.selector);
        app.depositConfigurableVault(liquidityVaultId, address(0), 1);
        vm.expectRevert(ZeroAddressError.selector);
        app.withdrawConfigurableVault(liquidityVaultId, address(0), 1);

        app.setKillSwitch(true);
        vm.expectRevert(KilledError.selector);
        app.withdrawConfigurableVault(liquidityVaultId, address(usd), 1);
    }

    function test_OfferCreationAndReferenceValidationBranches() public {
        MockUsd alternativeUsd = new MockUsd();

        vm.expectRevert(ZeroAddressError.selector);
        _makeOffer(address(0), address(onReToken), OfferFlow.Permissioned, navQuoterId, feeConfigId, liquidityVaultId);
        vm.expectRevert(ZeroAddressError.selector);
        _makeOffer(
            address(alternativeUsd), address(0), OfferFlow.Permissioned, navQuoterId, feeConfigId, liquidityVaultId
        );
        vm.expectRevert(InvalidTokenError.selector);
        _makeOffer(
            address(alternativeUsd),
            address(alternativeUsd),
            OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );

        MockHighDecimals highDecimals = new MockHighDecimals();
        vm.expectRevert(InvalidDecimalsError.selector);
        _makeOffer(
            address(highDecimals),
            address(onReToken),
            OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        vm.expectRevert(InvalidDecimalsError.selector);
        _makeOffer(
            address(onReToken),
            address(highDecimals),
            OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );

        bytes32 missing = keccak256("missingReference");
        vm.expectRevert(abi.encodeWithSelector(QuoterNotFoundError.selector, missing));
        _makeOffer(
            address(alternativeUsd), address(onReToken), OfferFlow.Permissioned, missing, feeConfigId, liquidityVaultId
        );
        vm.expectRevert(abi.encodeWithSelector(FeeConfigNotFoundError.selector, missing));
        _makeOffer(
            address(alternativeUsd), address(onReToken), OfferFlow.Permissioned, navQuoterId, missing, liquidityVaultId
        );
        vm.expectRevert(abi.encodeWithSelector(ConfigurableVaultNotFoundError.selector, missing));
        _makeOffer(
            address(alternativeUsd), address(onReToken), OfferFlow.Permissioned, navQuoterId, feeConfigId, missing
        );

        vm.expectRevert(abi.encodeWithSelector(QuoterAlreadyExistsError.selector, navQuoterId));
        app.createQuoter(QuoterKind.Nav, 0);
        vm.expectRevert(abi.encodeWithSelector(FeeConfigAlreadyExistsError.selector, feeConfigId));
        app.createFeeConfig(0, 100, 0, feeVaultId);
    }

    function test_ApprovalBranchesAndInsufficientLiquidity() public {
        uint256 inputAmount = 1e6;
        _fundAndApproveUsd(user, inputAmount);

        ApprovalMessage memory wrongUser = ApprovalMessage({user: makeAddr("approvalOther"), expiry: 1 days});
        vm.expectRevert(InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(
            _permissionedTakeOfferParams(permissionedOfferId, inputAmount, wrongUser, _signApproval(wrongUser))
        );

        ApprovalMessage memory expired = ApprovalMessage({user: user, expiry: 0});
        vm.expectRevert(InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(_permissionedTakeOfferParams(permissionedOfferId, inputAmount, expired, _signApproval(expired)));

        uint256 secondApproverKey = 0xB0B;
        address secondApprover = vm.addr(secondApproverKey);
        app.addApprover(secondApprover);
        ApprovalMessage memory approval = ApprovalMessage({user: user, expiry: 1 days});
        vm.prank(user);
        app.takeOffer(
            _permissionedTakeOfferParams(
                permissionedOfferId, inputAmount, approval, _signApprovalWithKey(approval, secondApproverKey)
            )
        );

        TakeOfferParams memory expiryOnly = _takeOfferParams(permissionlessOfferId, 1);
        expiryOnly.approval.expiry = 1;
        vm.expectRevert(InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(expiryOnly);

        TakeOfferParams memory signatureOnly = _takeOfferParams(permissionlessOfferId, 1);
        signatureOnly.signature = hex"01";
        vm.expectRevert(InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(signatureOnly);

        bytes32 reversePermissionless = _makeOffer(
            address(onReToken),
            address(usd),
            OfferFlow.Permissionless,
            navPermissionlessQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, 0, feeVaultId);
        onReToken.mint(user, 1e9);
        vm.prank(user);
        onReToken.approve(address(app), 1e9);
        vm.expectRevert(
            abi.encodeWithSelector(InsufficientLiquidityError.selector, liquidityVaultId, address(usd), 0, 1e6)
        );
        vm.prank(user);
        app.takeOffer(_takeOfferParams(reversePermissionless, 1e9));
    }

    function test_FulfillmentRejectsNonWorkerOffersAndZeroAmounts() public {
        vm.expectRevert(InvalidFlowQuoterError.selector);
        vm.prank(user);
        app.createFulfillmentRequest(permissionlessOfferId, 1, 1);

        vm.expectRevert(InvalidAmountError.selector);
        vm.prank(user);
        app.createFulfillmentRequest(workerOfferId, 1, 0);

        onReToken.mint(user, 1e9);
        vm.startPrank(user);
        onReToken.approve(address(app), 1e9);
        bytes32 requestKey = app.createFulfillmentRequest(workerOfferId, 2, 1e9);
        vm.stopPrank();

        vm.expectRevert(InvalidAmountError.selector);
        vm.prank(worker);
        app.fulfillWorkerRequest(requestKey, 0);
    }

    function test_PricingVectorZeroFieldsPastStartAndCompaction() public {
        PricingVector memory vector =
            PricingVector({startTime: 2, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days});

        vector.startTime = 0;
        vm.expectRevert(InvalidAmountError.selector);
        app.addPricingVector(pricerId, vector);
        vector.startTime = 2;
        vector.baseTime = 0;
        vm.expectRevert(InvalidAmountError.selector);
        app.addPricingVector(pricerId, vector);
        vector.baseTime = 1;
        vector.priceFixDuration = 0;
        vm.expectRevert(InvalidAmountError.selector);
        app.addPricingVector(pricerId, vector);

        vector.priceFixDuration = 1 days;
        for (uint64 startTime = 2; startTime <= 4; ++startTime) {
            vector.startTime = startTime;
            app.addPricingVector(pricerId, vector);
        }
        vm.warp(3);
        vector.startTime = 6;
        app.addPricingVector(pricerId, vector);
        assertEq(app.getPricer(pricerId).vectorCount, 4);
        assertEq(app.getPricingVector(pricerId, 0).startTime, 2);

        vm.warp(7);
        vector.startTime = 7;
        app.addPricingVector(pricerId, vector);
        assertEq(app.getPricer(pricerId).vectorCount, 2);
        assertEq(app.getPricingVector(pricerId, 0).startTime, 6);
        assertEq(app.getPricingVector(pricerId, 1).startTime, 7);

        vector.startTime = 6;
        vm.expectRevert(abi.encodeWithSelector(VectorStartTimeInPastError.selector, uint64(6), uint64(7)));
        app.addPricingVector(pricerId, vector);
    }

    function test_MarketStatsReportsNegativeNavAdjustment() public {
        app.addPricingVector(
            pricerId,
            PricingVector({startTime: 2, baseTime: 2, basePrice: 500_000_000, apr: 0, priceFixDuration: 1 days})
        );
        vm.warp(2);
        assertEq(app.marketStats(address(onReToken)).navAdjustment, -500_000_000);
    }

    function test_DisabledComponentsAndKillSwitchStopExecution() public {
        app.setPricerEnabled(pricerId, false);
        vm.expectRevert(abi.encodeWithSelector(PricerDisabledError.selector, pricerId));
        app.previewExecution(permissionedOfferId, 1e6);
        app.setPricerEnabled(pricerId, true);

        app.setQuoterEnabled(navQuoterId, false);
        vm.expectRevert(abi.encodeWithSelector(QuoterDisabledError.selector, navQuoterId));
        app.previewExecution(permissionedOfferId, 1e6);
        app.setQuoterEnabled(navQuoterId, true);

        app.setOfferConfigEnabled(permissionedOfferId, false);
        vm.expectRevert(abi.encodeWithSelector(OfferConfigDisabledError.selector, permissionedOfferId));
        app.previewExecution(permissionedOfferId, 1e6);
        app.setOfferConfigEnabled(permissionedOfferId, true);

        app.setKillSwitch(true);
        vm.expectRevert(KilledError.selector);
        app.previewExecution(permissionedOfferId, 1e6);
    }

    function test_AdminCanOnlyEnableKillSwitch() public {
        vm.expectRevert(
            abi.encodeWithSelector(IAccessControl.AccessControlUnauthorizedAccount.selector, user, app.ADMIN_ROLE())
        );
        vm.prank(user);
        app.setKillSwitch(true);

        vm.prank(admin);
        app.setKillSwitch(true);
        (bool isKilled,,) = app.appConfig();
        assertTrue(isKilled);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, app.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(admin);
        app.setKillSwitch(false);

        app.setKillSwitch(false);
        (isKilled,,) = app.appConfig();
        assertFalse(isKilled);
    }

    function test_ConfigOperationsAreRoleProtected() public {
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, app.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        app.createQuoter(QuoterKind.Nav, 99);

        bytes32 propRfqId = app.createQuoter(QuoterKind.PropRfq, 99);
        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, app.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        app.configurePropRfqQuoter(propRfqId, address(usd), address(onReToken), _basePropRfqTestConfig());

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, app.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(admin);
        app.createConfigurableVault(ConfigurableVaultKind.Fee, 99, admin, 0);
    }

    function testFuzz_NavPreviewMatchesDecimalScaling(uint96 rawInput) public view {
        uint256 inputAmount = bound(uint256(rawInput), 2, 1_000_000e6);
        ExecutionAccounting memory preview = app.previewExecution(permissionlessOfferId, inputAmount);
        assertEq(preview.grossInputAmount, inputAmount);
        assertEq(preview.amountOut, preview.netInputAmount * 1_000);
    }

    function _makeOffer(
        address tokenIn,
        address tokenOut,
        OfferFlow flow,
        bytes32 quoter,
        bytes32 feeConfig,
        bytes32 liquidityVault
    ) private returns (bytes32) {
        return app.makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                flow: flow,
                quoterId: quoter,
                feeConfigId: feeConfig,
                proceedsVaultId: proceedsVaultId,
                liquidityVaultId: liquidityVault
            })
        );
    }

    function _createConfiguredPropRfqQuoter(uint64 instanceId, PropRfqQuoterConfig memory config)
        private
        returns (bytes32 quoterId)
    {
        quoterId = app.createQuoter(QuoterKind.PropRfq, instanceId);
        app.configurePropRfqQuoter(quoterId, address(usd), address(onReToken), config);
    }

    function _fundAndApproveUsd(address account, uint256 amount) private {
        usd.mint(account, amount);
        vm.prank(account);
        usd.approve(address(app), amount);
    }

    function _basePropRfqTestConfig() private pure returns (PropRfqQuoterConfig memory) {
        return PropRfqQuoterConfig({
            curvePegHaircutBps: 700,
            curveExponentScaled: 25_000,
            cadenceThreshold: 20,
            cadenceWaveScaled: 10_000,
            epochDurationSeconds: 86_400,
            wallSensitivityScaled: 20_000
        });
    }

    function _depositLiquidity(uint256 amount) private {
        usd.mint(address(this), amount);
        usd.approve(address(app), amount);
        app.depositConfigurableVault(liquidityVaultId, address(usd), amount);
    }

    function _takeOfferParams(bytes32 offerConfigId, uint256 grossInputAmount)
        private
        view
        returns (TakeOfferParams memory params)
    {
        params.offerConfigId = offerConfigId;
        params.grossInputAmount = grossInputAmount;
        params.deadline = uint64(block.timestamp + 1 days);
    }

    function _permissionedTakeOfferParams(
        bytes32 offerConfigId,
        uint256 grossInputAmount,
        ApprovalMessage memory approval,
        bytes memory signature
    ) private view returns (TakeOfferParams memory params) {
        params = _takeOfferParams(offerConfigId, grossInputAmount);
        params.approval = approval;
        params.signature = signature;
    }

    function _signApproval(ApprovalMessage memory approval) private view returns (bytes memory) {
        return _signApprovalWithKey(approval, APPROVER_KEY);
    }

    function _signApprovalWithKey(ApprovalMessage memory approval, uint256 key) private view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _approvalDigest(approval));
        return abi.encodePacked(r, s, v);
    }

    function _approvalDigest(ApprovalMessage memory approval) private view returns (bytes32) {
        bytes32 domainTypehash =
            keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)");
        bytes32 domainSeparator =
            keccak256(abi.encode(domainTypehash, keccak256("OnReApp"), keccak256("1"), block.chainid, address(app)));
        bytes32 structHash = keccak256(abi.encode(APPROVAL_TYPEHASH, approval.user, approval.expiry));
        return keccak256(abi.encodePacked(hex"1901", domainSeparator, structHash));
    }

    function _deployToken(address burner) private returns (OnReToken token) {
        OnReToken implementation = new OnReToken();
        address[] memory initialMinters = new address[](1);
        initialMinters[0] = address(this);
        address[] memory initialBurners = new address[](1);
        initialBurners[0] = burner;
        IOnReToken.InitializeParams memory params = IOnReToken.InitializeParams({
            name: "OnRe USD",
            symbol: "ONusd",
            admin: address(this),
            ccipAdmin: address(this),
            initialMinters: initialMinters,
            initialBurners: initialBurners
        });
        token = OnReToken(
            address(new ERC1967Proxy(address(implementation), abi.encodeCall(OnReToken.initialize, (params))))
        );
    }
}

contract PropRfqMathHarness {
    uint256 private constant HARD_WALL_SCALE = 1_000_000_000_000;

    function baseCurveOutput(uint256 rawAmount, uint256 effectiveLiquidity, uint16 pegBps, uint32 exponent)
        external
        pure
        returns (uint256)
    {
        uint256 utilization = rawAmount * HARD_WALL_SCALE / effectiveLiquidity;
        uint256 haircut = LibOnRePropRfqMath._redemptionHaircutScaled(utilization, pegBps, exponent);
        return rawAmount * (HARD_WALL_SCALE - haircut) / HARD_WALL_SCALE;
    }

    function cadenceTarget(uint256 utilization, uint256 waveYScaled) external pure returns (uint256) {
        return LibOnRePropRfqMath._cadenceWaveTargetHaircutScaled(utilization, waveYScaled);
    }

    function utilizationPower(uint256 utilization, uint32 exponentScaled) external pure returns (uint256) {
        return LibOnRePropRfqMath._utilizationPowerScaled(utilization, exponentScaled);
    }
}

contract MockUsd is ERC20 {
    constructor() ERC20("USD Coin", "USDC") {}

    function decimals() public pure override returns (uint8) {
        return 6;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }
}

contract MockHighDecimals is ERC20 {
    constructor() ERC20("High Decimals", "HIGH") {}

    function decimals() public pure override returns (uint8) {
        return 19;
    }
}

contract MockSenderPaysFeeToken is ERC20 {
    address private immutable feeSource;

    constructor(address feeSource_) ERC20("Sender Pays Fee", "SPF") {
        feeSource = feeSource_;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (from == feeSource && to != address(0)) {
            _burn(from, 1);
        }
    }
}

contract MockRecipientPaysFeeToken is ERC20 {
    address private immutable feeRecipient;

    constructor(address feeRecipient_) ERC20("Recipient Pays Fee", "RPF") {
        feeRecipient = feeRecipient_;
    }

    function decimals() public pure override returns (uint8) {
        return 9;
    }

    function mint(address account, uint256 amount) external {
        _mint(account, amount);
    }

    function _update(address from, address to, uint256 amount) internal override {
        super._update(from, to, amount);
        if (to == feeRecipient && from != address(0)) {
            _burn(to, 1);
        }
    }
}
