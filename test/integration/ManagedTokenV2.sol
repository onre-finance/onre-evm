// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ManagedToken} from "../../src/ManagedToken.sol";

contract ManagedTokenV2 is ManagedToken {
    function version() external pure returns (uint256) {
        return 2;
    }
}
