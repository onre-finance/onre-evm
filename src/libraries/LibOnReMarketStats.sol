// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Read-only market reporting derived from the canonical USD Pricer.
library LibOnReMarketStats {
    function marketStats(address onReToken) internal view returns (OnReTypes.MarketStats memory stats) {
        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.decimals == 0) revert IOnReAppErrors.TokenNotRegisteredError(onReToken);

        uint256 circulatingSupply = LibOnRePricer.circulatingSupply(onReToken);
        bytes32 pricerId = config.mainPricerId;
        uint256 apy = 0;
        uint256 nav = 0;
        int256 navAdjustment = 0;

        if (pricerId != bytes32(0)) {
            OnReTypes.Pricer storage pricer = LibOnReValidation.requireExecutablePricer(pricerId);
            if (pricer.onReToken != onReToken) revert IOnReAppErrors.InvalidTokenError();
            uint8 activeVectorIndex = LibOnRePricer.activePricingVectorIndex(pricerId, pricer);
            OnReTypes.PricingVector storage activeVector = pricer.vectors[activeVectorIndex];
            // forge-lint: disable-next-line(block-timestamp)
            if (activeVector.baseTime > block.timestamp) {
                revert IOnReAppErrors.NoActiveVectorError(pricerId);
            }

            apy = OnReMath.calculateApyFromApr(activeVector.apr);
            nav = LibOnRePricer.calculatePricingVectorPriceAt(activeVector, block.timestamp);
            navAdjustment = _calculateNavAdjustment(pricer, activeVector, activeVectorIndex);
        }

        uint256 tvl = 0;
        if (nav > 0) {
            tvl = OnReMath.calculateTvl(circulatingSupply, nav, LibOnRePricer.PRICE_SCALE);
        }

        return OnReTypes.MarketStats({
            apy: apy,
            circulatingSupply: circulatingSupply,
            nav: nav,
            navAdjustment: navAdjustment,
            tvl: tvl,
            lastUpdatedAt: uint64(block.timestamp),
            lastUpdatedBlock: uint64(block.number)
        });
    }

    function _calculateNavAdjustment(
        OnReTypes.Pricer storage pricer,
        OnReTypes.PricingVector storage activeVector,
        uint8 activeVectorIndex
    ) private view returns (int256) {
        uint256 currentPrice = LibOnRePricer.calculatePricingVectorPriceAt(activeVector, activeVector.startTime);
        if (activeVectorIndex == 0) return _toInt256(currentPrice);

        uint256 previousPrice =
            LibOnRePricer.calculatePricingVectorPriceAt(pricer.vectors[activeVectorIndex - 1], activeVector.startTime);
        if (currentPrice >= previousPrice) return _toInt256(currentPrice - previousPrice);
        return -_toInt256(previousPrice - currentPrice);
    }

    function _toInt256(uint256 value) private pure returns (int256) {
        if (value > uint256(type(int256).max)) revert IOnReAppErrors.InvalidAmountError();
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(value);
    }
}
