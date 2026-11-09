// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {TransientSlot} from "@openzeppelin/contracts/utils/TransientSlot.sol";

/// @notice Shared lock for MM swaps and the standard MM vault deposit/withdraw paths.
library LibOnReMarketMakerGuard {
    using TransientSlot for *;

    error MarketMakerReentrantCall();

    // ERC-7201-derived slot for onre.storage.MarketMakerGuard, used in transient storage.
    bytes32 private constant LOCK_SLOT = 0x545ff798edc2e9ecd482d3e83b386e5237400681e78aa448f69f34b930fbc800;

    function _enter() internal {
        if (_entered()) revert MarketMakerReentrantCall();
        LOCK_SLOT.asBoolean().tstore(true);
    }

    function _exit() internal {
        LOCK_SLOT.asBoolean().tstore(false);
    }

    function _entered() internal view returns (bool) {
        return LOCK_SLOT.asBoolean().tload();
    }
}
