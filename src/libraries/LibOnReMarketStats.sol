// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Canonical token-market metrics derived from supply balances and the USD Pricer.
library LibOnReMarketStats {
    function marketStats(address onReToken) internal view returns (OnReTypes.MarketStats memory stats) {
        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.decimals == 0) revert IOnReAppErrors.TokenNotRegisteredError(onReToken);

        uint256 circulatingSupply_ = circulatingSupply(onReToken);
        bytes32 pricerId = OnReIds.usdPricerId(onReToken);
        OnReTypes.Pricer storage pricer = LibOnReValidation.requireExecutablePricer(pricerId);
        uint8 activeVectorIndex = LibOnRePricer.activePricingVectorIndex(pricerId, pricer);
        OnReTypes.PricingVector storage activeVector = pricer.vectors[activeVectorIndex];

        uint256 apy = OnReMath.calculateApyFromApr(activeVector.apr);
        uint256 nav = LibOnRePricer.calculatePricingVectorPriceAt(activeVector, block.timestamp);
        int256 navAdjustment = _calculateNavAdjustment(pricer, activeVector, activeVectorIndex);
        uint256 tvl = OnReMath.calculateTvl(circulatingSupply_, nav, LibOnRePricer.PRICE_SCALE);

        return OnReTypes.MarketStats({
            apy: apy,
            circulatingSupply: circulatingSupply_,
            nav: nav,
            navAdjustment: navAdjustment,
            tvl: tvl,
            lastUpdatedAt: uint64(block.timestamp),
            lastUpdatedBlock: uint64(block.number)
        });
    }

    function circulatingSupply(address onReToken) internal view returns (uint256) {
        uint256 supply = IERC20Metadata(onReToken).totalSupply();
        address inventorySource = LibOnReStorage.appStorage().onReTokenConfigs[onReToken].inventorySource;
        uint256 excludedSupply = IERC20Metadata(onReToken).balanceOf(inventorySource);
        address[] storage excludedAccounts = LibOnReStorage.appStorage().excludedSupplyAccounts[onReToken];
        uint256 excludedAccountsLength = excludedAccounts.length;
        for (uint256 i; i < excludedAccountsLength;) {
            address account = excludedAccounts[i];
            if (account != inventorySource) {
                excludedSupply += IERC20Metadata(onReToken).balanceOf(account);
            }
            unchecked {
                ++i;
            }
        }
        return excludedSupply >= supply ? 0 : supply - excludedSupply;
    }

    function currentTvl(address onReToken) internal view returns (uint256) {
        uint256 nav = LibOnRePricer.currentPrice(OnReIds.usdPricerId(onReToken));
        return OnReMath.calculateTvl(circulatingSupply(onReToken), nav, LibOnRePricer.PRICE_SCALE);
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
