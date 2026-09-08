// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {BufferState} from "../types/OnReTypes.sol";
import {LibOnReBuffer} from "../libraries/LibOnReBuffer.sol";
import {IBufferController} from "../IBufferController.sol";

contract OnReBufferFacet is IBufferController {
    function initializeBuffer(address managedToken) external {
        LibOnReBuffer._initializeBuffer(managedToken);
    }

    function setBufferGrossApr(address managedToken, uint64 grossApr) external {
        LibOnReBuffer._setBufferGrossApr(managedToken, grossApr);
    }

    function setBufferFeeConfig(
        address managedToken,
        uint16 managementFeeBasisPoints,
        uint16 performanceFeeBasisPoints,
        bool performanceFeeHighWatermarkEnabled
    ) external {
        LibOnReBuffer._setBufferFeeConfig(
            managedToken, managementFeeBasisPoints, performanceFeeBasisPoints, performanceFeeHighWatermarkEnabled
        );
    }

    function settleBuffer(address managedToken) external returns (uint256 bufferMintAmount) {
        bufferMintAmount = LibOnReBuffer._settleBuffer(managedToken);
    }

    /// @notice Burns reserve tokens to offset a USD asset reduction at the current quoted NAV.
    /// @param assetAdjustmentAmount USD amount scaled to the managed token's decimals, like MarketStats.tvl.
    /// @return burnAmount Amount burned in managed-token base units.
    function burnForNavIncrease(address managedToken, uint256 assetAdjustmentAmount)
        external
        returns (uint256 burnAmount)
    {
        burnAmount = LibOnReBuffer._burnForNavIncrease(managedToken, assetAdjustmentAmount);
    }

    function onBeforeSupplyChange(uint256 amount, bool isMint) external {
        LibOnReBuffer._onBeforeSupplyChange(amount, isMint);
    }

    function getBufferState(address managedToken) external view returns (BufferState memory) {
        return LibOnReBuffer._bufferState(managedToken);
    }
}
