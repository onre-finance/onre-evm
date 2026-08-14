// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {InvalidAmountError, TokenNotRegisteredError} from "../types/OnReAppErrors.sol";
import {MarketStats, OnReTokenConfig, Pricer, PricingVector} from "../types/OnReTypes.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Canonical token-market metrics derived from supply balances and the USD Pricer.
library LibOnReMarketStats {
    function _marketStats(address onReToken) internal view returns (MarketStats memory stats) {
        OnReTokenConfig storage config = LibOnReStorage._appStorage().onReTokenConfigs[onReToken];
        if (config.decimals == 0) revert TokenNotRegisteredError(onReToken);

        uint256 circulatingSupply_ = _circulatingSupply(onReToken);
        bytes32 pricerId = OnReIds._usdPricerId(onReToken);
        Pricer storage pricer = LibOnReValidation._requireExecutablePricer(pricerId);
        uint8 activeVectorIndex = LibOnRePricer._activePricingVectorIndex(pricerId, pricer);
        PricingVector storage activeVector = pricer.vectors[activeVectorIndex];

        uint256 apy = OnReMath._calculateApyFromApr(activeVector.apr);
        uint256 nav = LibOnRePricer._calculatePricingVectorPriceAt(activeVector, block.timestamp);
        int256 navAdjustment = _calculateNavAdjustment(pricer, activeVector, activeVectorIndex);
        uint256 tvl = OnReMath._calculateTvl(circulatingSupply_, nav, LibOnRePricer.PRICE_SCALE);

        stats = MarketStats({
            apy: apy,
            circulatingSupply: circulatingSupply_,
            nav: nav,
            navAdjustment: navAdjustment,
            tvl: tvl,
            lastUpdatedAt: uint64(block.timestamp),
            lastUpdatedBlock: uint64(block.number)
        });
    }

    function _circulatingSupply(address onReToken) internal view returns (uint256) {
        uint256 supply = IERC20Metadata(onReToken).totalSupply();
        address inventorySource = LibOnReStorage._appStorage().onReTokenConfigs[onReToken].inventorySource;
        uint256 excludedSupply = IERC20Metadata(onReToken).balanceOf(inventorySource);
        address[] storage excludedAccounts = LibOnReStorage._appStorage().excludedSupplyAccounts[onReToken];
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

    function _currentTvl(address onReToken) internal view returns (uint256) {
        uint256 nav = LibOnRePricer._currentPrice(OnReIds._usdPricerId(onReToken));
        return OnReMath._calculateTvl(_circulatingSupply(onReToken), nav, LibOnRePricer.PRICE_SCALE);
    }

    function _calculateNavAdjustment(Pricer storage pricer, PricingVector storage activeVector, uint8 activeVectorIndex)
        private
        view
        returns (int256)
    {
        uint256 currentPrice = LibOnRePricer._calculatePricingVectorPriceAt(activeVector, activeVector.startTime);
        if (activeVectorIndex == 0) return _toInt256(currentPrice);

        uint256 previousPrice =
            LibOnRePricer._calculatePricingVectorPriceAt(pricer.vectors[activeVectorIndex - 1], activeVector.startTime);
        if (currentPrice >= previousPrice) return _toInt256(currentPrice - previousPrice);
        return -_toInt256(previousPrice - currentPrice);
    }

    function _toInt256(uint256 value) private pure returns (int256) {
        if (value > uint256(type(int256).max)) revert InvalidAmountError();
        // forge-lint: disable-next-line(unsafe-typecast)
        return int256(value);
    }
}
