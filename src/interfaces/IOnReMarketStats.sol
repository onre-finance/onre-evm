// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";

interface IOnReMarketStats {
    function marketStats(address onReToken) external view returns (OnReTypes.MarketStats memory stats);
}
