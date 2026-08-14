// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReMarketStats} from "../libraries/LibOnReMarketStats.sol";
import {MarketStats} from "../types/OnReTypes.sol";

/// @notice Read-only market reporting kept separate from execution facets so its
///         calculation model can evolve without replacing settlement code.
contract OnReMarketStatsFacet {
    function marketStats(address onReToken) external view returns (MarketStats memory stats) {
        stats = LibOnReMarketStats._marketStats(onReToken);
    }
}
