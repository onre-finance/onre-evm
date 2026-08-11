// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {GemforgeIntegrationStorage} from "./GemforgeIntegrationStorage.sol";

contract GemforgeIntegrationFacetV3 {
    function setIntegrationValue(uint256 value) external {
        GemforgeIntegrationStorage.store().value = value;
    }

    function integrationValue() external view returns (uint256) {
        return GemforgeIntegrationStorage.store().value;
    }

    function integrationVersion() external pure returns (uint256) {
        return 3;
    }

    function addedInV2() external pure returns (uint256) {
        return 22;
    }
}
