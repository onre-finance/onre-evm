// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IOnReAppErrors} from "./IOnReAppErrors.sol";
import {IOnReAppEvents} from "./IOnReAppEvents.sol";
import {IOnReAccessControl} from "./IOnReAccessControl.sol";
import {IOnReConfig} from "./IOnReConfig.sol";
import {IOnRePricer} from "./IOnRePricer.sol";
import {IOnReQuoter} from "./IOnReQuoter.sol";
import {IOnReOffer} from "./IOnReOffer.sol";
import {IOnReFulfillment} from "./IOnReFulfillment.sol";
import {IOnReConfigurableVault} from "./IOnReConfigurableVault.sol";
import {IOnReView} from "./IOnReView.sol";
import {IOnReMarketStats} from "./IOnReMarketStats.sol";

/// @notice Aggregate client interface for the application selectors installed on the Diamond.
/// @dev Facets implement the domain interfaces directly; this interface declares no duplicate functions.
interface IOnReApp is
    IOnReAppEvents,
    IOnReAppErrors,
    IOnReAccessControl,
    IOnReConfig,
    IOnRePricer,
    IOnReQuoter,
    IOnReOffer,
    IOnReFulfillment,
    IOnReConfigurableVault,
    IOnReView,
    IOnReMarketStats
{}
