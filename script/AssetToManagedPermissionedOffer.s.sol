// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OfferSetup} from "./base/OfferSetup.sol";
import {OfferFlow, OfferDirection, QuoterKind} from "../src/types/OnReTypes.sol";

/// Uses named environment definitions matching this script's flow, direction, and quoter kind.
/// Use SetupOffers.s.sol to configure all offers and components.
contract AssetToManagedPermissionedOffer is OfferSetup {
    function run() external {
        _setupMatchingOffers(OfferFlow.Permissioned, OfferDirection.AssetToManaged, QuoterKind.Nav);
    }
}
