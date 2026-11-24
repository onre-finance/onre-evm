// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {Test} from "forge-std/Test.sol";
import {IDiamondCut} from "../../src/diamond/contracts/interfaces/IDiamondCut.sol";
import {IDiamondLoupe} from "../../src/diamond/contracts/interfaces/IDiamondLoupe.sol";
import {IDiamondProxy} from "../../src/generated/IDiamondProxy.sol";
import {LibDiamondHelper} from "../../src/generated/LibDiamondHelper.sol";
import {IManagedToken} from "../../src/IManagedToken.sol";
import {
    MakeOfferConfigParams,
    OfferAccess,
    OfferConfig,
    OfferConfigView,
    OfferExecution,
    TakeOfferParams
} from "../../src/types/OnReTypes.sol";
import {OnReIds} from "../../src/libraries/OnReIds.sol";

/// @notice Rehearses the offer identity upgrade against the live Ethereum mainnet Diamond.
/// @dev Runs only when ETH_MAINNET_RPC_URL is set:
/// `ETH_MAINNET_RPC_URL=<rpc> forge test --match-contract OnReOfferUpgradeForkTest -vv`.
/// The cut is built the way Gemforge builds it: every application facet is redeployed, existing
/// selectors are replaced, new ones added, and selectors that no longer exist removed.
contract OnReOfferUpgradeForkTest is Test {
    address private constant DIAMOND = 0xf199FC4f70a020745c41aa452A0dc43DB9a2ca2D;
    address private constant SAFE = 0xbD590530dC8AD7427a526Bd071e4f3B6047B605E;

    bytes32 private constant USDC_TO_ONYC = 0xc157e1b42a0d156ed9cdf581d84aa25bcc7f4791874ea5bedcbeddd05fda1cbd;
    bytes32 private constant USDG_TO_ONYC = 0x97e2af726c8996c5cf593102de2f73798fe2edb30b4cb1c120e29446fc1b35cc;
    bytes32 private constant ONYC_TO_USDG = 0x86092dbbf68dd31d80637436a5709cacee0b8dfc80749269d769089ca48b1535;

    uint256 private constant OFFER_CONFIGS_SLOT =
        uint256(0x31164558df59313d3ca3903acf513b2eda293f9424839a72cebf9d8c78813700) + 6;

    IDiamondProxy private app = IDiamondProxy(DIAMOND);
    address private trader = makeAddr("trader");
    bool private forked;

    struct Observation {
        bytes offerView;
        bytes preview;
        bytes32[5] referenceSlots;
        bool tradeSucceeded;
        bytes tradeResult;
    }

    function setUp() public {
        string memory rpcUrl = vm.envOr("ETH_MAINNET_RPC_URL", string(""));
        if (bytes(rpcUrl).length == 0) return;
        vm.createSelectFork(rpcUrl);
        forked = true;
    }

    function test_UpgradeKeepsLiveOffersAndTheirResults() public {
        if (!forked) {
            vm.skip(true);
            return;
        }
        bytes32[] memory ids = _liveOffers();
        // Live offers may be paused; previews and trades need them enabled before and after alike.
        for (uint256 i; i < ids.length; ++i) {
            if (!app.getOfferConfig(ids[i]).enabled) {
                vm.prank(SAFE);
                app.setOfferConfigEnabled(ids[i], true);
            }
        }

        Observation[] memory beforeUpgrade = _observe(ids);
        for (uint256 i; i < ids.length; ++i) {
            // Visible with -vv: whether the comparison covers a settled trade or a matching revert.
            emit log_named_bytes32("offer", ids[i]);
            emit log_named_string(
                "  takeOffer before upgrade", beforeUpgrade[i].tradeSucceeded ? "settled" : "reverted"
            );
            emit log_named_bytes("  takeOffer result", beforeUpgrade[i].tradeResult);
        }

        _upgrade();
        // Instant offers work between the cut and the migration; only the stored instance ID is missing.
        _assertSame(beforeUpgrade, _observe(ids), "after cut");
        for (uint256 i; i < ids.length; ++i) {
            OfferConfig memory offer = app.getOfferConfigV2(ids[i]);
            assertEq(offer.instanceId, 0);
            assertEq(uint8(offer.access), uint8(OfferAccess.Permissionless));
            assertEq(uint8(offer.execution), uint8(OfferExecution.Instant));
        }

        vm.prank(SAFE);
        assertEq(app.migrateOfferConfigs(ids), ids.length);
        _assertSame(beforeUpgrade, _observe(ids), "after migration");
        for (uint256 i; i < ids.length; ++i) {
            OfferConfig memory offer = app.getOfferConfigV2(ids[i]);
            // A formerly permissionless offer is instance 1 of its pair, under the same ID.
            assertEq(offer.instanceId, 1);
            assertEq(OnReIds._offerConfigId(offer.tokenIn, offer.tokenOut, offer.instanceId), ids[i]);
            assertEq(uint8(offer.access), uint8(OfferAccess.Permissionless));
            assertEq(uint8(offer.execution), uint8(OfferExecution.Instant));
        }
        vm.prank(SAFE);
        assertEq(app.migrateOfferConfigs(ids), 0);
    }

    function test_UpgradeAllowsASecondOfferOnALivePair() public {
        if (!forked) {
            vm.skip(true);
            return;
        }
        _upgrade();
        OfferConfigView memory live = app.getOfferConfig(USDC_TO_ONYC);

        vm.prank(SAFE);
        bytes32 offerId = app.makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: live.tokenIn,
                tokenOut: live.tokenOut,
                instanceId: 100,
                access: OfferAccess.Permissioned,
                execution: OfferExecution.Instant,
                quoterId: live.quoterId,
                feeConfigId: live.feeConfigId,
                proceedsVaultId: live.proceedsVaultId,
                liquidityVaultId: live.liquidityVaultId
            })
        );

        assertEq(offerId, OnReIds._offerConfigId(live.tokenIn, live.tokenOut, 100));
        assertTrue(app.getOfferConfig(offerId).exists);
        assertTrue(app.getOfferConfig(USDC_TO_ONYC).exists);
    }

    function _upgrade() private {
        bytes32 upgraderRole = app.UPGRADER_ROLE();
        vm.prank(SAFE);
        app.grantRole(upgraderRole, address(this));

        IDiamondCut.FacetCut[] memory replaced = LibDiamondHelper.deployFacetsAndGetCuts(DIAMOND);
        bytes4[] memory stale = _staleSelectors(replaced);
        IDiamondCut.FacetCut[] memory cut = new IDiamondCut.FacetCut[](replaced.length + (stale.length == 0 ? 0 : 1));
        for (uint256 i; i < replaced.length; ++i) {
            cut[i] = replaced[i];
        }
        if (stale.length != 0) {
            cut[replaced.length] = IDiamondCut.FacetCut({
                facetAddress: address(0), action: IDiamondCut.FacetCutAction.Remove, functionSelectors: stale
            });
        }
        IDiamondCut(DIAMOND).diamondCut(cut, address(0), "");
    }

    /// @dev Application selectors on-chain that the new build no longer has, such as the old
    /// `makeOfferConfig`. The cut and loupe facets are core and are left alone.
    function _staleSelectors(IDiamondCut.FacetCut[] memory cut) private view returns (bytes4[] memory stale) {
        IDiamondLoupe.Facet[] memory facets = IDiamondLoupe(DIAMOND).facets();
        address cutFacet = IDiamondLoupe(DIAMOND).facetAddress(IDiamondCut.diamondCut.selector);
        address loupeFacet = IDiamondLoupe(DIAMOND).facetAddress(IDiamondLoupe.facets.selector);
        bytes4[] memory found = new bytes4[](256);
        uint256 count;
        for (uint256 i; i < facets.length; ++i) {
            if (facets[i].facetAddress == cutFacet || facets[i].facetAddress == loupeFacet) continue;
            for (uint256 j; j < facets[i].functionSelectors.length; ++j) {
                if (!_contains(cut, facets[i].functionSelectors[j])) found[count++] = facets[i].functionSelectors[j];
            }
        }
        stale = new bytes4[](count);
        for (uint256 i; i < count; ++i) {
            stale[i] = found[i];
        }
    }

    function _contains(IDiamondCut.FacetCut[] memory cut, bytes4 selector) private pure returns (bool) {
        for (uint256 i; i < cut.length; ++i) {
            for (uint256 j; j < cut[i].functionSelectors.length; ++j) {
                if (cut[i].functionSelectors[j] == selector) return true;
            }
        }
        return false;
    }

    function _observe(bytes32[] memory ids) private returns (Observation[] memory observations) {
        observations = new Observation[](ids.length);
        for (uint256 i; i < ids.length; ++i) {
            OfferConfigView memory offer = app.getOfferConfig(ids[i]);
            uint256 amount = 1_000 * 10 ** offer.tokenInDecimals;
            Observation memory observation = observations[i];
            (, observation.offerView) = DIAMOND.staticcall(abi.encodeCall(IDiamondProxy.getOfferConfig, (ids[i])));
            (, observation.preview) =
                DIAMOND.staticcall(abi.encodeCall(IDiamondProxy.previewExecution, (ids[i], amount)));
            for (uint256 slot = 1; slot <= 5; ++slot) {
                observation.referenceSlots[slot - 1] = vm.load(DIAMOND, bytes32(_offerSlot(ids[i]) + slot));
            }
            // Execute a real trade and roll it back, so each observation starts from the same state.
            uint256 snapshot = vm.snapshotState();
            _fund(offer.tokenIn, offer.tokenOut, amount);
            TakeOfferParams memory params;
            params.offerConfigId = ids[i];
            params.grossInputAmount = amount;
            params.deadline = uint64(block.timestamp + 1 hours);
            vm.prank(trader);
            (observation.tradeSucceeded, observation.tradeResult) =
                DIAMOND.call(abi.encodeCall(IDiamondProxy.takeOffer, (params)));
            vm.revertToState(snapshot);
        }
    }

    /// @dev The managed token is minted by the Diamond, its minter; the asset is dealt.
    function _fund(address tokenIn, address tokenOut, uint256 amount) private {
        if (_isManaged(tokenIn)) {
            vm.prank(DIAMOND);
            IManagedToken(tokenIn).mint(trader, amount);
        } else {
            assertTrue(_isManaged(tokenOut));
            deal(tokenIn, trader, amount);
        }
        vm.prank(trader);
        IERC20(tokenIn).approve(DIAMOND, amount);
    }

    function _isManaged(address token) private view returns (bool) {
        (bool ok, bytes memory data) = DIAMOND.staticcall(abi.encodeCall(IDiamondProxy.getManagedTokenConfig, (token)));
        return ok && data.length != 0;
    }

    function _assertSame(Observation[] memory expected, Observation[] memory actual, string memory stage) private pure {
        for (uint256 i; i < expected.length; ++i) {
            assertEq(actual[i].offerView, expected[i].offerView, string.concat("getOfferConfig changed ", stage));
            assertEq(actual[i].preview, expected[i].preview, string.concat("previewExecution changed ", stage));
            assertEq(
                actual[i].tradeSucceeded, expected[i].tradeSucceeded, string.concat("takeOffer outcome changed ", stage)
            );
            assertEq(actual[i].tradeResult, expected[i].tradeResult, string.concat("takeOffer result changed ", stage));
            for (uint256 slot; slot < 5; ++slot) {
                assertEq(
                    actual[i].referenceSlots[slot],
                    expected[i].referenceSlots[slot],
                    string.concat("storage changed ", stage)
                );
            }
        }
    }

    function _liveOffers() private pure returns (bytes32[] memory ids) {
        ids = new bytes32[](3);
        ids[0] = USDC_TO_ONYC;
        ids[1] = USDG_TO_ONYC;
        ids[2] = ONYC_TO_USDG;
    }

    function _offerSlot(bytes32 offerId) private pure returns (uint256) {
        return uint256(keccak256(abi.encode(offerId, OFFER_CONFIGS_SLOT)));
    }
}
