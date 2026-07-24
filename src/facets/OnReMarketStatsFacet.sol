// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReMarketStats} from "../libraries/LibOnReMarketStats.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {IOnReMarketStats} from "../interfaces/IOnReMarketStats.sol";

/// @notice Read-only market reporting kept separate from execution facets so its
///         calculation model can evolve without replacing settlement code.
contract OnReMarketStatsFacet is IOnReMarketStats {
    function marketStats(address onReToken) external view override returns (OnReTypes.MarketStats memory stats) {
        return LibOnReMarketStats.marketStats(onReToken);
    }
}
