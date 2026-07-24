// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReFeeConfig} from "../libraries/LibOnReFeeConfig.sol";
import {LibOnReOffer} from "../libraries/LibOnReOffer.sol";
import {LibOnReOfferConfig} from "../libraries/LibOnReOfferConfig.sol";
import {IOnReOffer} from "../interfaces/IOnReOffer.sol";

contract OnReOfferFacet is IOnReOffer {
    function createFeeConfig(uint64 feeConfigInstanceId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        external
        override
        returns (bytes32 feeConfigId)
    {
        return LibOnReFeeConfig.createFeeConfig(feeConfigInstanceId, basisPoints, minimumAmount, feeVaultId);
    }

    function updateFeeConfig(bytes32 feeConfigId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        external
        override
    {
        LibOnReFeeConfig.updateFeeConfig(feeConfigId, basisPoints, minimumAmount, feeVaultId);
    }

    function setFeeConfigEnabled(bytes32 feeConfigId, bool enabled) external override {
        LibOnReFeeConfig.setFeeConfigEnabled(feeConfigId, enabled);
    }

    function makeOfferConfig(OnReTypes.MakeOfferConfigParams calldata params)
        external
        override
        returns (bytes32 offerConfigId)
    {
        return LibOnReOfferConfig.makeOfferConfig(params);
    }

    function updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) external override {
        LibOnReOfferConfig.updateOfferConfigReferences(
            offerConfigId, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
    }

    function setOfferConfigDisabled(bytes32 offerConfigId, bool disabled) external override {
        LibOnReOfferConfig.setOfferConfigDisabled(offerConfigId, disabled);
    }

    function takeOffer(OnReTypes.TakeOfferParams calldata params) external override returns (uint256 amountOut) {
        return LibOnReOffer.takeOffer(params);
    }

    function previewExecution(bytes32 offerConfigId, uint256 grossInputAmount)
        external
        view
        override
        returns (OnReTypes.ExecutionAccounting memory accounting)
    {
        return LibOnReOffer.previewExecution(offerConfigId, grossInputAmount);
    }
}
