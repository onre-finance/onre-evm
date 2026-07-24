// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {LibOnReStorage} from "../diamond/libraries/LibOnReStorage.sol";
import {IOnReAppErrors} from "../interfaces/IOnReAppErrors.sol";
import {OnReTypes} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {OnReIds} from "./OnReIds.sol";

/// @notice Shared authorization and storage validation used by domain libraries.
library LibOnReValidation {
    function enforceRole(bytes32 role) internal view {
        LibOnReAccessControl.checkRole(role);
    }

    function requireRegisteredOnReToken(address onReToken) internal view {
        if (LibOnReStorage.appStorage().onReTokenConfigs[onReToken].decimals == 0) {
            revert IOnReAppErrors.TokenNotRegisteredError(onReToken);
        }
    }

    function requireEnabledOnReToken(address onReToken) internal view {
        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.decimals == 0) revert IOnReAppErrors.TokenNotRegisteredError(onReToken);
        if (!config.enabled) revert IOnReAppErrors.InvalidTokenError();
    }

    function requirePricer(bytes32 pricerId) internal view returns (OnReTypes.Pricer storage pricer) {
        pricer = LibOnReStorage.appStorage().pricers[pricerId];
        if (!pricer.exists) revert IOnReAppErrors.PricerNotFoundError(pricerId);
    }

    function requireExecutablePricer(bytes32 pricerId) internal view returns (OnReTypes.Pricer storage pricer) {
        pricer = requirePricer(pricerId);
        if (pricer.disabled) revert IOnReAppErrors.PricerDisabledError(pricerId);
        requireEnabledOnReToken(pricer.onReToken);
    }

    function requireQuoter(bytes32 quoterId) internal view returns (OnReTypes.Quoter storage quoter) {
        quoter = LibOnReStorage.appStorage().quoters[quoterId];
        if (!quoter.exists) revert IOnReAppErrors.QuoterNotFoundError(quoterId);
    }

    function requireExecutableQuoter(bytes32 quoterId) internal view returns (OnReTypes.Quoter storage quoter) {
        quoter = requireQuoter(quoterId);
        if (quoter.disabled) revert IOnReAppErrors.QuoterDisabledError(quoterId);
    }

    function requireFeeConfig(bytes32 feeConfigId) internal view returns (OnReTypes.FeeConfig storage feeConfig) {
        feeConfig = LibOnReStorage.appStorage().feeConfigs[feeConfigId];
        if (!feeConfig.exists) revert IOnReAppErrors.FeeConfigNotFoundError(feeConfigId);
    }

    function requireExecutableFeeConfig(bytes32 feeConfigId)
        internal
        view
        returns (OnReTypes.FeeConfig storage feeConfig)
    {
        feeConfig = requireFeeConfig(feeConfigId);
        if (!feeConfig.enabled) revert IOnReAppErrors.FeeConfigDisabledError(feeConfigId);
    }

    function requireConfigurableVault(bytes32 vaultId)
        internal
        view
        returns (OnReTypes.ConfigurableVault storage vault)
    {
        vault = LibOnReStorage.appStorage().configurableVaults[vaultId];
        if (!vault.exists) revert IOnReAppErrors.ConfigurableVaultNotFoundError(vaultId);
    }

    function requireVaultKind(bytes32 vaultId, OnReTypes.ConfigurableVaultKind expectedKind)
        internal
        view
        returns (OnReTypes.ConfigurableVault storage vault)
    {
        vault = requireConfigurableVault(vaultId);
        if (vault.kind != expectedKind) {
            revert IOnReAppErrors.InvalidConfigurableVaultKindError(vaultId, uint8(expectedKind), uint8(vault.kind));
        }
    }

    function requireOfferConfig(bytes32 offerConfigId)
        internal
        view
        returns (OnReTypes.OfferConfig storage offerConfig)
    {
        offerConfig = LibOnReStorage.appStorage().offerConfigs[offerConfigId];
        if (!offerConfig.exists) revert IOnReAppErrors.OfferConfigNotFoundError(offerConfigId);
    }

    function requireExecutableOfferConfig(bytes32 offerConfigId)
        internal
        view
        returns (OnReTypes.OfferConfig storage offerConfig)
    {
        if (LibOnReStorage.appStorage().isKilled) revert IOnReAppErrors.KilledError();
        offerConfig = requireOfferConfig(offerConfigId);
        if (offerConfig.disabled) revert IOnReAppErrors.OfferConfigDisabledError(offerConfigId);
        address onReToken =
            offerConfig.direction == OnReTypes.OfferDirection.AssetToOnRe ? offerConfig.tokenOut : offerConfig.tokenIn;
        requireExecutablePricer(OnReIds.usdPricerId(onReToken));
        requireExecutableQuoter(offerConfig.quoterId);
        requireExecutableFeeConfig(offerConfig.feeConfigId);
    }

    function requireFulfillmentRequest(bytes32 fulfillmentRequestId)
        internal
        view
        returns (OnReTypes.FulfillmentRequest storage request)
    {
        request = LibOnReStorage.appStorage().fulfillmentRequests[fulfillmentRequestId];
        if (!request.exists) {
            revert IOnReAppErrors.FulfillmentRequestNotFoundError(fulfillmentRequestId);
        }
    }

    function validateMintLimits(address onReToken, uint256 amount) internal view {
        OnReTypes.OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.maxMintAmount > 0 && amount > config.maxMintAmount) {
            revert IOnReAppErrors.MaxMintAmountExceededError(onReToken, amount, config.maxMintAmount);
        }

        if (config.maxSupply > 0) {
            uint256 newSupply = IERC20(onReToken).totalSupply() + amount;
            if (newSupply > config.maxSupply) {
                revert IOnReAppErrors.MaxSupplyExceededError(onReToken, newSupply, config.maxSupply);
            }
        }
    }
}
