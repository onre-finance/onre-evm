// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

library GemforgeIntegrationStorage {
    bytes32 internal constant STORAGE_LOCATION = 0x1070114fa4cecf2df49d633c571f66e4bdc3523537fe4b7cb4eb06ca13b9a66f;

    struct Layout {
        uint256 value;
    }

    function store() internal pure returns (Layout storage state) {
        assembly {
            state.slot := STORAGE_LOCATION
        }
    }
}
