// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReOffer} from "../libraries/LibOnReOffer.sol";

contract OnReOfferFacet {
    function createFeeConfig(uint64 feeConfigInstanceId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        external
        returns (bytes32 feeConfigId)
    {
        return LibOnReOffer.createFeeConfig(feeConfigInstanceId, basisPoints, minimumAmount, feeVaultId);
    }

    function updateFeeConfig(bytes32 feeConfigId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId)
        external
    {
        LibOnReOffer.updateFeeConfig(feeConfigId, basisPoints, minimumAmount, feeVaultId);
    }

    function setFeeConfigEnabled(bytes32 feeConfigId, bool enabled) external {
        LibOnReOffer.setFeeConfigEnabled(feeConfigId, enabled);
    }

    function makeOfferConfig(OnReTypes.MakeOfferConfigParams calldata params) external returns (bytes32 offerConfigId) {
        return LibOnReOffer.makeOfferConfig(params);
    }

    function updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) external {
        LibOnReOffer.updateOfferConfigReferences(
            offerConfigId, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
    }

    function setOfferConfigDisabled(bytes32 offerConfigId, bool disabled) external {
        LibOnReOffer.setOfferConfigDisabled(offerConfigId, disabled);
    }

    function takeOffer(OnReTypes.TakeOfferParams calldata params) external returns (uint256 amountOut) {
        return LibOnReOffer.takeOffer(params);
    }

    function previewExecution(bytes32 offerConfigId, uint256 grossInputAmount)
        external
        view
        returns (OnReTypes.ExecutionAccounting memory accounting)
    {
        return LibOnReOffer.previewExecution(offerConfigId, grossInputAmount);
    }
}
