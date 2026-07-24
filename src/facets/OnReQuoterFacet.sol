// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReQuoter} from "../libraries/LibOnReQuoter.sol";
import {OnReTypes} from "../types/OnReTypes.sol";

contract OnReQuoterFacet {
    function createQuoter(OnReTypes.QuoterKind kind, uint64 quoterInstanceId) external returns (bytes32 quoterId) {
        return LibOnReQuoter.createQuoter(kind, quoterInstanceId);
    }

    function setQuoterDisabled(bytes32 quoterId, bool disabled) external {
        LibOnReQuoter.setQuoterDisabled(quoterId, disabled);
    }

    function quote(bytes32 offerConfigId, uint256 netInputAmount)
        external
        view
        returns (OnReTypes.QuoteResult memory result)
    {
        return LibOnReQuoter.quote(offerConfigId, netInputAmount);
    }
}
