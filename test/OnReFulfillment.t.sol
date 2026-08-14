// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "../src/types/OnReAppErrors.sol";
import "../src/types/OnReTypes.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import "./helpers/OnReAppTestBase.sol";

contract OnReFulfillmentTest is OnReAppTestBase {
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
}
