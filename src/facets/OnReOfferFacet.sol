// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ExecutionAccounting, MakeOfferConfigParams, TakeOfferParams} from "../types/OnReTypes.sol";
import {LibOnReFeeConfig} from "../libraries/LibOnReFeeConfig.sol";
import {LibOnReOffer} from "../libraries/LibOnReOffer.sol";
import {LibOnReOfferConfig} from "../libraries/LibOnReOfferConfig.sol";

contract OnReOfferFacet {
    function createFeeConfig(uint64 feeConfigInstanceId, uint16 basisPoints, bytes32 feeVaultId)
        external
        returns (bytes32 feeConfigId)
    {
        return LibOnReFeeConfig.createFeeConfig(feeConfigInstanceId, basisPoints, feeVaultId);
    }

    function updateFeeConfig(bytes32 feeConfigId, uint16 basisPoints, bytes32 feeVaultId) external {
        LibOnReFeeConfig.updateFeeConfig(feeConfigId, basisPoints, feeVaultId);
    }

    function setFeeConfigEnabled(bytes32 feeConfigId, bool enabled) external {
        LibOnReFeeConfig.setFeeConfigEnabled(feeConfigId, enabled);
    }

    function makeOfferConfig(MakeOfferConfigParams calldata params) external returns (bytes32 offerConfigId) {
        return LibOnReOfferConfig.makeOfferConfig(params);
    }

    function updateOfferConfigReferences(
        bytes32 offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    ) external {
        LibOnReOfferConfig.updateOfferConfigReferences(
            offerConfigId, quoterId, feeConfigId, proceedsVaultId, liquidityVaultId
        );
    }

    function setOfferConfigDisabled(bytes32 offerConfigId, bool disabled) external {
        LibOnReOfferConfig.setOfferConfigDisabled(offerConfigId, disabled);
    }

    function takeOffer(TakeOfferParams calldata params) external returns (uint256 amountOut) {
        return LibOnReOffer.takeOffer(params);
    }

    function previewExecution(bytes32 offerConfigId, uint256 grossInputAmount)
        external
        view
        returns (ExecutionAccounting memory accounting)
    {
        return LibOnReOffer.previewExecution(offerConfigId, grossInputAmount);
    }
}
