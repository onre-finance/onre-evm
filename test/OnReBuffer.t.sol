// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    BufferAlreadyExistsError,
    BufferNotFoundError,
    BufferReserveExcludedFromSupplyError,
    BufferSupplyMismatchError,
    InsufficientBalanceError,
    InvalidAssetAdjustmentAmountError,
    InvalidBasisPointsError,
    InvalidBufferAprError,
    InvalidBufferControllerError,
    KilledError,
    NoBurnNeededError
} from "../src/types/OnReAppErrors.sol";
import {BufferBurnedForNav} from "../src/types/OnReAppEvents.sol";
import {
    BufferState,
    ConfigurableVault,
    ConfigurableVaultKind,
    MarketStats,
    PricingDenomination,
    PricingVector
} from "../src/types/OnReTypes.sol";
import {IManagedToken} from "../src/IManagedToken.sol";
import {IBufferController} from "../src/IBufferController.sol";
import {ManagedToken} from "../src/ManagedToken.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {OnReAppTestBase} from "./helpers/OnReAppTestBase.sol";

contract OnReBufferTest is OnReAppTestBase {
    uint256 private constant INITIAL_SUPPLY = 1_000_000_000e9;
    uint64 private constant GROSS_APR = 100_000;
    uint16 private constant MANAGEMENT_FEE_BPS = 100;
    uint16 private constant PERFORMANCE_FEE_BPS = 2_000;

    bytes32 private bufferReserveVaultId;
    bytes32 private managementFeeVaultId;
    bytes32 private performanceFeeVaultId;

    function setUp() public override {
        super.setUp();

        managedToken.mint(address(this), INITIAL_SUPPLY);
        app.initializeBuffer(address(managedToken));
        BufferState memory state = app.getBufferState(address(managedToken));
        bufferReserveVaultId = state.reserveVaultId;
        managementFeeVaultId = state.managementFeeVaultId;
        performanceFeeVaultId = state.performanceFeeVaultId;
        app.updateConfigurableVault(bufferReserveVaultId, vaultDestination, 0);
        app.updateConfigurableVault(managementFeeVaultId, vaultDestination, 0);
        app.updateConfigurableVault(performanceFeeVaultId, vaultDestination, 0);
        managedToken.setBufferController(address(app));
        app.setBufferGrossApr(address(managedToken), GROSS_APR);
        app.setBufferFeeConfig(address(managedToken), MANAGEMENT_FEE_BPS, PERFORMANCE_FEE_BPS, true);
    }

    function test_MintSettlesBufferOnceAndStoresPostMintSupply() public {
        uint256 startingSupply = managedToken.totalSupply();
        uint256 mintAmount = 100e9;
        vm.warp(block.timestamp + 365 days / 2);

        managedToken.mint(user, mintAmount);

        uint256 expectedBufferMint = startingSupply * GROSS_APR * (365 days / 2) / (365 days * 1_000_000);
        uint256 expectedManagementFee = expectedBufferMint * 10_000 / GROSS_APR;
        uint256 expectedAfterManagement = expectedBufferMint - expectedManagementFee;
        uint256 expectedPerformanceFee = expectedAfterManagement * PERFORMANCE_FEE_BPS / 10_000;
        uint256 expectedReserveMint = expectedAfterManagement - expectedPerformanceFee;

        assertEq(managedToken.balanceOf(address(app)), expectedBufferMint);
        assertEq(app.configurableVaultBalance(bufferReserveVaultId, address(managedToken)), expectedReserveMint);
        assertEq(app.configurableVaultBalance(managementFeeVaultId, address(managedToken)), expectedManagementFee);
        assertEq(app.configurableVaultBalance(performanceFeeVaultId, address(managedToken)), expectedPerformanceFee);

        uint256 expectedPostMintSupply = startingSupply + expectedBufferMint + mintAmount;
        BufferState memory state = app.getBufferState(address(managedToken));
        assertEq(state.previousSupply, expectedPostMintSupply);
        assertEq(managedToken.totalSupply(), expectedPostMintSupply);
        assertEq(managedToken.balanceOf(user), mintAmount);
        assertEq(app.getExcludedSupplyAccounts(address(managedToken)).length, 0);

        MarketStats memory stats = app.marketStats(address(managedToken));
        assertEq(stats.circulatingSupply, startingSupply + expectedBufferMint + mintAmount);
    }

    function test_BurnAndBurnFromSettleBeforeSupplyChange() public {
        managedToken.grantBurnRole(address(this));
        managedToken.mint(address(this), 200e9);
        managedToken.mint(user, 100e9);

        vm.prank(user);
        managedToken.approve(address(this), 40e9);

        vm.warp(block.timestamp + 30 days);
        managedToken.burn(50e9);
        BufferState memory afterDirectBurn = app.getBufferState(address(managedToken));
        assertEq(afterDirectBurn.previousSupply, managedToken.totalSupply());

        vm.warp(block.timestamp + 30 days);
        managedToken.burnFrom(user, 40e9);
        BufferState memory afterBurnFrom = app.getBufferState(address(managedToken));
        assertEq(afterBurnFrom.previousSupply, managedToken.totalSupply());
        assertEq(managedToken.balanceOf(user), 60e9);
    }

    function test_ControllerOnlyMintBufferDoesNotRecursivelyAccrue() public {
        vm.expectRevert(abi.encodeWithSelector(IManagedToken.SenderNotBufferControllerError.selector, address(this)));
        managedToken.mintBuffer(1);

        uint256 startingSupply = managedToken.totalSupply();
        vm.warp(block.timestamp + 365 days);
        managedToken.mint(user, 1);

        uint256 expectedBufferMint = startingSupply * GROSS_APR / 1_000_000;
        assertEq(managedToken.balanceOf(address(app)), expectedBufferMint);
        assertEq(managedToken.totalSupply(), startingSupply + expectedBufferMint + 1);
        assertEq(app.getBufferState(address(managedToken)).previousSupply, managedToken.totalSupply());
    }

    function test_WorkerCanSettleWithoutAnExternalSupplyChange() public {
        uint256 startingSupply = managedToken.totalSupply();
        vm.warp(block.timestamp + 90 days);

        vm.prank(worker);
        uint256 mintedAmount = app.settleBuffer(address(managedToken));

        uint256 expectedMint = startingSupply * GROSS_APR * 90 days / (365 days * 1_000_000);
        assertEq(mintedAmount, expectedMint);
        assertEq(managedToken.totalSupply(), startingSupply + expectedMint);
        assertEq(app.getBufferState(address(managedToken)).previousSupply, managedToken.totalSupply());

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), app.WORKER_ROLE()
            )
        );
        app.settleBuffer(address(managedToken));
    }

    function test_PerformanceFeeHighWatermarkSkipsFeeBelowPriorNav() public {
        app.addPricingVector(
            pricerId,
            PricingVector({
                startTime: uint64(block.timestamp + 1),
                baseTime: uint64(block.timestamp + 1),
                basePrice: 900e6,
                apr: 0,
                priceFixDuration: 1 days
            })
        );
        vm.warp(block.timestamp + 365 days / 2);

        managedToken.mint(user, 1);

        assertEq(app.configurableVaultBalance(performanceFeeVaultId, address(managedToken)), 0);
        BufferState memory state = app.getBufferState(address(managedToken));
        assertEq(state.performanceFeeHighWatermark, 1e9);
    }

    function test_AccrualDiscountsForNavAprAlreadyEarned() public {
        app.setBufferGrossApr(address(managedToken), 150_000);
        app.addPricingVector(
            pricerId,
            PricingVector({
                startTime: uint64(block.timestamp + 1),
                baseTime: uint64(block.timestamp + 1),
                basePrice: 1e9,
                apr: 50_000,
                priceFixDuration: 1 days
            })
        );
        uint256 startingSupply = managedToken.totalSupply();
        uint256 elapsed = 365 days / 2;
        vm.warp(block.timestamp + elapsed);

        managedToken.mint(user, 1);

        uint256 expectedBufferMint = startingSupply * 100_000 * elapsed / (365 days * 1_000_000 + 50_000 * elapsed);
        assertEq(managedToken.balanceOf(address(app)), expectedBufferMint);
    }

    function test_BufferGrossAccrualMatchesSolanaReferenceVectors() public {
        _assertSolanaGrossAccrualVector(1_000_000_000, 150_000, 50_000, 365 days / 2, 48_780_487);
        _assertSolanaGrossAccrualVector(1_000_000_000, 120_000, 20_000, 365 days, 98_039_215);
        _assertSolanaGrossAccrualVector(2_500_000_000, 300_000, 100_000, 365 days / 4, 121_951_219);
        _assertSolanaGrossAccrualVector(1_000_000_000, 80_000, 60_000, 30 days, 1_635_768);
    }

    function test_BufferFeeSplitMatchesSolanaReferenceVector() public {
        ManagedToken parityToken = _deployToken(address(app));
        parityToken.mint(address(this), 100_000);
        app.registerManagedToken(address(parityToken));

        bytes32 parityPricerId = app.createPricer(address(parityToken), PricingDenomination.Usd);
        app.addPricingVector(
            parityPricerId,
            PricingVector({
                startTime: uint64(block.timestamp),
                baseTime: uint64(block.timestamp),
                basePrice: 1e9,
                apr: 0,
                priceFixDuration: 1 days
            })
        );

        app.initializeBuffer(address(parityToken));
        BufferState memory parityState = app.getBufferState(address(parityToken));
        parityToken.setBufferController(address(app));
        app.setBufferGrossApr(address(parityToken), 100_000);
        app.setBufferFeeConfig(address(parityToken), 100, 2_000, true);

        vm.warp(block.timestamp + 365 days);
        parityToken.mint(user, 0);

        assertEq(parityToken.balanceOf(address(app)), 10_000);
        assertEq(app.configurableVaultBalance(parityState.reserveVaultId, address(parityToken)), 7_200);
        assertEq(app.configurableVaultBalance(parityState.managementFeeVaultId, address(parityToken)), 1_000);
        assertEq(app.configurableVaultBalance(parityState.performanceFeeVaultId, address(parityToken)), 1_800);
    }

    function test_UntrackedSupplyChangeFailsClosedAfterActivation() public {
        managedToken.setBufferController(address(new NoopBufferController()));
        managedToken.mint(user, 1e9);
        managedToken.setBufferController(address(app));

        uint256 expectedSupply = app.getBufferState(address(managedToken)).previousSupply;
        uint256 actualSupply = managedToken.totalSupply();
        vm.expectRevert(
            abi.encodeWithSelector(
                BufferSupplyMismatchError.selector, address(managedToken), expectedSupply, actualSupply
            )
        );
        managedToken.mint(user, 1);
    }

    function test_BufferInitializationAndConfigurationGuards() public {
        vm.expectRevert(abi.encodeWithSelector(BufferAlreadyExistsError.selector, address(managedToken)));
        app.initializeBuffer(address(managedToken));

        ManagedToken secondToken = _deployToken(address(app));
        app.registerManagedToken(address(secondToken));
        app.initializeBuffer(address(secondToken));

        BufferState memory secondState = app.getBufferState(address(secondToken));
        assertEq(secondState.reserveVaultId, OnReIds._bufferReserveVaultId(address(secondToken)));
        assertEq(secondState.managementFeeVaultId, OnReIds._bufferManagementFeeVaultId(address(secondToken)));
        assertEq(secondState.performanceFeeVaultId, OnReIds._bufferPerformanceFeeVaultId(address(secondToken)));
        assertNotEq(secondState.reserveVaultId, bufferReserveVaultId);
        assertNotEq(secondState.managementFeeVaultId, managementFeeVaultId);
        assertNotEq(secondState.performanceFeeVaultId, performanceFeeVaultId);

        address secondVaultDestination = makeAddr("secondVaultDestination");
        app.updateConfigurableVault(secondState.reserveVaultId, secondVaultDestination, 0);
        ConfigurableVault memory firstReserveVault = app.getConfigurableVault(bufferReserveVaultId);
        ConfigurableVault memory secondReserveVault = app.getConfigurableVault(secondState.reserveVaultId);
        assertEq(firstReserveVault.withdrawalDestination, vaultDestination);
        assertEq(secondReserveVault.withdrawalDestination, secondVaultDestination);

        vm.expectRevert(abi.encodeWithSelector(InvalidBufferAprError.selector, 1_000_001));
        app.setBufferGrossApr(address(managedToken), 1_000_001);

        vm.expectRevert(InvalidBasisPointsError.selector);
        app.setBufferFeeConfig(address(managedToken), 10_001, 0, true);
    }

    function test_ControllerActivationBeforeBufferInitializationFailsClosed() public {
        ManagedToken unconfiguredToken = _deployToken(address(app));
        unconfiguredToken.setBufferController(address(app));

        vm.expectRevert(abi.encodeWithSelector(BufferNotFoundError.selector, address(unconfiguredToken)));
        unconfiguredToken.mint(user, 1);
    }

    function test_BurnForNavSettlesAccrualAndOnlyConsumesReserve() public {
        uint256 holderBalance = managedToken.balanceOf(address(this));
        vm.warp(block.timestamp + 365 days);
        uint256 adjustment = 100e9;
        uint256 accrued = INITIAL_SUPPLY / 10;
        uint256 managementFee = accrued / 10;
        uint256 performanceFee = (accrued - managementFee) / 5;
        uint256 reserve = accrued - managementFee - performanceFee;

        vm.expectEmit(true, false, false, true, address(app));
        emit BufferBurnedForNav(address(managedToken), adjustment, adjustment, INITIAL_SUPPLY + accrued, 1e9);
        assertEq(app.burnForNavIncrease(address(managedToken), adjustment), adjustment);

        assertEq(managedToken.totalSupply(), INITIAL_SUPPLY + accrued - adjustment);
        assertEq(managedToken.balanceOf(address(this)), holderBalance);
        assertEq(managedToken.balanceOf(address(app)), accrued - adjustment);
        assertEq(app.configurableVaultBalance(bufferReserveVaultId, address(managedToken)), reserve - adjustment);
        assertEq(app.configurableVaultBalance(managementFeeVaultId, address(managedToken)), managementFee);
        assertEq(app.configurableVaultBalance(performanceFeeVaultId, address(managedToken)), performanceFee);
        BufferState memory state = app.getBufferState(address(managedToken));
        assertEq(state.previousSupply, managedToken.totalSupply());
        assertEq(state.lastAccrualTimestamp, block.timestamp);
        assertEq(state.performanceFeeHighWatermark, 1e9);
        MarketStats memory stats = app.marketStats(address(managedToken));
        assertEq(stats.nav, 1e9);
        assertEq(stats.tvl, INITIAL_SUPPLY + accrued - adjustment);

        vm.warp(uint256(state.lastAccrualTimestamp) + 365 days);
        vm.prank(worker);
        assertEq(app.settleBuffer(address(managedToken)), state.previousSupply / 10);
        assertEq(app.getBufferState(address(managedToken)).previousSupply, managedToken.totalSupply());
    }

    function test_BurnForNavUsesActiveNavAndSolanaRounding() public {
        _setBurnNav(1_100_000_000);
        _depositBurnReserve(100e9);
        uint256 totalAssets = 1_100_000_000e9;
        uint256 expectedBurn = 90_909_090_909;

        vm.expectEmit(true, false, false, true, address(app));
        emit BufferBurnedForNav(address(managedToken), expectedBurn, 100e9, totalAssets, 1_100_000_000);
        assertEq(app.burnForNavIncrease(address(managedToken), 100e9), expectedBurn);
        assertEq(app.marketStats(address(managedToken)).nav, 1_100_000_000);
        assertEq(app.getBufferState(address(managedToken)).previousSupply, INITIAL_SUPPLY - expectedBurn);
    }

    function test_BurnForNavReserveAbsorbsAssetLossWhileHolderBackingStaysLevel() public {
        _setBurnNav(1_100_000_000);
        managedToken.grantBurnRole(address(this));
        managedToken.burn(INITIAL_SUPPLY - 1_000e9);
        _depositBurnReserve(200e9);

        // Model independently recorded USD backing: $1,100 for 1,000 ONyc, then a $110 loss.
        uint256 actualAssetsBefore = 1_100e9;
        uint256 actualAssetsAfter = actualAssetsBefore - 110e9;
        assertEq(actualAssetsBefore * 1e9 / managedToken.totalSupply(), 1_100_000_000);
        assertEq(actualAssetsAfter * 1e9 / managedToken.totalSupply(), 990_000_000);

        assertEq(app.burnForNavIncrease(address(managedToken), 110e9), 100e9);
        assertEq(managedToken.totalSupply(), 900e9);
        assertEq(managedToken.balanceOf(address(this)), 800e9);
        assertEq(app.configurableVaultBalance(bufferReserveVaultId, address(managedToken)), 100e9);
        assertEq(actualAssetsAfter * 1e9 / managedToken.totalSupply(), 1_100_000_000);
        assertEq(app.marketStats(address(managedToken)).tvl, actualAssetsAfter);
    }

    function testFuzz_BurnForNavRemainingSupplyBracketsAdjustedAssets(
        uint64 supplySeed,
        uint64 navSeed,
        uint64 adjustmentSeed
    ) public {
        uint256 circulatingSupply = bound(supplySeed, 100, 1e12);
        uint64 nav = uint64(bound(navSeed, 1e8, 3e9));
        _setBurnNav(nav);
        _depositBurnReserve(circulatingSupply);
        app.addExcludedSupplyAddress(address(managedToken), address(this));
        uint256 totalAssets = circulatingSupply * nav / 1e9;
        uint256 adjustment = bound(adjustmentSeed, 3, totalAssets - 1);
        uint256 adjustedAssetsScaled = (totalAssets - adjustment) * 1e9;

        uint256 burned = app.burnForNavIncrease(address(managedToken), adjustment);
        uint256 remaining = app.marketStats(address(managedToken)).circulatingSupply;
        // The remaining claims cover adjusted assets; one more base-unit burn would cross the target.
        assertGe(remaining * nav, adjustedAssetsScaled);
        assertLt((remaining - 1) * nav, adjustedAssetsScaled);
        assertEq(remaining, circulatingSupply - burned);
        assertEq(app.configurableVaultBalance(bufferReserveVaultId, address(managedToken)), remaining);
        assertEq(app.getBufferState(address(managedToken)).previousSupply, managedToken.totalSupply());
    }

    function test_BurnForNavUsesCirculatingSupplyAndFloorsTvlBeforeRoundingSupplyUp() public {
        _setBurnNav(1_100_000_000);
        _depositBurnReserve(1_003);
        app.addExcludedSupplyAddress(address(managedToken), address(this));
        // Solana reference: floor(1003 * 1.1) = 1103; ceil((1103 - 100) / 1.1) = 912.
        vm.expectEmit(true, false, false, true, address(app));
        emit BufferBurnedForNav(address(managedToken), 91, 100, 1_103, 1_100_000_000);
        assertEq(app.burnForNavIncrease(address(managedToken), 100), 91);
        assertEq(app.marketStats(address(managedToken)).circulatingSupply, 912);
        assertEq(managedToken.totalSupply(), INITIAL_SUPPLY - 91);
    }

    function test_BurnForNavRejectsAdjustmentAboveCirculatingTvl() public {
        _depositBurnReserve(100e9);
        app.addExcludedSupplyAddress(address(managedToken), address(this));
        vm.expectRevert(InvalidAssetAdjustmentAmountError.selector);
        app.burnForNavIncrease(address(managedToken), 100e9 + 1);
    }

    function test_BurnForNavCanConsumeEntireReserveAndCirculatingSupply() public {
        _depositBurnReserve(100e9);
        app.addExcludedSupplyAddress(address(managedToken), address(this));
        assertEq(app.burnForNavIncrease(address(managedToken), 100e9), 100e9);
        assertEq(app.configurableVaultBalance(bufferReserveVaultId, address(managedToken)), 0);
        assertEq(app.marketStats(address(managedToken)).circulatingSupply, 0);
        assertEq(app.getBufferState(address(managedToken)).previousSupply, managedToken.totalSupply());
    }

    function test_BurnForNavRejectsZeroAndSubTokenAdjustments() public {
        vm.expectRevert(NoBurnNeededError.selector);
        app.burnForNavIncrease(address(managedToken), 0);
        _setBurnNav(2e9);
        _depositBurnReserve(100);
        vm.expectRevert(NoBurnNeededError.selector);
        app.burnForNavIncrease(address(managedToken), 1);
    }

    function test_BurnForNavCannotSpendFeeVaultsOrUnaccountedTokensAndRollsBackAccrual() public {
        managedToken.transfer(address(app), INITIAL_SUPPLY / 2);
        BufferState memory beforeBurn = app.getBufferState(address(managedToken));
        vm.warp(block.timestamp + 365 days);
        uint256 expectedReserve = INITIAL_SUPPLY / 10 * 72 / 100;
        vm.expectRevert(abi.encodeWithSelector(InsufficientBalanceError.selector, expectedReserve, expectedReserve + 1));
        app.burnForNavIncrease(address(managedToken), expectedReserve + 1);

        assertEq(managedToken.totalSupply(), INITIAL_SUPPLY);
        assertEq(managedToken.balanceOf(address(app)), INITIAL_SUPPLY / 2);
        assertEq(app.configurableVaultBalance(bufferReserveVaultId, address(managedToken)), 0);
        assertEq(app.configurableVaultBalance(managementFeeVaultId, address(managedToken)), 0);
        assertEq(app.configurableVaultBalance(performanceFeeVaultId, address(managedToken)), 0);
        assertEq(abi.encode(app.getBufferState(address(managedToken))), abi.encode(beforeBurn));
    }

    function test_BurnForNavRequiresBossAndRespectsKillSwitch() public {
        address[3] memory unauthorized = [user, worker, admin];
        for (uint256 i; i < unauthorized.length; ++i) {
            vm.expectRevert(
                abi.encodeWithSelector(
                    IAccessControl.AccessControlUnauthorizedAccount.selector, unauthorized[i], bytes32(0)
                )
            );
            vm.prank(unauthorized[i]);
            app.burnForNavIncrease(address(managedToken), 1);
        }
        app.setKillSwitch(true);
        vm.expectRevert(KilledError.selector);
        app.burnForNavIncrease(address(managedToken), 1);
    }

    function test_BurnForNavRejectsExcludedDiamond() public {
        _depositBurnReserve(100e9);
        app.addExcludedSupplyAddress(address(managedToken), address(app));
        vm.expectRevert(abi.encodeWithSelector(BufferReserveExcludedFromSupplyError.selector, address(managedToken)));
        app.burnForNavIncrease(address(managedToken), 100e9);
    }

    function test_BurnForNavRequiresBufferAndCorrectController() public {
        ManagedToken otherToken = _deployToken(address(app));
        vm.expectRevert(abi.encodeWithSelector(BufferNotFoundError.selector, address(otherToken)));
        app.burnForNavIncrease(address(otherToken), 1);

        address wrongController = address(new NoopBufferController());
        managedToken.setBufferController(wrongController);
        vm.expectRevert(
            abi.encodeWithSelector(InvalidBufferControllerError.selector, address(managedToken), wrongController)
        );
        app.burnForNavIncrease(address(managedToken), 1);
    }

    function test_BurnForNavUsesControllerAuthorityWithoutOrdinaryBurnPermission() public {
        _depositBurnReserve(100e9);
        managedToken.revokeBurnRole(address(app));
        assertEq(app.burnForNavIncrease(address(managedToken), 100e9), 100e9);
        assertEq(app.configurableVaultBalance(bufferReserveVaultId, address(managedToken)), 0);
        assertEq(managedToken.totalSupply(), INITIAL_SUPPLY - 100e9);
        assertEq(app.getBufferState(address(managedToken)).previousSupply, INITIAL_SUPPLY - 100e9);
    }

    function test_BurnForNavRollsBackAccrualAndBaselineWhenTokenBurnFails() public {
        BufferState memory beforeBurn = app.getBufferState(address(managedToken));
        vm.warp(block.timestamp + 365 days);
        bytes memory failure = abi.encodeWithSelector(IManagedToken.NoChangeError.selector);
        vm.mockCallRevert(address(managedToken), abi.encodeCall(IManagedToken.burnBuffer, (100e9)), failure);
        vm.expectRevert(failure);
        app.burnForNavIncrease(address(managedToken), 100e9);
        assertEq(managedToken.totalSupply(), INITIAL_SUPPLY);
        assertEq(managedToken.balanceOf(address(app)), 0);
        assertEq(app.configurableVaultBalance(bufferReserveVaultId, address(managedToken)), 0);
        assertEq(app.configurableVaultBalance(managementFeeVaultId, address(managedToken)), 0);
        assertEq(app.configurableVaultBalance(performanceFeeVaultId, address(managedToken)), 0);
        assertEq(abi.encode(app.getBufferState(address(managedToken))), abi.encode(beforeBurn));
    }

    function test_BurnForNavSupportsLargeAmountsWithoutIntermediateOverflow() public {
        uint256 supply = uint256(1) << 240;
        managedToken.mint(address(this), supply - INITIAL_SUPPLY);
        _depositBurnReserve(supply);
        assertEq(app.burnForNavIncrease(address(managedToken), supply / 2), supply / 2);
        assertEq(managedToken.totalSupply(), supply / 2);
    }

    function testFuzz_BurnForNavUsesManagedTokenDecimals(uint8 decimalsSeed, uint64 adjustmentSeed) public {
        uint8 decimals = uint8(bound(decimalsSeed, 0, 18));
        uint256 scale = 10 ** uint256(decimals);
        uint256 adjustment = bound(adjustmentSeed, 2, 1_000_000) * scale;
        ManagedToken otherToken = _deployToken(address(app), decimals);
        otherToken.mint(address(this), 1_000_000 * scale);
        app.registerManagedToken(address(otherToken));
        bytes32 otherPricerId = app.createPricer(address(otherToken), PricingDenomination.Usd);
        app.addPricingVector(
            otherPricerId, PricingVector({startTime: 1, baseTime: 1, basePrice: 2e9, apr: 0, priceFixDuration: 1 days})
        );
        app.initializeBuffer(address(otherToken));
        otherToken.setBufferController(address(app));
        bytes32 reserveId = app.getBufferState(address(otherToken)).reserveVaultId;
        otherToken.approve(address(app), type(uint256).max);
        app.depositConfigurableVault(reserveId, address(otherToken), 1_000_000 * scale);

        assertEq(app.burnForNavIncrease(address(otherToken), adjustment), adjustment / 2);
        assertEq(otherToken.totalSupply(), 1_000_000 * scale - adjustment / 2);
        assertEq(app.getBufferState(address(otherToken)).previousSupply, otherToken.totalSupply());
        assertEq(managedToken.totalSupply(), INITIAL_SUPPLY);
    }

    function _depositBurnReserve(uint256 amount) private {
        managedToken.approve(address(app), amount);
        app.depositConfigurableVault(bufferReserveVaultId, address(managedToken), amount);
    }

    function _setBurnNav(uint64 nav) private {
        app.setBufferGrossApr(address(managedToken), 0);
        app.addPricingVector(
            pricerId, PricingVector({startTime: 2, baseTime: 2, basePrice: nav, apr: 0, priceFixDuration: 1 days})
        );
        vm.warp(2);
    }

    function _assertSolanaGrossAccrualVector(
        uint256 previousSupply,
        uint64 grossApr,
        uint64 currentApr,
        uint256 elapsed,
        uint256 expectedBufferMint
    ) private {
        vm.warp(1);
        ManagedToken parityToken = _deployToken(address(app));
        parityToken.mint(address(this), previousSupply);
        app.registerManagedToken(address(parityToken));

        bytes32 parityPricerId = app.createPricer(address(parityToken), PricingDenomination.Usd);
        app.addPricingVector(
            parityPricerId,
            PricingVector({
                startTime: uint64(block.timestamp),
                baseTime: uint64(block.timestamp),
                basePrice: 1e9,
                apr: currentApr,
                priceFixDuration: 1 days
            })
        );

        app.initializeBuffer(address(parityToken));
        bytes32 parityReserveVaultId = app.getBufferState(address(parityToken)).reserveVaultId;
        parityToken.setBufferController(address(app));
        app.setBufferGrossApr(address(parityToken), grossApr);

        vm.warp(block.timestamp + elapsed);
        parityToken.mint(user, 0);

        assertEq(parityToken.balanceOf(address(app)), expectedBufferMint);
        assertEq(app.configurableVaultBalance(parityReserveVaultId, address(parityToken)), expectedBufferMint);
        assertEq(app.getBufferState(address(parityToken)).previousSupply, previousSupply + expectedBufferMint);
    }
}

contract NoopBufferController is IBufferController {
    function onBeforeSupplyChange(uint256, bool) external pure {}
}
