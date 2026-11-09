// SPDX-License-Identifier: MIT
pragma solidity 0.8.26;

import {PoolManager} from "@uniswap/v4-core/src/PoolManager.sol";
import {IPoolManager} from "@uniswap/v4-core/src/interfaces/IPoolManager.sol";
import {IHooks} from "@uniswap/v4-core/src/interfaces/IHooks.sol";
import {Currency} from "@uniswap/v4-core/src/types/Currency.sol";
import {PoolKey} from "@uniswap/v4-core/src/types/PoolKey.sol";
import {StateLibrary} from "@uniswap/v4-core/src/libraries/StateLibrary.sol";

// A separate compilation root for the canonical 0.8.26 PoolManager artifact.
// Its name also matches the OnReMarketMakerTest filter used for focused tests.
// OnRe's 0.8.35 integration suite deploys the original PoolManager artifact,
// not this derived fixture, so the upstream implementation stays unmodified.
contract OnReMarketMakerTestPoolManagerFixture {
    using StateLibrary for IPoolManager;

    function test_CanonicalManagerInitializesHooklessPool() public {
        IPoolManager manager = IPoolManager(address(new PoolManager(address(this))));
        PoolKey memory key = PoolKey(Currency.wrap(address(1)), Currency.wrap(address(2)), 500, 10, IHooks(address(0)));
        manager.initialize(key, uint160(1 << 96));
        (uint160 price,,, uint24 fee) = manager.getSlot0(key.toId());
        require(price == uint160(1 << 96) && fee == 500, "Unexpected canonical pool state");
    }
}
