// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import "../src/types/OnReAppErrors.sol";
import "../src/types/OnReTypes.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import "./helpers/OnReAppTestBase.sol";

contract OnReVaultAndFeeTest is OnReAppTestBase {
    function test_FeeConfigRejectsMinimumThatConsumesGrossInput() public {
        app.updateFeeConfig(feeConfigId, 0, 1_000_000, feeVaultId);

        vm.expectRevert(InvalidAmountError.selector);
        app.previewExecution(permissionlessOfferId, 1_000_000);
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
}
