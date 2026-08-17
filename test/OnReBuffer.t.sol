// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {
    BufferAlreadyExistsError,
    BufferNotFoundError,
    BufferSupplyMismatchError,
    DuplicateBufferVaultError,
    InvalidBasisPointsError,
    InvalidBufferAprError,
    InvalidConfigurableVaultKindError
} from "../src/types/OnReAppErrors.sol";
import {
    BufferState,
    ConfigurableVaultKind,
    MarketStats,
    PricingDenomination,
    PricingVector
} from "../src/types/OnReTypes.sol";
import {IOnReToken} from "../src/IOnReToken.sol";
import {IOnReBufferController} from "../src/IOnReBufferController.sol";
import {OnReToken} from "../src/OnReToken.sol";
import {OnReAppTestBase} from "./helpers/OnReAppTestBase.sol";

contract OnReBufferTest is OnReAppTestBase {
    uint64 private constant GROSS_APR = 100_000;
    uint16 private constant MANAGEMENT_FEE_BPS = 100;
    uint16 private constant PERFORMANCE_FEE_BPS = 2_000;

    bytes32 private bufferReserveVaultId;
    bytes32 private managementFeeVaultId;
    bytes32 private performanceFeeVaultId;

    function setUp() public override {
        super.setUp();

        bufferReserveVaultId = app.createConfigurableVault(ConfigurableVaultKind.BufferReserve, 0, vaultDestination, 0);
        managementFeeVaultId = app.createConfigurableVault(ConfigurableVaultKind.Fee, 1, vaultDestination, 0);
        performanceFeeVaultId = app.createConfigurableVault(ConfigurableVaultKind.Fee, 2, vaultDestination, 0);
        app.initializeBuffer(address(onReToken), bufferReserveVaultId, managementFeeVaultId, performanceFeeVaultId);
        onReToken.setBufferController(address(app));
        app.setBufferGrossApr(address(onReToken), GROSS_APR);
        app.setBufferFeeConfig(address(onReToken), MANAGEMENT_FEE_BPS, PERFORMANCE_FEE_BPS, true);
    }

    function test_MintSettlesBufferOnceAndStoresPostMintSupply() public {
        uint256 startingSupply = onReToken.totalSupply();
        uint256 mintAmount = 100e9;
        vm.warp(block.timestamp + 365 days / 2);

        onReToken.mint(user, mintAmount);

        uint256 expectedBufferMint = startingSupply * GROSS_APR * (365 days / 2) / (365 days * 1_000_000);
        uint256 expectedManagementFee = expectedBufferMint * 10_000 / GROSS_APR;
        uint256 expectedAfterManagement = expectedBufferMint - expectedManagementFee;
        uint256 expectedPerformanceFee = expectedAfterManagement * PERFORMANCE_FEE_BPS / 10_000;
        uint256 expectedReserveMint = expectedAfterManagement - expectedPerformanceFee;

        assertEq(onReToken.balanceOf(address(app)), expectedBufferMint);
        assertEq(app.configurableVaultBalance(bufferReserveVaultId, address(onReToken)), expectedReserveMint);
        assertEq(app.configurableVaultBalance(managementFeeVaultId, address(onReToken)), expectedManagementFee);
        assertEq(app.configurableVaultBalance(performanceFeeVaultId, address(onReToken)), expectedPerformanceFee);

        uint256 expectedPostMintSupply = startingSupply + expectedBufferMint + mintAmount;
        BufferState memory state = app.getBufferState(address(onReToken));
        assertEq(state.previousSupply, expectedPostMintSupply);
        assertEq(onReToken.totalSupply(), expectedPostMintSupply);
        assertEq(onReToken.balanceOf(user), mintAmount);
        assertEq(app.getExcludedSupplyAccounts(address(onReToken)).length, 0);

        MarketStats memory stats = app.marketStats(address(onReToken));
        assertEq(stats.circulatingSupply, expectedBufferMint + mintAmount);
    }

    function test_BurnAndBurnFromSettleBeforeSupplyChange() public {
        onReToken.grantBurnRole(address(this));
        onReToken.mint(address(this), 200e9);
        onReToken.mint(user, 100e9);

        vm.prank(user);
        onReToken.approve(address(this), 40e9);

        vm.warp(block.timestamp + 30 days);
        onReToken.burn(50e9);
        BufferState memory afterDirectBurn = app.getBufferState(address(onReToken));
        assertEq(afterDirectBurn.previousSupply, onReToken.totalSupply());

        vm.warp(block.timestamp + 30 days);
        onReToken.burnFrom(user, 40e9);
        BufferState memory afterBurnFrom = app.getBufferState(address(onReToken));
        assertEq(afterBurnFrom.previousSupply, onReToken.totalSupply());
        assertEq(onReToken.balanceOf(user), 60e9);
    }

    function test_ControllerOnlyMintBufferDoesNotRecursivelyAccrue() public {
        vm.expectRevert(abi.encodeWithSelector(IOnReToken.SenderNotBufferControllerError.selector, address(this)));
        onReToken.mintBuffer(1);

        uint256 startingSupply = onReToken.totalSupply();
        vm.warp(block.timestamp + 365 days);
        onReToken.mint(user, 1);

        uint256 expectedBufferMint = startingSupply * GROSS_APR / 1_000_000;
        assertEq(onReToken.balanceOf(address(app)), expectedBufferMint);
        assertEq(onReToken.totalSupply(), startingSupply + expectedBufferMint + 1);
        assertEq(app.getBufferState(address(onReToken)).previousSupply, onReToken.totalSupply());
    }

    function test_WorkerCanSettleWithoutAnExternalSupplyChange() public {
        uint256 startingSupply = onReToken.totalSupply();
        vm.warp(block.timestamp + 90 days);

        vm.prank(worker);
        uint256 mintedAmount = app.settleBuffer(address(onReToken));

        uint256 expectedMint = startingSupply * GROSS_APR * 90 days / (365 days * 1_000_000);
        assertEq(mintedAmount, expectedMint);
        assertEq(onReToken.totalSupply(), startingSupply + expectedMint);
        assertEq(app.getBufferState(address(onReToken)).previousSupply, onReToken.totalSupply());

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, address(this), app.WORKER_ROLE()
            )
        );
        app.settleBuffer(address(onReToken));
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

        onReToken.mint(user, 1);

        assertEq(app.configurableVaultBalance(performanceFeeVaultId, address(onReToken)), 0);
        BufferState memory state = app.getBufferState(address(onReToken));
        assertEq(state.performanceFeeHighWatermark, 1e9);
    }

    function test_AccrualDiscountsForNavAprAlreadyEarned() public {
        app.setBufferGrossApr(address(onReToken), 150_000);
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
        uint256 startingSupply = onReToken.totalSupply();
        uint256 elapsed = 365 days / 2;
        vm.warp(block.timestamp + elapsed);

        onReToken.mint(user, 1);

        uint256 expectedBufferMint = startingSupply * 100_000 * elapsed / (365 days * 1_000_000 + 50_000 * elapsed);
        assertEq(onReToken.balanceOf(address(app)), expectedBufferMint);
    }

    function test_BufferGrossAccrualMatchesSolanaReferenceVectors() public {
        _assertSolanaGrossAccrualVector(10, 1_000_000_000, 150_000, 50_000, 365 days / 2, 48_780_487);
        _assertSolanaGrossAccrualVector(20, 1_000_000_000, 120_000, 20_000, 365 days, 98_039_215);
        _assertSolanaGrossAccrualVector(30, 2_500_000_000, 300_000, 100_000, 365 days / 4, 121_951_219);
        _assertSolanaGrossAccrualVector(40, 1_000_000_000, 80_000, 60_000, 30 days, 1_635_768);
    }

    function test_BufferFeeSplitMatchesSolanaReferenceVector() public {
        OnReToken parityToken = _deployToken(address(app));
        parityToken.mint(inventorySource, 100_000);
        app.registerOnReToken(address(parityToken), inventorySource);

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

        bytes32 reserveVaultId =
            app.createConfigurableVault(ConfigurableVaultKind.BufferReserve, 50, vaultDestination, 0);
        bytes32 managementVaultId = app.createConfigurableVault(ConfigurableVaultKind.Fee, 51, vaultDestination, 0);
        bytes32 performanceVaultId = app.createConfigurableVault(ConfigurableVaultKind.Fee, 52, vaultDestination, 0);
        app.initializeBuffer(address(parityToken), reserveVaultId, managementVaultId, performanceVaultId);
        parityToken.setBufferController(address(app));
        app.setBufferGrossApr(address(parityToken), 100_000);
        app.setBufferFeeConfig(address(parityToken), 100, 2_000, true);

        vm.warp(block.timestamp + 365 days);
        parityToken.mint(user, 0);

        assertEq(parityToken.balanceOf(address(app)), 10_000);
        assertEq(app.configurableVaultBalance(reserveVaultId, address(parityToken)), 7_200);
        assertEq(app.configurableVaultBalance(managementVaultId, address(parityToken)), 1_000);
        assertEq(app.configurableVaultBalance(performanceVaultId, address(parityToken)), 1_800);
    }

    function test_UntrackedSupplyChangeFailsClosedAfterActivation() public {
        onReToken.setBufferController(address(new NoopBufferController()));
        onReToken.mint(user, 1e9);
        onReToken.setBufferController(address(app));

        uint256 expectedSupply = app.getBufferState(address(onReToken)).previousSupply;
        uint256 actualSupply = onReToken.totalSupply();
        vm.expectRevert(
            abi.encodeWithSelector(BufferSupplyMismatchError.selector, address(onReToken), expectedSupply, actualSupply)
        );
        onReToken.mint(user, 1);
    }

    function test_BufferInitializationAndConfigurationGuards() public {
        vm.expectRevert(abi.encodeWithSelector(BufferAlreadyExistsError.selector, address(onReToken)));
        app.initializeBuffer(address(onReToken), bufferReserveVaultId, managementFeeVaultId, performanceFeeVaultId);

        OnReToken secondToken = _deployToken(address(app));
        app.registerOnReToken(address(secondToken), inventorySource);

        vm.expectRevert(abi.encodeWithSelector(DuplicateBufferVaultError.selector, managementFeeVaultId));
        app.initializeBuffer(address(secondToken), bufferReserveVaultId, managementFeeVaultId, managementFeeVaultId);

        vm.expectRevert(
            abi.encodeWithSelector(
                InvalidConfigurableVaultKindError.selector,
                feeVaultId,
                uint8(ConfigurableVaultKind.BufferReserve),
                uint8(ConfigurableVaultKind.Fee)
            )
        );
        app.initializeBuffer(address(secondToken), feeVaultId, managementFeeVaultId, performanceFeeVaultId);

        vm.expectRevert(abi.encodeWithSelector(InvalidBufferAprError.selector, 1_000_001));
        app.setBufferGrossApr(address(onReToken), 1_000_001);

        vm.expectRevert(InvalidBasisPointsError.selector);
        app.setBufferFeeConfig(address(onReToken), 10_001, 0, true);
    }

    function test_ControllerActivationBeforeBufferInitializationFailsClosed() public {
        OnReToken unconfiguredToken = _deployToken(address(app));
        unconfiguredToken.setBufferController(address(app));

        vm.expectRevert(abi.encodeWithSelector(BufferNotFoundError.selector, address(unconfiguredToken)));
        unconfiguredToken.mint(user, 1);
    }

    function _assertSolanaGrossAccrualVector(
        uint64 firstVaultInstanceId,
        uint256 previousSupply,
        uint64 grossApr,
        uint64 currentApr,
        uint256 elapsed,
        uint256 expectedBufferMint
    ) private {
        vm.warp(1);
        OnReToken parityToken = _deployToken(address(app));
        parityToken.mint(inventorySource, previousSupply);
        app.registerOnReToken(address(parityToken), inventorySource);

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

        bytes32 reserveVaultId =
            app.createConfigurableVault(ConfigurableVaultKind.BufferReserve, firstVaultInstanceId, vaultDestination, 0);
        bytes32 managementVaultId =
            app.createConfigurableVault(ConfigurableVaultKind.Fee, firstVaultInstanceId + 1, vaultDestination, 0);
        bytes32 performanceVaultId =
            app.createConfigurableVault(ConfigurableVaultKind.Fee, firstVaultInstanceId + 2, vaultDestination, 0);
        app.initializeBuffer(address(parityToken), reserveVaultId, managementVaultId, performanceVaultId);
        parityToken.setBufferController(address(app));
        app.setBufferGrossApr(address(parityToken), grossApr);

        vm.warp(block.timestamp + elapsed);
        parityToken.mint(user, 0);

        assertEq(parityToken.balanceOf(address(app)), expectedBufferMint);
        assertEq(app.configurableVaultBalance(reserveVaultId, address(parityToken)), expectedBufferMint);
        assertEq(app.getBufferState(address(parityToken)).previousSupply, previousSupply + expectedBufferMint);
    }
}

contract NoopBufferController is IOnReBufferController {
    function onBeforeSupplyChange(uint256, bool) external pure {}
}
