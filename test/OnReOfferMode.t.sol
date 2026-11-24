// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "../src/types/OnReAppErrors.sol";
import "../src/types/OnReAppEvents.sol";
import "../src/types/OnReTypes.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import "./helpers/OnReAppTestBase.sol";

/// @notice Offers store who may trade (access) separately from how a trade settles (execution).
contract OnReOfferModeTest is OnReAppTestBase {
    function test_StoredModesAndTheirLegacyFlow() public view {
        _assertMode(permissionedOfferId, OfferAccess.Permissioned, OfferExecution.Instant, OfferFlow.Permissioned);
        _assertMode(permissionlessOfferId, OfferAccess.Permissionless, OfferExecution.Instant, OfferFlow.Permissionless);
        _assertMode(workerOfferId, OfferAccess.Permissionless, OfferExecution.Worker, OfferFlow.Worker);
    }

    function test_CreationEmitsTheLegacyEventAndTheMode() public {
        bytes32 offerId = OnReIds._offerConfigId(address(usd), address(managedToken), 9);

        vm.expectEmit(address(app));
        emit OfferConfigCreated(
            offerId,
            address(usd),
            address(managedToken),
            OfferFlow.Permissionless,
            OfferDirection.AssetToManaged,
            navPermissionlessQuoterId,
            feeConfigId,
            proceedsVaultId,
            bytes32(0)
        );
        vm.expectEmit(address(app));
        emit OfferConfigModeSet(offerId, 9, OfferAccess.Permissionless, OfferExecution.Instant);
        app.makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: address(usd),
                tokenOut: address(managedToken),
                instanceId: 9,
                access: OfferAccess.Permissionless,
                execution: OfferExecution.Instant,
                quoterId: navPermissionlessQuoterId,
                feeConfigId: feeConfigId,
                proceedsVaultId: proceedsVaultId,
                liquidityVaultId: bytes32(0)
            })
        );
    }

    function test_RevertWhen_WorkerOfferIsPermissioned() public {
        vm.expectRevert(abi.encodeWithSelector(UnsupportedOfferFlowError.selector, uint8(OfferFlow.Worker)));
        app.makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: address(managedToken),
                tokenOut: address(usd),
                instanceId: 9,
                access: OfferAccess.Permissioned,
                execution: OfferExecution.Worker,
                quoterId: navQuoterId,
                feeConfigId: feeConfigId,
                proceedsVaultId: proceedsVaultId,
                liquidityVaultId: liquidityVaultId
            })
        );
    }

    function test_PermissionedOfferCanUseAPropAmmQuoter() public {
        bytes32 propAmmId = _createConfiguredPropAmm(0, _basePropAmmTestConfig());
        bytes32 offerId =
            _make(address(managedToken), address(usd), OfferAccess.Permissioned, OfferExecution.Instant, propAmmId);
        _depositLiquidity(1_000e6);
        managedToken.mint(user, 100e9);
        ApprovalMessage memory approval = ApprovalMessage({user: user, expiry: uint64(block.timestamp + 1 hours)});

        vm.startPrank(user);
        managedToken.approve(address(app), 100e9);
        // Without an approval the permissioned offer stays closed, whatever its quoter.
        vm.expectRevert(InvalidApprovalError.selector);
        app.takeOffer(_takeOfferParams(offerId, 100e9));
        uint256 amountOut =
            app.takeOffer(_permissionedTakeOfferParams(offerId, 100e9, approval, _signApproval(approval)));
        vm.stopPrank();

        // 99 managed tokens net of the 1% fee, priced at NAV 1.0 and reduced by the curve haircut.
        assertGt(amountOut, 0);
        assertLt(amountOut, 99e6);
        assertEq(usd.balanceOf(user), amountOut);
    }

    function test_WorkerOfferCanBuyManagedTokens() public {
        bytes32 offerId =
            _make(address(usd), address(managedToken), OfferAccess.Permissionless, OfferExecution.Worker, navQuoterId);
        _fundAndApproveUsd(user, 100e6);

        vm.prank(user);
        bytes32 requestId = app.createFulfillmentRequest(offerId, 1, 100e6);
        assertEq(usd.balanceOf(user), 0);
        vm.prank(worker);
        assertEq(app.fulfillWorkerRequest(requestId, 40e6), 39.6e9);
        vm.prank(worker);
        assertEq(app.fulfillWorkerRequest(requestId, 60e6), 59.4e9);

        assertEq(managedToken.balanceOf(user), 99e9);
        assertEq(app.configurableVaultBalance(feeVaultId, address(usd)), 1e6);
        assertEq(app.configurableVaultBalance(proceedsVaultId, address(usd)), 99e6);
    }

    function test_WorkerOfferCanUseAPropAmmQuoter() public {
        bytes32 propAmmId = _createConfiguredPropAmm(0, _basePropAmmTestConfig());
        bytes32 offerId =
            _make(address(managedToken), address(usd), OfferAccess.Permissionless, OfferExecution.Worker, propAmmId);
        _depositLiquidity(1_000e6);
        managedToken.mint(user, 100e9);

        vm.startPrank(user);
        managedToken.approve(address(app), 100e9);
        bytes32 requestId = app.createFulfillmentRequest(offerId, 1, 100e9);
        vm.stopPrank();
        vm.prank(worker);
        uint256 amountOut = app.fulfillWorkerRequest(requestId, 100e9);

        assertGt(amountOut, 0);
        assertLt(amountOut, 99e6);
        assertEq(usd.balanceOf(user), amountOut);
        // The fill is recorded as sell pressure on the quoter, like an instant trade.
        assertEq(app.getPropAmmState(propAmmId).currentSellTradeCount, 1);
    }

    function _make(address tokenIn, address tokenOut, OfferAccess access, OfferExecution execution, bytes32 quoterId)
        private
        returns (bytes32)
    {
        return app.makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                instanceId: 50,
                access: access,
                execution: execution,
                quoterId: quoterId,
                feeConfigId: feeConfigId,
                proceedsVaultId: proceedsVaultId,
                liquidityVaultId: liquidityVaultId
            })
        );
    }

    function _assertMode(bytes32 offerId, OfferAccess access, OfferExecution execution, OfferFlow legacyFlow)
        private
        view
    {
        OfferConfig memory offer = app.getOfferConfigV2(offerId);
        assertEq(uint8(offer.access), uint8(access));
        assertEq(uint8(offer.execution), uint8(execution));
        assertEq(uint8(app.getOfferConfig(offerId).flow), uint8(legacyFlow));
    }
}
