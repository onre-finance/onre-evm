// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "../src/types/OnReAppErrors.sol";
import "../src/types/OnReTypes.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import "./helpers/OnReAppTestBase.sol";

contract OnReOfferTest is OnReAppTestBase {
    function test_OfferIdentityIncludesDirectedPairAndFlow() public view {
        assertEq(permissionedOfferId, OnReIds.offerConfigId(address(usd), address(onReToken), OfferFlow.Permissioned));
        assertEq(
            permissionlessOfferId, OnReIds.offerConfigId(address(usd), address(onReToken), OfferFlow.Permissionless)
        );
        assertEq(workerOfferId, OnReIds.offerConfigId(address(onReToken), address(usd), OfferFlow.Worker));
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
                OnReIds.offerConfigId(address(onReToken), address(usd), OfferFlow.Permissionless)
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

    function testFuzz_NavPreviewMatchesDecimalScaling(uint96 rawInput) public view {
        uint256 inputAmount = bound(uint256(rawInput), 2, 1_000_000e6);
        ExecutionAccounting memory preview = app.previewExecution(permissionlessOfferId, inputAmount);
        assertEq(preview.grossInputAmount, inputAmount);
        assertEq(preview.amountOut, preview.netInputAmount * 1_000);
    }
}
