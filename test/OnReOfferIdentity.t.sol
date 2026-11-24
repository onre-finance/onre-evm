// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import "../src/types/OnReAppErrors.sol";
import "../src/types/OnReTypes.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import "./helpers/OnReAppTestBase.sol";

/// @notice Offers are identified by their directed pair and a boss-chosen instance ID.
contract OnReOfferIdentityTest is OnReAppTestBase {
    function test_OfferIdIsDerivedFromPairAndInstanceId() public view {
        assertEq(
            OnReIds._offerConfigId(address(usd), address(managedToken), 7),
            keccak256(abi.encode(keccak256("onre.offer_config"), address(usd), address(managedToken), uint64(7)))
        );
        // The direction is part of the identity.
        assertNotEq(
            OnReIds._offerConfigId(address(usd), address(managedToken), 7),
            OnReIds._offerConfigId(address(managedToken), address(usd), 7)
        );
    }

    function test_InstanceIdIsStoredAndExposedByTheV2Getter() public {
        bytes32 offerId = _makeInstance(41);

        assertEq(offerId, OnReIds._offerConfigId(address(usd), address(managedToken), 41));
        OfferConfig memory offer = app.getOfferConfigV2(offerId);
        assertEq(offer.instanceId, 41);
        assertEq(offer.tokenIn, address(usd));
        assertEq(offer.tokenOut, address(managedToken));
        assertTrue(offer.exists);
        // Offers created through the pre-instance path sit at the instance equal to their flow ordinal.
        assertEq(app.getOfferConfigV2(permissionlessOfferId).instanceId, uint64(uint8(OfferFlow.Permissionless)));
    }

    function test_SeveralOffersOfOnePairCanCoexist() public {
        bytes32 first = _makeInstance(10);
        bytes32 second = _makeInstance(11);

        assertNotEq(first, second);
        _fundAndApproveUsd(user, 200e6);
        vm.startPrank(user);
        assertEq(app.takeOffer(_takeOfferParams(first, 100e6)), 99e9);
        assertEq(app.takeOffer(_takeOfferParams(second, 100e6)), 99e9);
        vm.stopPrank();
    }

    function test_RevertWhen_InstanceIdIsAlreadyUsedForThePair() public {
        bytes32 offerId = _makeInstance(10);

        vm.expectRevert(abi.encodeWithSelector(OfferConfigAlreadyExistsError.selector, offerId));
        _makeInstance(10);
    }

    function test_V2GetterRequiresAnExistingOffer() public {
        bytes32 missing = keccak256("missing offer");

        vm.expectRevert(abi.encodeWithSelector(OfferConfigNotFoundError.selector, missing));
        app.getOfferConfigV2(missing);
    }

    function _makeInstance(uint64 instanceId) private returns (bytes32) {
        return app.makeOfferConfig(
            MakeOfferConfigParams({
                tokenIn: address(usd),
                tokenOut: address(managedToken),
                instanceId: instanceId,
                flow: OfferFlow.Permissionless,
                quoterId: navPermissionlessQuoterId,
                feeConfigId: feeConfigId,
                proceedsVaultId: proceedsVaultId,
                liquidityVaultId: bytes32(0)
            })
        );
    }
}
