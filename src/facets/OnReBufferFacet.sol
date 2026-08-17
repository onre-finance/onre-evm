// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {BufferState} from "../types/OnReTypes.sol";
import {LibOnReBuffer} from "../libraries/LibOnReBuffer.sol";
import {IOnReBufferController} from "../IOnReBufferController.sol";

contract OnReBufferFacet is IOnReBufferController {
    function initializeBuffer(
        address onReToken,
        bytes32 reserveVaultId,
        bytes32 managementFeeVaultId,
        bytes32 performanceFeeVaultId
    ) external {
        LibOnReBuffer._initializeBuffer(onReToken, reserveVaultId, managementFeeVaultId, performanceFeeVaultId);
    }

    function setBufferGrossApr(address onReToken, uint64 grossApr) external {
        LibOnReBuffer._setBufferGrossApr(onReToken, grossApr);
    }

    function setBufferFeeConfig(
        address onReToken,
        uint16 managementFeeBasisPoints,
        uint16 performanceFeeBasisPoints,
        bool performanceFeeHighWatermarkEnabled
    ) external {
        LibOnReBuffer._setBufferFeeConfig(
            onReToken, managementFeeBasisPoints, performanceFeeBasisPoints, performanceFeeHighWatermarkEnabled
        );
    }

    function settleBuffer(address onReToken) external returns (uint256 bufferMintAmount) {
        bufferMintAmount = LibOnReBuffer._settleBuffer(onReToken);
    }

    function onBeforeSupplyChange(uint256 amount, bool isMint) external {
        LibOnReBuffer._onBeforeSupplyChange(amount, isMint);
    }

    function getBufferState(address onReToken) external view returns (BufferState memory) {
        return LibOnReBuffer._bufferState(onReToken);
    }
}
