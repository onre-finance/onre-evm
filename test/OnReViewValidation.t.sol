// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "../src/types/OnReAppErrors.sol";
import "../src/types/OnReTypes.sol";
import "./helpers/OnReAppTestBase.sol";

contract OnReViewValidationTest is OnReAppTestBase {
    function test_UnknownObjectsReturnDomainErrors() public {
        bytes32 missing = keccak256("missing S2 object");
        address unknownToken = makeAddr("unknown S2 token");

        vm.expectRevert(abi.encodeWithSelector(TokenNotRegisteredError.selector, unknownToken));
        app.getManagedTokenConfig(unknownToken);
        vm.expectRevert(abi.encodeWithSelector(PricerNotFoundError.selector, missing));
        app.getPricer(missing);
        vm.expectRevert(abi.encodeWithSelector(PricerNotFoundError.selector, missing));
        app.getPricingVector(missing, 0);
        vm.expectRevert(abi.encodeWithSelector(QuoterNotFoundError.selector, missing));
        app.getQuoter(missing);
        vm.expectRevert(abi.encodeWithSelector(QuoterNotFoundError.selector, missing));
        app.getPropAmmState(missing);
        vm.expectRevert(abi.encodeWithSelector(FeeConfigNotFoundError.selector, missing));
        app.getFeeConfig(missing);
        vm.expectRevert(abi.encodeWithSelector(OfferConfigNotFoundError.selector, missing));
        app.getOfferConfig(missing);
        vm.expectRevert(abi.encodeWithSelector(FulfillmentRequestNotFoundError.selector, missing));
        app.getFulfillmentRequest(missing);
        vm.expectRevert(abi.encodeWithSelector(ConfigurableVaultNotFoundError.selector, missing));
        app.getConfigurableVault(missing);
        vm.expectRevert(abi.encodeWithSelector(TokenNotRegisteredError.selector, unknownToken));
        app.getExcludedSupplyAccounts(unknownToken);
        vm.expectRevert(abi.encodeWithSelector(ConfigurableVaultNotFoundError.selector, missing));
        app.configurableVaultBalance(missing, address(usd));
        vm.expectRevert(abi.encodeWithSelector(BufferNotFoundError.selector, unknownToken));
        app.getBufferState(unknownToken);
    }

    function test_ExistingEmptyRecordsAndPredicatesRemainReadable() public {
        bytes32 propAmmId = app.createQuoter(QuoterKind.PropAmm, 42);
        assertEq(app.getPropAmmState(propAmmId).assetToken, address(0));
        assertEq(app.getExcludedSupplyAccounts(address(managedToken)).length, 0);
        // Payment assets do not need to be registered as managed tokens.
        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), 0);
        _depositLiquidity(100e6);
        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), 100e6);
        assertFalse(app.isManagedTokenDeployed(address(usd)));
        assertFalse(app.hasRole(app.WORKER_ROLE(), user));

        app.deleteAllPricingVectors(pricerId);
        assertTrue(app.getPricer(pricerId).exists);
        assertEq(app.getPricer(pricerId).vectorCount, 0);
        vm.expectRevert(abi.encodeWithSelector(VectorIndexOutOfBoundsError.selector, uint8(0), uint8(0)));
        app.getPricingVector(pricerId, 0);
    }

    function test_DisabledObjectsRemainReadableWhileKilled() public {
        bytes32 propAmmId = _createConfiguredPropAmm(42, _basePropAmmTestConfig());
        app.initializeBuffer(address(managedToken));
        managedToken.mint(user, 10e9);
        vm.prank(user);
        managedToken.approve(address(app), 10e9);
        vm.prank(user);
        bytes32 requestId = app.createFulfillmentRequest(workerOfferId, 42, 10e9);

        app.setPricerEnabled(pricerId, false);
        app.setQuoterEnabled(navQuoterId, false);
        app.setQuoterEnabled(propAmmId, false);
        app.setFeeConfigEnabled(feeConfigId, false);
        app.setOfferConfigEnabled(workerOfferId, false);
        app.setManagedTokenEnabled(address(managedToken), false);
        app.setKillSwitch(true);

        assertFalse(app.getManagedTokenConfig(address(managedToken)).enabled);
        assertFalse(app.getPricer(pricerId).enabled);
        assertEq(app.getPricingVector(pricerId, 0).basePrice, 1e9);
        assertFalse(app.getQuoter(navQuoterId).enabled);
        assertEq(app.getPropAmmState(propAmmId).assetToken, address(usd));
        assertFalse(app.getFeeConfig(feeConfigId).enabled);
        assertFalse(app.getOfferConfig(workerOfferId).enabled);
        assertTrue(app.getFulfillmentRequest(requestId).exists);
        assertTrue(app.getConfigurableVault(liquidityVaultId).exists);
        assertEq(app.configurableVaultBalance(liquidityVaultId, address(usd)), 0);
        assertEq(app.getExcludedSupplyAccounts(address(managedToken)).length, 0);
        assertTrue(app.getBufferState(address(managedToken)).exists);
    }

    function testFuzz_PricingDurationAboveOneDayIsRejected(uint64 duration) public {
        duration = uint64(bound(duration, 1 days + 1, type(uint64).max));
        PricingVector memory vector =
            PricingVector({startTime: 2, baseTime: 2, basePrice: 1e9, apr: 100_000, priceFixDuration: duration});
        vm.expectRevert(InvalidAmountError.selector);
        app.addPricingVector(pricerId, vector);
        assertEq(app.getPricer(pricerId).vectorCount, 1);
    }

    function testFuzz_PricingDurationUpToOneDayIsAccepted(uint64 duration) public {
        duration = uint64(bound(duration, 1, 1 days));
        app.addPricingVector(
            pricerId,
            PricingVector({startTime: 2, baseTime: 2, basePrice: 1e9, apr: 100_000, priceFixDuration: duration})
        );
        assertEq(app.getPricingVector(pricerId, 1).priceFixDuration, duration);
        vm.warp(2);
        assertGe(app.currentPrice(pricerId), 1e9);
    }

    function test_PricingDurationBoundaries() public {
        PricingVector memory vector =
            PricingVector({startTime: 2, baseTime: 2, basePrice: 1e9, apr: 100_000, priceFixDuration: 0});
        vm.expectRevert(InvalidAmountError.selector);
        app.addPricingVector(pricerId, vector);
        vector.priceFixDuration = 1 days + 1;
        vm.expectRevert(InvalidAmountError.selector);
        app.addPricingVector(pricerId, vector);
        vector.priceFixDuration = 1;
        app.addPricingVector(pricerId, vector);
        vector.startTime = 3;
        vector.priceFixDuration = 1 days;
        app.addPricingVector(pricerId, vector);
        assertEq(app.getPricingVector(pricerId, 1).priceFixDuration, 1);
        assertEq(app.getPricingVector(pricerId, 2).priceFixDuration, 1 days);
    }
}
