// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReQuoter} from "../libraries/LibOnReQuoter.sol";
import {PropAmmConfig, QuoterKind} from "../types/OnReTypes.sol";

contract OnReQuoterFacet {
    function createQuoter(QuoterKind kind, uint64 quoterInstanceId) external returns (bytes32 quoterId) {
        quoterId = LibOnReQuoter._createQuoter(kind, quoterInstanceId);
    }

    function configurePropAmm(bytes32 quoterId, address assetToken, address managedToken, PropAmmConfig calldata config)
        external
    {
        LibOnReQuoter._configurePropAmm(quoterId, assetToken, managedToken, config);
    }

    function setQuoterEnabled(bytes32 quoterId, bool enabled) external {
        LibOnReQuoter._setQuoterEnabled(quoterId, enabled);
    }
}
