// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {GemforgeIntegrationStorage} from "./GemforgeIntegrationStorage.sol";

contract GemforgeIntegrationFacetV2 {
    function setIntegrationValue(uint256 value) external {
        GemforgeIntegrationStorage._store().value = value;
    }

    function integrationValue() external view returns (uint256) {
        return GemforgeIntegrationStorage._store().value;
    }

    function integrationVersion() external pure returns (uint256) {
        return 2;
    }

    function legacyOne() external pure returns (uint256) {
        return 1;
    }

    function legacyTwo() external pure returns (uint256) {
        return 2;
    }

    function addedInV2() external pure returns (uint256) {
        return 22;
    }
}
