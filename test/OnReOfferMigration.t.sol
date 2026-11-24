// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IAccessControl} from "@openzeppelin/contracts/access/IAccessControl.sol";
import {stdError} from "forge-std/StdError.sol";
import "../src/types/OnReAppErrors.sol";
import "../src/types/OnReAppEvents.sol";
import "../src/types/OnReTypes.sol";
import "./helpers/OnReAppTestBase.sol";

/// @notice Offers stored by the pre-instance layout are rewritten in place and keep their IDs.
/// @dev Legacy storage is reproduced by overwriting the first slot with what the old code wrote:
/// tokenIn, the flow byte, the direction byte, and zeroes above.
contract OnReOfferMigrationTest is OnReAppTestBase {
    uint256 private constant OFFER_CONFIGS_MEMBER_INDEX = 6;

    function setUp() public override {
        super.setUp();
        _storeLegacyFirstSlot(permissionedOfferId, address(usd), OfferFlow.Permissioned, OfferDirection.AssetToManaged);
        _storeLegacyFirstSlot(
            permissionlessOfferId, address(usd), OfferFlow.Permissionless, OfferDirection.AssetToManaged
        );
        _storeLegacyFirstSlot(workerOfferId, address(managedToken), OfferFlow.Worker, OfferDirection.ManagedToAsset);
    }

    function test_InstantOffersWorkBeforeMigration() public {
        // Permissioned and Permissionless flows share their values with OfferAccess.
        assertEq(uint8(app.getOfferConfig(permissionedOfferId).flow), uint8(OfferFlow.Permissioned));
        assertEq(uint8(app.getOfferConfig(permissionlessOfferId).flow), uint8(OfferFlow.Permissionless));
        assertEq(app.getOfferConfigV2(permissionlessOfferId).instanceId, 0);

        _fundAndApproveUsd(user, 100e6);
        vm.prank(user);
        assertEq(app.takeOffer(_takeOfferParams(permissionlessOfferId, 100e6)), 99e9);
    }

    function test_LegacyWorkerOfferCannotBeReadBeforeMigration() public {
        vm.expectRevert(stdError.enumConversionError);
        app.getOfferConfig(workerOfferId);
    }

    function test_MigrationStoresInstanceIdsAndRewritesWorkerOffers() public {
        vm.expectEmit(address(app));
        emit OfferConfigModeSet(permissionlessOfferId, 1, OfferAccess.Permissionless, OfferExecution.Instant);
        vm.expectEmit(address(app));
        emit OfferConfigModeSet(workerOfferId, 2, OfferAccess.Permissionless, OfferExecution.Worker);
        // A legacy Permissioned offer already is instance 0 and is skipped.
        assertEq(app.migrateOfferConfigs(_allOffers()), 2);

        _assertOffer(permissionedOfferId, 0, OfferAccess.Permissioned, OfferExecution.Instant, OfferFlow.Permissioned);
        _assertOffer(
            permissionlessOfferId, 1, OfferAccess.Permissionless, OfferExecution.Instant, OfferFlow.Permissionless
        );
        _assertOffer(workerOfferId, 2, OfferAccess.Permissionless, OfferExecution.Worker, OfferFlow.Worker);
    }

    function test_MigratedWorkerOfferAcceptsAndFillsRequests() public {
        app.migrateOfferConfigs(_allOffers());
        _depositLiquidity(1_000e6);
        managedToken.mint(user, 100e9);

        vm.startPrank(user);
        managedToken.approve(address(app), 100e9);
        bytes32 requestId = app.createFulfillmentRequest(workerOfferId, 1, 100e9);
        vm.stopPrank();
        vm.prank(worker);
        assertEq(app.fulfillWorkerRequest(requestId, 100e9), 99e6);
        assertEq(usd.balanceOf(user), 99e6);
    }

    function test_MigrationIsIdempotent() public {
        app.migrateOfferConfigs(_allOffers());

        vm.recordLogs();
        assertEq(app.migrateOfferConfigs(_allOffers()), 0);
        assertEq(vm.getRecordedLogs().length, 0);
        _assertOffer(workerOfferId, 2, OfferAccess.Permissionless, OfferExecution.Worker, OfferFlow.Worker);
    }

    function test_MigrationSkipsOffersCreatedWithAnInstanceId() public {
        bytes32 offerId = app.makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: address(usd),
                tokenOut: address(managedToken),
                instanceId: 77,
                access: OfferAccess.Permissionless,
                execution: OfferExecution.Instant,
                quoterId: navPermissionlessQuoterId,
                feeConfigId: feeConfigId,
                proceedsVaultId: proceedsVaultId,
                liquidityVaultId: bytes32(0)
            })
        );
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = offerId;

        assertEq(app.migrateOfferConfigs(ids), 0);
        assertEq(app.getOfferConfigV2(offerId).instanceId, 77);
    }

    function test_RevertWhen_MigratedOfferDoesNotExist() public {
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = keccak256("missing offer");

        vm.expectRevert(abi.encodeWithSelector(OfferConfigNotFoundError.selector, ids[0]));
        app.migrateOfferConfigs(ids);
    }

    function test_RevertWhen_StoredOfferDoesNotMatchItsId() public {
        // The stored flow says Permissioned, but the ID was derived for Permissionless.
        _storeLegacyFirstSlot(
            permissionlessOfferId, address(managedToken), OfferFlow.Permissioned, OfferDirection.AssetToManaged
        );
        bytes32[] memory ids = new bytes32[](1);
        ids[0] = permissionlessOfferId;

        vm.expectRevert(abi.encodeWithSelector(OfferConfigNotMigratableError.selector, permissionlessOfferId));
        app.migrateOfferConfigs(ids);
    }

    function test_RevertWhen_MigrationCallerIsNotBoss() public {
        bytes32[] memory ids = _allOffers();

        vm.expectRevert(
            abi.encodeWithSelector(
                IAccessControl.AccessControlUnauthorizedAccount.selector, user, app.DEFAULT_ADMIN_ROLE()
            )
        );
        vm.prank(user);
        app.migrateOfferConfigs(ids);
    }

    function _assertOffer(
        bytes32 offerId,
        uint64 instanceId,
        OfferAccess access,
        OfferExecution execution,
        OfferFlow legacyFlow
    ) private view {
        OfferConfig memory offer = app.getOfferConfigV2(offerId);
        assertEq(offer.instanceId, instanceId);
        assertEq(uint8(offer.access), uint8(access));
        assertEq(uint8(offer.execution), uint8(execution));
        assertEq(uint8(app.getOfferConfig(offerId).flow), uint8(legacyFlow));
    }

    function _allOffers() private view returns (bytes32[] memory ids) {
        ids = new bytes32[](3);
        ids[0] = permissionedOfferId;
        ids[1] = permissionlessOfferId;
        ids[2] = workerOfferId;
    }

    function _storeLegacyFirstSlot(bytes32 offerId, address tokenIn, OfferFlow flow, OfferDirection direction) private {
        uint256 mappingSlot = uint256(APP_STORAGE_LOCATION) + OFFER_CONFIGS_MEMBER_INDEX;
        vm.store(
            address(app),
            keccak256(abi.encode(offerId, mappingSlot)),
            bytes32(uint256(uint160(tokenIn)) | uint256(uint8(flow)) << 160 | uint256(uint8(direction)) << 168)
        );
    }
}
