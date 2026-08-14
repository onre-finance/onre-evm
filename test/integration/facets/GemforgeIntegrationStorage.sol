// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

library GemforgeIntegrationStorage {
    bytes32 internal constant STORAGE_LOCATION = 0x1070114fa4cecf2df49d633c571f66e4bdc3523537fe4b7cb4eb06ca13b9a66f;

    struct Layout {
        uint256 value;
    }

    function _store() internal pure returns (Layout storage state) {
        bytes32 location = STORAGE_LOCATION;
        // solhint-disable-next-line no-inline-assembly
        assembly {
            state.slot := location
        }
    }
}
