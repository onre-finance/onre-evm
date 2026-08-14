// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ExecutionAccounting, MakeOfferConfigParams, TakeOfferParams} from "../types/OnReTypes.sol";
import {LibOnReFeeConfig} from "../libraries/LibOnReFeeConfig.sol";
import {LibOnReOffer} from "../libraries/LibOnReOffer.sol";
import {LibOnReOfferConfig} from "../libraries/LibOnReOfferConfig.sol";

contract OnReOfferFacet {
    function createFeeConfig(
        uint64 feeConfigInstanceId,
        uint16 basisPoints,
        uint256 minimumFeeAmount,
        bytes32 feeVaultId
    ) external returns (bytes32 feeConfigId) {
        feeConfigId =
            LibOnReFeeConfig._createFeeConfig(feeConfigInstanceId, basisPoints, minimumFeeAmount, feeVaultId);
    }

    function updateFeeConfig(bytes32 feeConfigId, uint16 basisPoints, uint256 minimumFeeAmount, bytes32 feeVaultId)
        external
    {
        LibOnReFeeConfig._updateFeeConfig(feeConfigId, basisPoints, minimumFeeAmount, feeVaultId);
    }

    function setFeeConfigEnabled(bytes32 feeConfigId, bool enabled) external {
        LibOnReFeeConfig._setFeeConfigEnabled(feeConfigId, enabled);
    }

    function makeOfferConfig(MakeOfferConfigParams calldata params) external returns (bytes32 offerConfigId) {
        offerConfigId = LibOnReOfferConfig._makeOfferConfig(params);
    }

    function updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) external {
        LibOnReOfferConfig._updateOfferConfigReferences(
            offerConfigId, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
    }

    function setOfferConfigEnabled(bytes32 offerConfigId, bool enabled) external {
        LibOnReOfferConfig._setOfferConfigEnabled(offerConfigId, enabled);
    }

    function takeOffer(TakeOfferParams calldata params) external returns (uint256 amountOut) {
        amountOut = LibOnReOffer._takeOffer(params);
    }

    function previewExecution(bytes32 offerConfigId, uint256 grossInputAmount)
        external
        view
        returns (ExecutionAccounting memory accounting)
    {
        accounting = LibOnReOffer._previewExecution(offerConfigId, grossInputAmount);
    }
}
