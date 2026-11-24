// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OfferSetup} from "./base/OfferSetup.sol";
import {OfferAccess, OfferDirection, OfferExecution, QuoterKind} from "../src/types/OnReTypes.sol";

/// Uses named environment definitions matching this script's access, execution, direction, and quoter kind.
/// Use SetupOffers.s.sol to configure all offers and components.
contract AssetToManagedPermissionedOffer is OfferSetup {
    function run() external {
        _setupMatchingOffers(
            OfferAccess.Permissioned, OfferExecution.Instant, OfferDirection.AssetToManaged, QuoterKind.Nav
        );
    }
}
