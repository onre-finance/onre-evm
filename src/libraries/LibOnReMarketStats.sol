// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20Metadata} from "@openzeppelin/contracts/token/ERC20/extensions/IERC20Metadata.sol";
import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {InvalidAmountError, TokenNotRegisteredError} from "../types/OnReAppErrors.sol";
import {MarketStats, ManagedTokenConfig, Pricer, PricingVector} from "../types/OnReTypes.sol";
import {LibOnRePricer} from "./LibOnRePricer.sol";
import {LibOnReValidation} from "./LibOnReValidation.sol";
import {OnReIds} from "./OnReIds.sol";
import {OnReMath} from "./OnReMath.sol";

/// @notice Canonical token-market metrics derived from supply balances and the USD Pricer.
library LibOnReMarketStats {
    function _marketStats(address managedToken) internal view returns (MarketStats memory stats) {
        ManagedTokenConfig storage config = LibOnReStorage._appStorage().managedTokenConfigs[managedToken];
        if (!config.exists) revert TokenNotRegisteredError(managedToken);

        uint256 circulatingSupply_ = _circulatingSupply(managedToken);
        bytes32 pricerId = OnReIds._usdPricerId(managedToken);
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

    function _circulatingSupply(address managedToken) internal view returns (uint256) {
        uint256 supply = IERC20Metadata(managedToken).totalSupply();
        uint256 excludedSupply;
        address[] storage excludedAccounts = LibOnReStorage._appStorage().excludedSupplyAccounts[managedToken];
        uint256 excludedAccountsLength = excludedAccounts.length;
        for (uint256 i; i < excludedAccountsLength;) {
            excludedSupply += IERC20Metadata(managedToken).balanceOf(excludedAccounts[i]);
            unchecked {
                ++i;
            }
        }
        return excludedSupply >= supply ? 0 : supply - excludedSupply;
    }

    function _currentTvl(address managedToken) internal view returns (uint256) {
        uint256 nav = LibOnRePricer._currentPrice(OnReIds._usdPricerId(managedToken));
        return OnReMath._calculateTvl(_circulatingSupply(managedToken), nav, LibOnRePricer.PRICE_SCALE);
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
