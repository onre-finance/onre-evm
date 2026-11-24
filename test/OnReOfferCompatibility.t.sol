// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {Vm} from "forge-std/Vm.sol";
import "../src/types/OnReTypes.sol";
import "./helpers/OnReAppTestBase.sol";

/// @notice Pins what deployed offers and their integrators depend on: offer IDs,
/// the `OfferConfig` storage layout, and the user-facing ABI.
/// @dev The literals below were computed from `origin/main` before the offer
/// identity rework. They must never change.
contract OnReOfferCompatibilityTest is OnReAppTestBase {
    // Ethereum mainnet tokens of the three live offers (script/config/ethereum-mainnet-live.json).
    address private constant ONYC = 0xaD6cbfC79DA040713BFFB939f16927c15BAdc837;
    address private constant USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address private constant USDG = 0xe343167631d89B6Ffc58B88d6b7fB0228795491D;

    bytes32 private constant USDC_TO_ONYC_OFFER_ID = 0xc157e1b42a0d156ed9cdf581d84aa25bcc7f4791874ea5bedcbeddd05fda1cbd;
    bytes32 private constant USDG_TO_ONYC_OFFER_ID = 0x97e2af726c8996c5cf593102de2f73798fe2edb30b4cb1c120e29446fc1b35cc;
    bytes32 private constant ONYC_TO_USDG_OFFER_ID = 0x86092dbbf68dd31d80637436a5709cacee0b8dfc80749269d769089ca48b1535;

    /// @dev `offerConfigs` is the seventh member of `LibOnReStorage.AppStorage`.
    uint256 private constant OFFER_CONFIGS_MEMBER_INDEX = 6;

    bytes32 private constant OFFER_EXECUTED_TOPIC = 0xe97aa63f080aafac8f3fec798a034ae24510afd7ee9d260de1ba87a74b488a63;

    function test_LiveMainnetOfferIdsAreStable() public pure {
        assertEq(_legacyOfferId(USDC, ONYC, OfferFlow.Permissionless), USDC_TO_ONYC_OFFER_ID);
        assertEq(_legacyOfferId(USDG, ONYC, OfferFlow.Permissionless), USDG_TO_ONYC_OFFER_ID);
        assertEq(_legacyOfferId(ONYC, USDG, OfferFlow.Permissionless), ONYC_TO_USDG_OFFER_ID);
    }

    function test_OfferIdsOfEveryLegacyFlowAreStable() public view {
        assertEq(permissionedOfferId, _legacyOfferId(address(usd), address(managedToken), OfferFlow.Permissioned));
        assertEq(permissionlessOfferId, _legacyOfferId(address(usd), address(managedToken), OfferFlow.Permissionless));
        assertEq(workerOfferId, _legacyOfferId(address(managedToken), address(usd), OfferFlow.Worker));
    }

    function test_OfferConfigStorageLayoutIsStable() public view {
        // Slot 0: tokenIn in the low 20 bytes, then one byte each for flow and direction.
        assertEq(
            _offerSlot(permissionlessOfferId, 0) & bytes32(uint256(type(uint176).max)),
            bytes32(
                uint256(uint160(address(usd))) | uint256(uint8(OfferFlow.Permissionless)) << 160
                    | uint256(uint8(OfferDirection.AssetToManaged)) << 168
            )
        );
        assertEq(
            _offerSlot(workerOfferId, 0) & bytes32(uint256(type(uint176).max)),
            bytes32(
                uint256(uint160(address(managedToken))) | uint256(uint8(OfferFlow.Worker)) << 160
                    | uint256(uint8(OfferDirection.ManagedToAsset)) << 168
            )
        );
        assertEq(_offerSlot(permissionlessOfferId, 1), navPermissionlessQuoterId);
        assertEq(_offerSlot(permissionlessOfferId, 2), feeConfigId);
        assertEq(_offerSlot(permissionlessOfferId, 3), proceedsVaultId);
        assertEq(_offerSlot(permissionlessOfferId, 4), liquidityVaultId);
        // Slot 5: tokenOut, tokenOutDecimals, tokenInDecimals, enabled, exists.
        assertEq(
            _offerSlot(permissionlessOfferId, 5),
            bytes32(
                uint256(uint160(address(managedToken))) | uint256(9) << 160 | uint256(6) << 168 | uint256(1) << 176
                    | uint256(1) << 184
            )
        );
    }

    function test_UserFacingSelectorsAreStable() public view {
        assertEq(app.takeOffer.selector, bytes4(0x2b337c21));
        assertEq(app.previewExecution.selector, bytes4(0xceaf1761));
        assertEq(app.createFulfillmentRequest.selector, bytes4(0x0753f8e5));
        assertEq(app.cancelFulfillmentRequest.selector, bytes4(0x8067a539));
        assertEq(app.fulfillWorkerRequest.selector, bytes4(0xeb00c4a8));
        assertEq(app.getOfferConfig.selector, bytes4(0x87982501));
    }

    function test_GetOfferConfigReturnsTheLegacyTwelveWordShape() public view {
        _assertLegacyOfferView(permissionedOfferId, address(usd), address(managedToken), OfferFlow.Permissioned);
        _assertLegacyOfferView(permissionlessOfferId, address(usd), address(managedToken), OfferFlow.Permissionless);
        _assertLegacyOfferView(workerOfferId, address(managedToken), address(usd), OfferFlow.Worker);
    }

    function test_OfferExecutedKeepsItsTopicsAndFlowValue() public {
        _fundAndApproveUsd(user, 100e6);
        vm.recordLogs();
        vm.prank(user);
        app.takeOffer(_takeOfferParams(permissionlessOfferId, 100e6));

        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i; i < logs.length; ++i) {
            if (logs[i].topics[0] != OFFER_EXECUTED_TOPIC) continue;
            found = true;
            assertEq(logs[i].topics.length, 4);
            assertEq(logs[i].topics[1], permissionlessOfferId);
            assertEq(logs[i].topics[2], bytes32(uint256(uint160(user))));
            assertEq(logs[i].topics[3], bytes32(uint256(uint8(OfferFlow.Permissionless))));
            assertEq(logs[i].data.length, 7 * 32);
        }
        assertTrue(found);
    }

    function _assertLegacyOfferView(bytes32 offerId, address tokenIn, address tokenOut, OfferFlow flow) private view {
        (bool ok, bytes memory data) = address(app).staticcall(abi.encodeWithSelector(0x87982501, offerId));
        assertTrue(ok);
        assertEq(data.length, 12 * 32);
        (
            address viewTokenIn,
            uint8 viewFlow,
            uint8 viewDirection,
            bytes32 viewQuoterId,
            bytes32 viewFeeConfigId,
            bytes32 viewProceedsVaultId,
            bytes32 viewLiquidityVaultId,
            address viewTokenOut,
            uint8 viewTokenOutDecimals,
            uint8 viewTokenInDecimals,
            bool viewEnabled,
            bool viewExists
        ) = abi.decode(
            data, (address, uint8, uint8, bytes32, bytes32, bytes32, bytes32, address, uint8, uint8, bool, bool)
        );
        bool isBuy = tokenOut == address(managedToken);
        assertEq(viewTokenIn, tokenIn);
        assertEq(viewFlow, uint8(flow));
        assertEq(viewDirection, uint8(isBuy ? OfferDirection.AssetToManaged : OfferDirection.ManagedToAsset));
        assertEq(viewQuoterId, flow == OfferFlow.Permissionless ? navPermissionlessQuoterId : navQuoterId);
        assertEq(viewFeeConfigId, feeConfigId);
        assertEq(viewProceedsVaultId, proceedsVaultId);
        assertEq(viewLiquidityVaultId, liquidityVaultId);
        assertEq(viewTokenOut, tokenOut);
        assertEq(viewTokenOutDecimals, isBuy ? 9 : 6);
        assertEq(viewTokenInDecimals, isBuy ? 6 : 9);
        assertTrue(viewEnabled);
        assertTrue(viewExists);
    }

    /// @dev The original derivation, restated here so the pin does not depend on `OnReIds`.
    function _legacyOfferId(address tokenIn, address tokenOut, OfferFlow flow) private pure returns (bytes32) {
        return keccak256(abi.encode(keccak256("onre.offer_config"), tokenIn, tokenOut, flow));
    }

    function _offerSlot(bytes32 offerId, uint256 offset) private view returns (bytes32) {
        uint256 mappingSlot = uint256(APP_STORAGE_LOCATION) + OFFER_CONFIGS_MEMBER_INDEX;
        return vm.load(address(app), bytes32(uint256(keccak256(abi.encode(offerId, mappingSlot))) + offset));
    }
}
