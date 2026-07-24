// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReQuoter} from "../libraries/LibOnReQuoter.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {IOnReQuoter} from "../interfaces/IOnReQuoter.sol";

contract OnReQuoterFacet is IOnReQuoter {
    function createQuoter(OnReTypes.QuoterKind kind, uint64 quoterInstanceId)
        external
        override
        returns (bytes32 quoterId)
    {
        return LibOnReQuoter.createQuoter(kind, quoterInstanceId);
    }

    function setQuoterDisabled(bytes32 quoterId, bool disabled) external override {
        LibOnReQuoter.setQuoterDisabled(quoterId, disabled);
    }

    function quote(bytes32 offerConfigId, uint256 netInputAmount)
        external
        view
        override
        returns (OnReTypes.QuoteResult memory result)
    {
        return LibOnReQuoter.quote(offerConfigId, netInputAmount);
    }
}
