// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReQuoter} from "../libraries/LibOnReQuoter.sol";
import {QuoteResult, QuoterKind} from "../types/OnReTypes.sol";

contract OnReQuoterFacet {
    function createQuoter(QuoterKind kind, uint64 quoterInstanceId) external returns (bytes32 quoterId) {
        return LibOnReQuoter.createQuoter(kind, quoterInstanceId);
    }

    function setQuoterEnabled(bytes32 quoterId, bool enabled) external {
        LibOnReQuoter.setQuoterEnabled(quoterId, enabled);
    }

    function quote(bytes32 offerConfigId, uint256 netInputAmount) external view returns (QuoteResult memory result) {
        return LibOnReQuoter.quote(offerConfigId, netInputAmount);
    }
}
