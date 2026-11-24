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
