// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";

interface IOnReQuoter {
    function createQuoter(OnReTypes.QuoterKind kind, uint64 quoterInstanceId) external returns (bytes32 quoterId);
    function setQuoterDisabled(bytes32 quoterId, bool disabled) external;
    function quote(bytes32 offerConfigId, uint256 netInputAmount)
        external
        view
        returns (OnReTypes.QuoteResult memory result);
}
