// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";

interface IOnReOffer {
    function createFeeConfig(uint64 feeConfigInstanceId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        external
        returns (bytes32 feeConfigId);
    function updateFeeConfig(bytes32 feeConfigId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        external;
    function setFeeConfigEnabled(bytes32 feeConfigId, bool enabled) external;

    function makeOfferConfig(OnReTypes.MakeOfferConfigParams calldata params) external returns (bytes32 offerConfigId);
    function updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) external;
    function setOfferConfigDisabled(bytes32 offerConfigId, bool disabled) external;
    function takeOffer(OnReTypes.TakeOfferParams calldata params) external returns (uint256 amountOut);
    function previewExecution(bytes32 offerConfigId, uint256 grossInputAmount)
        external
        view
        returns (OnReTypes.ExecutionAccounting memory accounting);
}
