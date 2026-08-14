// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "../src/types/OnReAppErrors.sol";
import "../src/types/OnReTypes.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import "./helpers/OnReAppTestBase.sol";

contract OnReConfigTest is OnReAppTestBase {
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
}
