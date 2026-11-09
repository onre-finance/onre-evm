// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReMarketMaker} from "../libraries/LibOnReMarketMaker.sol";
import {MarketMakerConfig, MarketMakerSwapParams} from "../types/OnReTypes.sol";

/// @notice Executor-authorized Uniswap v4 swaps against separately accounted Diamond inventory.
contract OnReMarketMakerFacet {
    function configureMarketMaker(MarketMakerConfig calldata config) external {
        LibOnReMarketMaker._configure(config);
    }

    function setMarketMakerExecutor(address executor) external {
        LibOnReMarketMaker._setExecutor(executor);
    }

    function setMarketMakerKillSwitch(bool killed) external {
        LibOnReMarketMaker._setKillSwitch(killed);
    }

    function swapUniswapV4(MarketMakerSwapParams calldata params)
        external
        returns (uint256 actualAmountIn, uint256 amountOut)
    {
        return LibOnReMarketMaker._swap(params);
    }

    /// @notice PoolManager callback. Only accepted once during an executor-initiated swap.
    function unlockCallback(bytes calldata data) external returns (bytes memory) {
        return LibOnReMarketMaker._unlockCallback(data);
    }

    function marketMakerState() external view returns (MarketMakerConfig memory config, address executor, bool killed) {
        return LibOnReMarketMaker._state();
    }
}
