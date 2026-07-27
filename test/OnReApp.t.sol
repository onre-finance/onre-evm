// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ERC1967Proxy} from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";
import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";
import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {Test} from "forge-std/Test.sol";
import {IOnReApp} from "../src/interfaces/IOnReApp.sol";
import {IOnReAppErrors} from "../src/interfaces/IOnReAppErrors.sol";
import {IOnReToken} from "../src/interfaces/IOnReToken.sol";
import {OnReToken} from "../src/OnReToken.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {OnReTypes} from "../src/types/OnReTypes.sol";
import {OnReDiamondTestHelper} from "./helpers/OnReDiamondTestHelper.sol";

contract OnReAppTest is Test, OnReDiamondTestHelper {
    bytes32 private constant APPROVAL_TYPEHASH = keccak256("ApprovalMessage(address user,uint64 expiry)");
    uint256 private constant APPROVER_KEY = 0xA11CE;
    uint256 private constant INVENTORY_AMOUNT = 1_000_000_000e9;

    IOnReApp private app;
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
            OnReTypes.InitializeParams({
                boss: address(this), admin: admin, worker: worker, upgrader: makeAddr("upgrader"), approvers: approvers
            })
        );

        onReToken = _deployToken(address(app));
        usd = new MockUsd();

        onReToken.mint(inventorySource, INVENTORY_AMOUNT);
        vm.prank(inventorySource);
        onReToken.approve(address(app), type(uint256).max);
        app.registerOnReToken(address(onReToken), inventorySource);

        pricerId = app.createPricer(address(onReToken), OnReTypes.PricingDenomination.Usd);
        app.addPricingVector(
            pricerId,
            OnReTypes.PricingVector({startTime: 1, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );

        navQuoterId = app.createQuoter(OnReTypes.QuoterKind.Nav, 0);
        navPermissionlessQuoterId = app.createQuoter(OnReTypes.QuoterKind.NavPermissionless, 0);

        feeVaultId = app.createConfigurableVault(OnReTypes.ConfigurableVaultKind.Fee, 0, vaultDestination, 0);
        proceedsVaultId = app.createConfigurableVault(OnReTypes.ConfigurableVaultKind.Proceeds, 0, vaultDestination, 0);
        liquidityVaultId =
            app.createConfigurableVault(OnReTypes.ConfigurableVaultKind.Liquidity, 0, vaultDestination, 0);
        feeConfigId = app.createFeeConfig(0, 100, feeVaultId);

        permissionedOfferId = _makeOffer(
            address(usd),
            address(onReToken),
            OnReTypes.OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        permissionlessOfferId = _makeOffer(
            address(usd),
            address(onReToken),
            OnReTypes.OfferFlow.Permissionless,
            navPermissionlessQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        workerOfferId = _makeOffer(
            address(onReToken), address(usd), OnReTypes.OfferFlow.Worker, navQuoterId, feeConfigId, liquidityVaultId
        );
    }

    function test_InitializesRolesAndCanonicalDomainRecords() public view {
        assertTrue(app.hasRole(app.DEFAULT_ADMIN_ROLE(), address(this)));
        assertTrue(app.hasRole(app.ADMIN_ROLE(), admin));
        assertTrue(app.hasRole(app.WORKER_ROLE(), worker));
        assertFalse(app.hasRole(app.ADMIN_ROLE(), address(this)));
        assertFalse(app.hasRole(app.WORKER_ROLE(), address(this)));

        OnReTypes.OnReTokenConfig memory tokenConfig = app.getOnReTokenConfig(address(onReToken));
        assertTrue(tokenConfig.enabled);
        assertEq(tokenConfig.decimals, 9);
        assertEq(tokenConfig.inventorySource, inventorySource);

        OnReTypes.Pricer memory pricer = app.getPricer(pricerId);
        assertEq(pricerId, OnReIds.pricerId(address(onReToken), OnReTypes.PricingDenomination.Usd));
        assertEq(pricer.onReToken, address(onReToken));
        assertEq(uint8(pricer.denomination), uint8(OnReTypes.PricingDenomination.Usd));
        assertEq(pricer.vectorCount, 1);
        assertTrue(pricer.exists);

        OnReTypes.Quoter memory nav = app.getQuoter(navQuoterId);
        assertEq(uint8(nav.kind), uint8(OnReTypes.QuoterKind.Nav));
        assertEq(nav.instanceId, 0);

        OnReTypes.FeeConfig memory fee = app.getFeeConfig(feeConfigId);
        assertEq(fee.basisPoints, 100);
        assertEq(fee.feeVaultId, feeVaultId);
        assertTrue(fee.enabled);

        OnReTypes.ConfigurableVault memory liquidity = app.getConfigurableVault(liquidityVaultId);
        assertEq(uint8(liquidity.kind), uint8(OnReTypes.ConfigurableVaultKind.Liquidity));
    }

    function test_QuoterIdentitySupportsIndependentInstancesOfTheSameKind() public {
        bytes32 secondNavQuoterId = app.createQuoter(OnReTypes.QuoterKind.Nav, 1);

        assertEq(secondNavQuoterId, OnReIds.quoterId(OnReTypes.QuoterKind.Nav, 1));
        assertNotEq(secondNavQuoterId, navQuoterId);
        assertEq(app.getQuoter(secondNavQuoterId).instanceId, 1);

        app.setQuoterDisabled(secondNavQuoterId, true);
        assertTrue(app.getQuoter(secondNavQuoterId).disabled);
        assertFalse(app.getQuoter(navQuoterId).disabled);
    }

    function test_OfferIdentityIncludesDirectedPairAndFlow() public view {
        assertEq(
            permissionedOfferId,
            OnReIds.offerConfigId(address(usd), address(onReToken), OnReTypes.OfferFlow.Permissioned)
        );
        assertEq(
            permissionlessOfferId,
            OnReIds.offerConfigId(address(usd), address(onReToken), OnReTypes.OfferFlow.Permissionless)
        );
        assertEq(workerOfferId, OnReIds.offerConfigId(address(onReToken), address(usd), OnReTypes.OfferFlow.Worker));
        assertTrue(permissionedOfferId != permissionlessOfferId);

        OnReTypes.OfferConfig memory permissioned = app.getOfferConfig(permissionedOfferId);
        OnReTypes.OfferConfig memory workerConfig = app.getOfferConfig(workerOfferId);
        assertEq(uint8(permissioned.direction), uint8(OnReTypes.OfferDirection.AssetToOnRe));
        assertEq(uint8(workerConfig.direction), uint8(OnReTypes.OfferDirection.OnReToAsset));
        assertEq(permissioned.tokenInDecimals, 6);
        assertEq(permissioned.tokenOutDecimals, 9);
        assertEq(workerConfig.tokenInDecimals, 9);
        assertEq(workerConfig.tokenOutDecimals, 6);
    }

    function test_OfferCreationRejectsWrongFlowQuoterAndWorkerDirection() public {
        MockUsd alternativeUsd = new MockUsd();
        vm.expectRevert(IOnReAppErrors.InvalidFlowQuoterError.selector);
        _makeOffer(
            address(alternativeUsd),
            address(onReToken),
            OnReTypes.OfferFlow.Permissionless,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );

        bytes32 secondFee = app.createFeeConfig(1, 0, feeVaultId);
        vm.expectRevert(IOnReAppErrors.InvalidOfferDirectionError.selector);
        _makeOffer(
            address(alternativeUsd),
            address(onReToken),
            OnReTypes.OfferFlow.Worker,
            navQuoterId,
            secondFee,
            liquidityVaultId
        );
    }

    function test_PricerOwnsVectorsAndDrivesMarketStats() public {
        assertEq(app.currentPrice(pricerId), 1e9);
        OnReTypes.PricingVector memory vector = app.getPricingVector(pricerId, 0);
        assertEq(vector.basePrice, 1e9);

        onReToken.mint(user, 250e9);
        OnReTypes.MarketStats memory stats = app.marketStats(address(onReToken));
        assertEq(stats.nav, 1e9);
        assertEq(stats.circulatingSupply, 250e9);
        assertEq(stats.tvl, 250e9);

        app.addPricingVector(
            pricerId,
            OnReTypes.PricingVector({startTime: 2, baseTime: 2, basePrice: 2e9, apr: 0, priceFixDuration: 1 days})
        );
        vm.warp(2);
        assertEq(app.currentPrice(pricerId), 2e9);
        assertEq(app.marketStats(address(onReToken)).nav, 2e9);
    }

    function test_PricingVectorLifecycleAndValidationBranches() public {
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.PricerAlreadyExistsError.selector, pricerId));
        app.createPricer(address(onReToken), OnReTypes.PricingDenomination.Usd);

        vm.expectRevert(IOnReAppErrors.InvalidAmountError.selector);
        app.addPricingVector(
            pricerId,
            OnReTypes.PricingVector({startTime: 2, baseTime: 1, basePrice: 0, apr: 0, priceFixDuration: 1 days})
        );

        vm.expectRevert(
            abi.encodeWithSelector(IOnReAppErrors.VectorBaseTimeAfterStartTimeError.selector, uint64(3), uint64(2))
        );
        app.addPricingVector(
            pricerId,
            OnReTypes.PricingVector({startTime: 2, baseTime: 3, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );

        OnReTypes.PricingVector memory futureVector =
            OnReTypes.PricingVector({startTime: 5, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days});
        app.addPricingVector(pricerId, futureVector);

        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.DuplicateVectorStartTimeError.selector, uint64(5)));
        app.addPricingVector(pricerId, futureVector);

        vm.expectRevert(IOnReAppErrors.InvalidVectorOrderError.selector);
        app.addPricingVector(
            pricerId,
            OnReTypes.PricingVector({startTime: 4, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );

        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.VectorNotFoundError.selector, uint64(6)));
        app.deletePricingVector(pricerId, 6);
        app.deletePricingVector(pricerId, 5);

        vm.expectRevert(
            abi.encodeWithSelector(IOnReAppErrors.VectorStartTimeInPastError.selector, uint64(1), uint64(1))
        );
        app.deletePricingVector(pricerId, 1);

        for (uint64 startTime = 2; startTime <= 10; ++startTime) {
            app.addPricingVector(
                pricerId,
                OnReTypes.PricingVector({
                    startTime: startTime, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days
                })
            );
        }
        vm.expectRevert(IOnReAppErrors.TooManyVectorsError.selector);
        app.addPricingVector(
            pricerId,
            OnReTypes.PricingVector({startTime: 11, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days})
        );

        app.deleteAllPricingVectors(pricerId);
        assertEq(app.getPricer(pricerId).vectorCount, 0);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.NoActiveVectorError.selector, pricerId));
        app.currentPrice(pricerId);
    }

    function test_TakeOfferPermissionedRequiresApprovalAndRoutesInputFee() public {
        uint256 inputAmount = 100e6;
        _fundAndApproveUsd(user, inputAmount);

        OnReTypes.ApprovalMessage memory approval = OnReTypes.ApprovalMessage({user: user, expiry: 1 days});
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
        OnReTypes.TakeOfferParams memory missingSignature =
            _permissionedTakeOfferParams(permissionedOfferId, inputAmount, approval, "");
        vm.expectRevert(IOnReAppErrors.InvalidApprovalError.selector);
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

        OnReTypes.QuoteResult memory quote = app.quote(permissionlessOfferId, 49_500_000);
        assertEq(quote.price, 1e9);
        assertEq(quote.amountOut, amountOut);

        OnReTypes.TakeOfferParams memory unexpectedApproval = _takeOfferParams(permissionlessOfferId, 1);
        unexpectedApproval.approval = OnReTypes.ApprovalMessage({user: user, expiry: 1 days});
        unexpectedApproval.signature = hex"01";
        vm.expectRevert(IOnReAppErrors.InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(unexpectedApproval);
    }

    function test_TakeOfferDispatchRejectsWorkerAndEnforcesUserProtections() public {
        OnReTypes.TakeOfferParams memory workerParams = _takeOfferParams(workerOfferId, 1);
        vm.expectRevert(
            abi.encodeWithSelector(IOnReAppErrors.WorkerOfferRequiresFulfillmentRequestError.selector, workerOfferId)
        );
        vm.prank(user);
        app.takeOffer(workerParams);

        OnReTypes.TakeOfferParams memory expiredParams = _takeOfferParams(permissionlessOfferId, 50e6);
        expiredParams.deadline = 0;
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.TakeOfferDeadlineExpiredError.selector, uint64(0)));
        vm.prank(user);
        app.takeOffer(expiredParams);

        OnReTypes.TakeOfferParams memory slippageParams = _takeOfferParams(permissionlessOfferId, 50e6);
        slippageParams.minimumAmountOut = 49_500_000_001;
        vm.expectRevert(
            abi.encodeWithSelector(IOnReAppErrors.MinimumAmountOutNotMetError.selector, 49_500_000_001, 49_500_000_000)
        );
        vm.prank(user);
        app.takeOffer(slippageParams);
    }

    function test_TakeOfferPermissionedReverseBurnsInputAndPaysFromLiquidity() public {
        bytes32 reversePermissioned = _makeOffer(
            address(onReToken),
            address(usd),
            OnReTypes.OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        _depositLiquidity(200e6);
        onReToken.mint(user, 100e9);
        vm.prank(user);
        onReToken.approve(address(app), 100e9);

        OnReTypes.ApprovalMessage memory approval = OnReTypes.ApprovalMessage({user: user, expiry: 1 days});
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
        assertEq(requestKey, OnReIds.fulfillmentRequestId(workerOfferId, user, 7));
        assertEq(onReToken.balanceOf(address(app)), 100e9);

        vm.prank(worker);
        uint256 firstAmountOut = app.fulfillWorkerRequest(requestKey, 40e9);
        assertEq(firstAmountOut, 39_600_000);
        OnReTypes.FulfillmentRequest memory request = app.getFulfillmentRequest(requestKey);
        assertEq(request.fulfilledInputAmount, 40e9);

        app.addPricingVector(
            pricerId,
            OnReTypes.PricingVector({startTime: 2, baseTime: 2, basePrice: 2e9, apr: 0, priceFixDuration: 1 days})
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

        vm.expectRevert(
            abi.encodeWithSelector(
                IOnReAppErrors.FulfillmentAmountExceedsRemainingError.selector, requestKey, 11e9, 10e9
            )
        );
        vm.prank(worker);
        app.fulfillWorkerRequest(requestKey, 11e9);
    }

    function test_FeeConfigIsReusableAndMutable() public {
        app.updateFeeConfig(feeConfigId, 200, feeVaultId);
        OnReTypes.ExecutionAccounting memory preview = app.previewExecution(permissionlessOfferId, 10e6);
        assertEq(preview.feeAmount, 200_000);
        assertEq(preview.netInputAmount, 9_800_000);
        assertEq(preview.amountOut, 9_800_000_000);

        app.setFeeConfigEnabled(feeConfigId, false);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.FeeConfigDisabledError.selector, feeConfigId));
        app.previewExecution(permissionedOfferId, 10e6);
    }

    function test_ForwardExecutionRefillsLiquidityBeforeProceeds() public {
        onReToken.mint(address(this), 1_000e9);
        bytes32 refillVault =
            app.createConfigurableVault(OnReTypes.ConfigurableVaultKind.Liquidity, 1, vaultDestination, 1_000);
        bytes32 zeroFee = app.createFeeConfig(2, 0, feeVaultId);
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

        bytes32 noDestinationVault = app.createConfigurableVault(OnReTypes.ConfigurableVaultKind.Fee, 5, address(0), 0);
        usd.mint(address(this), 1);
        usd.approve(address(app), 1);
        app.depositConfigurableVault(noDestinationVault, address(usd), 1);
        vm.expectRevert(
            abi.encodeWithSelector(IOnReAppErrors.MissingConfigurableVaultDestinationError.selector, noDestinationVault)
        );
        app.withdrawConfigurableVault(noDestinationVault, address(usd), 1);
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
        vm.expectRevert(IOnReAppErrors.InvalidBasisPointsError.selector);
        app.createConfigurableVault(OnReTypes.ConfigurableVaultKind.Fee, 12, vaultDestination, 1);

        vm.expectRevert(IOnReAppErrors.InvalidBasisPointsError.selector);
        app.updateConfigurableVault(liquidityVaultId, vaultDestination, 10_001);

        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.ConfigurableVaultAlreadyExistsError.selector, feeVaultId));
        app.createConfigurableVault(OnReTypes.ConfigurableVaultKind.Fee, 0, vaultDestination, 0);

        vm.expectRevert(IOnReAppErrors.InvalidFeeError.selector);
        app.createFeeConfig(12, 1_001, feeVaultId);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOnReAppErrors.InvalidConfigurableVaultKindError.selector,
                proceedsVaultId,
                uint8(OnReTypes.ConfigurableVaultKind.Fee),
                uint8(OnReTypes.ConfigurableVaultKind.Proceeds)
            )
        );
        app.createFeeConfig(12, 0, proceedsVaultId);

        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.updateFeeConfig(feeConfigId, 100, feeVaultId);
        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.updateConfigurableVault(liquidityVaultId, vaultDestination, 0);

        vm.expectRevert(IOnReAppErrors.InvalidAmountError.selector);
        app.depositConfigurableVault(liquidityVaultId, address(usd), 0);
        vm.expectRevert(IOnReAppErrors.ZeroBalanceError.selector);
        app.withdrawConfigurableVault(liquidityVaultId, address(usd), 0);

        usd.mint(address(this), 1e6);
        usd.approve(address(app), 1e6);
        app.depositConfigurableVault(liquidityVaultId, address(usd), 1e6);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.InsufficientBalanceError.selector, 1e6, 2e6));
        app.withdrawConfigurableVault(liquidityVaultId, address(usd), 2e6);
    }

    function test_OfferAndComponentNoChangeDuplicateAndLiquidityGuards() public {
        vm.expectRevert(
            abi.encodeWithSelector(IOnReAppErrors.OfferConfigAlreadyExistsError.selector, permissionedOfferId)
        );
        _makeOffer(
            address(usd),
            address(onReToken),
            OnReTypes.OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );

        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.updateOfferConfigReferences(
            permissionedOfferId, navQuoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );

        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.setOfferConfigDisabled(permissionedOfferId, false);
        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.setPricerDisabled(pricerId, false);
        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.setQuoterDisabled(navQuoterId, false);
        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.setFeeConfigEnabled(feeConfigId, true);

        vm.expectRevert(
            abi.encodeWithSelector(
                IOnReAppErrors.LiquidityVaultRequiredError.selector,
                OnReIds.offerConfigId(address(onReToken), address(usd), OnReTypes.OfferFlow.Permissionless)
            )
        );
        _makeOffer(
            address(onReToken),
            address(usd),
            OnReTypes.OfferFlow.Permissionless,
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
        vm.expectRevert(
            abi.encodeWithSelector(IOnReAppErrors.FulfillmentRequestAlreadyExistsError.selector, requestKey)
        );
        app.createFulfillmentRequest(workerOfferId, 55, 10e9);
        vm.stopPrank();

        address stranger = makeAddr("stranger");
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.UnauthorizedError.selector, stranger));
        vm.prank(stranger);
        app.cancelFulfillmentRequest(requestKey);

        bytes32 missing = keccak256("missing request");
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.FulfillmentRequestNotFoundError.selector, missing));
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
            abi.encodeWithSelector(
                IOnReAppErrors.ExcludedSupplyAddressAlreadyExistsError.selector, address(onReToken), excluded
            )
        );
        app.addExcludedSupplyAddress(address(onReToken), excluded);
        app.removeExcludedSupplyAddress(address(onReToken), excluded);

        address secondApprover = makeAddr("secondApprover");
        app.addApprover(secondApprover);
        app.removeApprover(secondApprover);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.NotApproverError.selector, secondApprover));
        app.removeApprover(secondApprover);

        address newInventorySource = makeAddr("newInventorySource");
        app.setOnReTokenInventorySource(address(onReToken), newInventorySource);
        assertEq(app.getOnReTokenConfig(address(onReToken)).inventorySource, newInventorySource);
        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.setOnReTokenInventorySource(address(onReToken), newInventorySource);
        app.setOnReTokenEnabled(address(onReToken), false);
        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.setOnReTokenEnabled(address(onReToken), false);

        app.setKillSwitch(true);
        vm.expectRevert(IOnReAppErrors.NoChangeError.selector);
        app.setKillSwitch(true);
    }

    function test_TokenRegistrationRejectsInvalidInputsAndSupportsReenable() public {
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        app.registerOnReToken(address(0), inventorySource);

        OnReToken secondToken = _deployToken(address(app));
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        app.registerOnReToken(address(secondToken), address(0));

        vm.expectRevert(IOnReAppErrors.InvalidTokenError.selector);
        app.registerOnReToken(address(usd), inventorySource);

        app.setOnReTokenEnabled(address(onReToken), false);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.TokenAlreadyRegisteredError.selector, address(onReToken)));
        app.registerOnReToken(address(onReToken), inventorySource);

        vm.expectRevert(IOnReAppErrors.InvalidTokenError.selector);
        app.createPricer(address(onReToken), OnReTypes.PricingDenomination.Usd);
        app.setOnReTokenEnabled(address(onReToken), true);

        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        app.setOnReTokenInventorySource(address(onReToken), address(0));

        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.TokenNotRegisteredError.selector, address(usd)));
        app.setOnReTokenEnabled(address(usd), true);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.TokenNotRegisteredError.selector, address(usd)));
        app.createPricer(address(usd), OnReTypes.PricingDenomination.Usd);
    }

    function test_ExcludedSupplyAddressCapacityRemovalAndInventoryDeduplication() public {
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        app.addExcludedSupplyAddress(address(onReToken), address(0));
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        app.removeExcludedSupplyAddress(address(onReToken), address(0));

        address missing = makeAddr("missingExcluded");
        vm.expectRevert(
            abi.encodeWithSelector(
                IOnReAppErrors.ExcludedSupplyAddressNotFoundError.selector, address(onReToken), missing
            )
        );
        app.removeExcludedSupplyAddress(address(onReToken), missing);

        app.addExcludedSupplyAddress(address(onReToken), inventorySource);
        for (uint160 i = 1; i < 20; ++i) {
            app.addExcludedSupplyAddress(address(onReToken), address(10_000 + i));
        }
        vm.expectRevert(
            abi.encodeWithSelector(IOnReAppErrors.TooManyExcludedSupplyAddressesError.selector, address(onReToken))
        );
        app.addExcludedSupplyAddress(address(onReToken), address(20_000));

        assertEq(app.marketStats(address(onReToken)).circulatingSupply, 0);
        app.removeExcludedSupplyAddress(address(onReToken), inventorySource);
        app.removeExcludedSupplyAddress(address(onReToken), address(10_018));
        assertEq(app.getExcludedSupplyAccounts(address(onReToken)).length, 18);
    }

    function test_ApproverSlotValidationAndReuse() public {
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        app.addApprover(address(0));
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        app.removeApprover(address(0));

        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.ApproverAlreadyExistsError.selector, approver));
        app.addApprover(approver);

        address secondApprover = makeAddr("secondApprover");
        app.addApprover(secondApprover);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.ApproverAlreadyExistsError.selector, secondApprover));
        app.addApprover(secondApprover);

        vm.expectRevert(IOnReAppErrors.BothApproversFilledError.selector);
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

        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.PricerNotFoundError.selector, missing));
        app.currentPrice(missing);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.QuoterNotFoundError.selector, missing));
        app.setQuoterDisabled(missing, true);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.FeeConfigNotFoundError.selector, missing));
        app.updateFeeConfig(missing, 0, feeVaultId);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.ConfigurableVaultNotFoundError.selector, missing));
        app.updateConfigurableVault(missing, vaultDestination, 0);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.OfferConfigNotFoundError.selector, missing));
        app.setOfferConfigDisabled(missing, true);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.TokenNotRegisteredError.selector, address(usd)));
        app.marketStats(address(usd));

        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.VectorIndexOutOfBoundsError.selector, uint8(1), uint8(1)));
        app.getPricingVector(pricerId, 1);
        vm.expectRevert(IOnReAppErrors.InvalidAmountError.selector);
        app.quote(permissionlessOfferId, 0);
        vm.expectRevert(IOnReAppErrors.InvalidAmountError.selector);
        app.previewExecution(permissionlessOfferId, 0);

        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        app.depositConfigurableVault(liquidityVaultId, address(0), 1);
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        app.withdrawConfigurableVault(liquidityVaultId, address(0), 1);

        app.setKillSwitch(true);
        vm.expectRevert(IOnReAppErrors.KilledError.selector);
        app.withdrawConfigurableVault(liquidityVaultId, address(usd), 1);
    }

    function test_OfferCreationAndReferenceValidationBranches() public {
        MockUsd alternativeUsd = new MockUsd();

        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        _makeOffer(
            address(0), address(onReToken), OnReTypes.OfferFlow.Permissioned, navQuoterId, feeConfigId, liquidityVaultId
        );
        vm.expectRevert(IOnReAppErrors.ZeroAddressError.selector);
        _makeOffer(
            address(alternativeUsd),
            address(0),
            OnReTypes.OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        vm.expectRevert(IOnReAppErrors.InvalidTokenError.selector);
        _makeOffer(
            address(alternativeUsd),
            address(alternativeUsd),
            OnReTypes.OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );

        MockHighDecimals highDecimals = new MockHighDecimals();
        vm.expectRevert(IOnReAppErrors.InvalidDecimalsError.selector);
        _makeOffer(
            address(highDecimals),
            address(onReToken),
            OnReTypes.OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        vm.expectRevert(IOnReAppErrors.InvalidDecimalsError.selector);
        _makeOffer(
            address(onReToken),
            address(highDecimals),
            OnReTypes.OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            liquidityVaultId
        );

        bytes32 missing = keccak256("missingReference");
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.QuoterNotFoundError.selector, missing));
        _makeOffer(
            address(alternativeUsd),
            address(onReToken),
            OnReTypes.OfferFlow.Permissioned,
            missing,
            feeConfigId,
            liquidityVaultId
        );
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.FeeConfigNotFoundError.selector, missing));
        _makeOffer(
            address(alternativeUsd),
            address(onReToken),
            OnReTypes.OfferFlow.Permissioned,
            navQuoterId,
            missing,
            liquidityVaultId
        );
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.ConfigurableVaultNotFoundError.selector, missing));
        _makeOffer(
            address(alternativeUsd),
            address(onReToken),
            OnReTypes.OfferFlow.Permissioned,
            navQuoterId,
            feeConfigId,
            missing
        );

        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.QuoterAlreadyExistsError.selector, navQuoterId));
        app.createQuoter(OnReTypes.QuoterKind.Nav, 0);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.FeeConfigAlreadyExistsError.selector, feeConfigId));
        app.createFeeConfig(0, 100, feeVaultId);
    }

    function test_ApprovalBranchesAndInsufficientLiquidity() public {
        uint256 inputAmount = 1e6;
        _fundAndApproveUsd(user, inputAmount);

        OnReTypes.ApprovalMessage memory wrongUser =
            OnReTypes.ApprovalMessage({user: makeAddr("approvalOther"), expiry: 1 days});
        vm.expectRevert(IOnReAppErrors.InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(
            _permissionedTakeOfferParams(permissionedOfferId, inputAmount, wrongUser, _signApproval(wrongUser))
        );

        OnReTypes.ApprovalMessage memory expired = OnReTypes.ApprovalMessage({user: user, expiry: 0});
        vm.expectRevert(IOnReAppErrors.InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(_permissionedTakeOfferParams(permissionedOfferId, inputAmount, expired, _signApproval(expired)));

        uint256 secondApproverKey = 0xB0B;
        address secondApprover = vm.addr(secondApproverKey);
        app.addApprover(secondApprover);
        OnReTypes.ApprovalMessage memory approval = OnReTypes.ApprovalMessage({user: user, expiry: 1 days});
        vm.prank(user);
        app.takeOffer(
            _permissionedTakeOfferParams(
                permissionedOfferId, inputAmount, approval, _signApprovalWithKey(approval, secondApproverKey)
            )
        );

        OnReTypes.TakeOfferParams memory expiryOnly = _takeOfferParams(permissionlessOfferId, 1);
        expiryOnly.approval.expiry = 1;
        vm.expectRevert(IOnReAppErrors.InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(expiryOnly);

        OnReTypes.TakeOfferParams memory signatureOnly = _takeOfferParams(permissionlessOfferId, 1);
        signatureOnly.signature = hex"01";
        vm.expectRevert(IOnReAppErrors.InvalidApprovalError.selector);
        vm.prank(user);
        app.takeOffer(signatureOnly);

        bytes32 reversePermissionless = _makeOffer(
            address(onReToken),
            address(usd),
            OnReTypes.OfferFlow.Permissionless,
            navPermissionlessQuoterId,
            feeConfigId,
            liquidityVaultId
        );
        app.updateFeeConfig(feeConfigId, 0, feeVaultId);
        onReToken.mint(user, 1e9);
        vm.prank(user);
        onReToken.approve(address(app), 1e9);
        vm.expectRevert(
            abi.encodeWithSelector(
                IOnReAppErrors.InsufficientLiquidityError.selector, liquidityVaultId, address(usd), 0, 1e6
            )
        );
        vm.prank(user);
        app.takeOffer(_takeOfferParams(reversePermissionless, 1e9));
    }

    function test_FulfillmentRejectsNonWorkerOffersAndZeroAmounts() public {
        vm.expectRevert(IOnReAppErrors.InvalidFlowQuoterError.selector);
        vm.prank(user);
        app.createFulfillmentRequest(permissionlessOfferId, 1, 1);

        vm.expectRevert(IOnReAppErrors.InvalidAmountError.selector);
        vm.prank(user);
        app.createFulfillmentRequest(workerOfferId, 1, 0);

        onReToken.mint(user, 1e9);
        vm.startPrank(user);
        onReToken.approve(address(app), 1e9);
        bytes32 requestKey = app.createFulfillmentRequest(workerOfferId, 2, 1e9);
        vm.stopPrank();

        vm.expectRevert(IOnReAppErrors.InvalidAmountError.selector);
        vm.prank(worker);
        app.fulfillWorkerRequest(requestKey, 0);
    }

    function test_PricingVectorZeroFieldsPastStartAndCompaction() public {
        OnReTypes.PricingVector memory vector =
            OnReTypes.PricingVector({startTime: 2, baseTime: 1, basePrice: 1e9, apr: 0, priceFixDuration: 1 days});

        vector.startTime = 0;
        vm.expectRevert(IOnReAppErrors.InvalidAmountError.selector);
        app.addPricingVector(pricerId, vector);
        vector.startTime = 2;
        vector.baseTime = 0;
        vm.expectRevert(IOnReAppErrors.InvalidAmountError.selector);
        app.addPricingVector(pricerId, vector);
        vector.baseTime = 1;
        vector.priceFixDuration = 0;
        vm.expectRevert(IOnReAppErrors.InvalidAmountError.selector);
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
        vm.expectRevert(
            abi.encodeWithSelector(IOnReAppErrors.VectorStartTimeInPastError.selector, uint64(6), uint64(7))
        );
        app.addPricingVector(pricerId, vector);
    }

    function test_MarketStatsReportsNegativeNavAdjustment() public {
        app.addPricingVector(
            pricerId,
            OnReTypes.PricingVector({
                startTime: 2, baseTime: 2, basePrice: 500_000_000, apr: 0, priceFixDuration: 1 days
            })
        );
        vm.warp(2);
        assertEq(app.marketStats(address(onReToken)).navAdjustment, -500_000_000);
    }

    function test_DisabledComponentsAndKillSwitchStopExecution() public {
        app.setPricerDisabled(pricerId, true);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.PricerDisabledError.selector, pricerId));
        app.previewExecution(permissionedOfferId, 1e6);
        app.setPricerDisabled(pricerId, false);

        app.setQuoterDisabled(navQuoterId, true);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.QuoterDisabledError.selector, navQuoterId));
        app.previewExecution(permissionedOfferId, 1e6);
        app.setQuoterDisabled(navQuoterId, false);

        app.setOfferConfigDisabled(permissionedOfferId, true);
        vm.expectRevert(abi.encodeWithSelector(IOnReAppErrors.OfferConfigDisabledError.selector, permissionedOfferId));
        app.previewExecution(permissionedOfferId, 1e6);
        app.setOfferConfigDisabled(permissionedOfferId, false);

        app.setKillSwitch(true);
        vm.expectRevert(IOnReAppErrors.KilledError.selector);
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
        app.createQuoter(OnReTypes.QuoterKind.Nav, 99);

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, admin, app.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(admin);
        app.createConfigurableVault(OnReTypes.ConfigurableVaultKind.Fee, 99, admin, 0);
    }

    function testFuzz_NavQuoteMatchesDecimalScaling(uint96 rawInput) public view {
        uint256 inputAmount = bound(uint256(rawInput), 1, 1_000_000e6);
        OnReTypes.QuoteResult memory quote = app.quote(permissionlessOfferId, inputAmount);
        assertEq(quote.amountOut, inputAmount * 1_000);
    }

    function _makeOffer(
        address tokenIn,
        address tokenOut,
        OnReTypes.OfferFlow flow,
        bytes32 quoter,
        bytes32 feeConfig,
        bytes32 liquidityVault
    ) private returns (bytes32) {
        return app.makeOfferConfig(
            OnReTypes.MakeOfferConfigParams({
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

    function _fundAndApproveUsd(address account, uint256 amount) private {
        usd.mint(account, amount);
        vm.prank(account);
        usd.approve(address(app), amount);
    }

    function _depositLiquidity(uint256 amount) private {
        usd.mint(address(this), amount);
        usd.approve(address(app), amount);
        app.depositConfigurableVault(liquidityVaultId, address(usd), amount);
    }

    function _takeOfferParams(bytes32 offerConfigId, uint256 grossInputAmount)
        private
        view
        returns (OnReTypes.TakeOfferParams memory params)
    {
        params.offerConfigId = offerConfigId;
        params.grossInputAmount = grossInputAmount;
        params.deadline = uint64(block.timestamp + 1 days);
    }

    function _permissionedTakeOfferParams(
        bytes32 offerConfigId,
        uint256 grossInputAmount,
        OnReTypes.ApprovalMessage memory approval,
        bytes memory signature
    ) private view returns (OnReTypes.TakeOfferParams memory params) {
        params = _takeOfferParams(offerConfigId, grossInputAmount);
        params.approval = approval;
        params.signature = signature;
    }

    function _signApproval(OnReTypes.ApprovalMessage memory approval) private view returns (bytes memory) {
        return _signApprovalWithKey(approval, APPROVER_KEY);
    }

    function _signApprovalWithKey(OnReTypes.ApprovalMessage memory approval, uint256 key)
        private
        view
        returns (bytes memory)
    {
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, _approvalDigest(approval));
        return abi.encodePacked(r, s, v);
    }

    function _approvalDigest(OnReTypes.ApprovalMessage memory approval) private view returns (bytes32) {
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
