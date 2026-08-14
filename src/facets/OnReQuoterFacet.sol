// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReQuoter} from "../libraries/LibOnReQuoter.sol";
import {PropRfqQuoterConfig, QuoterKind} from "../types/OnReTypes.sol";

contract OnReQuoterFacet {
    function createQuoter(QuoterKind kind, uint64 quoterInstanceId) external returns (bytes32 quoterId) {
        quoterId = LibOnReQuoter._createQuoter(kind, quoterInstanceId);
    }

    function configurePropRfqQuoter(
        bytes32 quoterId,
        address assetToken,
        address onReToken,
        PropRfqQuoterConfig calldata config
    ) external {
        LibOnReQuoter._configurePropRfqQuoter(quoterId, assetToken, onReToken, config);
    }

    function setQuoterEnabled(bytes32 quoterId, bool enabled) external {
        LibOnReQuoter._setQuoterEnabled(quoterId, enabled);
    }
}
