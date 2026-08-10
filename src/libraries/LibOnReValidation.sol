// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    ConfigurableVaultNotFoundError,
    FeeConfigDisabledError,
    FeeConfigNotFoundError,
    FulfillmentRequestNotFoundError,
    InvalidConfigurableVaultKindError,
    InvalidTokenError,
    KilledError,
    OfferConfigDisabledError,
    OfferConfigNotFoundError,
    PricerDisabledError,
    PricerNotFoundError,
    QuoterDisabledError,
    QuoterNotFoundError,
    TokenNotRegisteredError
} from "../types/OnReAppErrors.sol";
import {
    ConfigurableVault,
    ConfigurableVaultKind,
    FeeConfig,
    FulfillmentRequest,
    OfferConfig,
    OfferDirection,
    OnReTokenConfig,
    Pricer,
    Quoter
} from "../types/OnReTypes.sol";
import {LibOnReAccessControl} from "./LibOnReAccessControl.sol";
import {OnReIds} from "./OnReIds.sol";

/// @notice Shared authorization and storage validation used by domain libraries.
library LibOnReValidation {
    function enforceRole(bytes32 role) internal view {
        LibOnReAccessControl.checkRole(role);
    }

    function requireRegisteredOnReToken(address onReToken) internal view {
        if (LibOnReStorage.appStorage().onReTokenConfigs[onReToken].decimals == 0) {
            revert TokenNotRegisteredError(onReToken);
        }
    }

    function requireEnabledOnReToken(address onReToken) internal view {
        OnReTokenConfig storage config = LibOnReStorage.appStorage().onReTokenConfigs[onReToken];
        if (config.decimals == 0) revert TokenNotRegisteredError(onReToken);
        if (!config.enabled) revert InvalidTokenError();
    }

    function requirePricer(bytes32 pricerId) internal view returns (Pricer storage pricer) {
        pricer = LibOnReStorage.appStorage().pricers[pricerId];
        if (!pricer.exists) revert PricerNotFoundError(pricerId);
    }

    function requireExecutablePricer(bytes32 pricerId) internal view returns (Pricer storage pricer) {
        pricer = requirePricer(pricerId);
        if (pricer.disabled) revert PricerDisabledError(pricerId);
        requireEnabledOnReToken(pricer.onReToken);
    }

    function requireQuoter(bytes32 quoterId) internal view returns (Quoter storage quoter) {
        quoter = LibOnReStorage.appStorage().quoters[quoterId];
        if (!quoter.exists) revert QuoterNotFoundError(quoterId);
    }

    function requireExecutableQuoter(bytes32 quoterId) internal view returns (Quoter storage quoter) {
        quoter = requireQuoter(quoterId);
        if (quoter.disabled) revert QuoterDisabledError(quoterId);
    }

    function requireFeeConfig(bytes32 feeConfigId) internal view returns (FeeConfig storage feeConfig) {
        feeConfig = LibOnReStorage.appStorage().feeConfigs[feeConfigId];
        if (!feeConfig.exists) revert FeeConfigNotFoundError(feeConfigId);
    }

    function requireExecutableFeeConfig(bytes32 feeConfigId) internal view returns (FeeConfig storage feeConfig) {
        feeConfig = requireFeeConfig(feeConfigId);
        if (!feeConfig.enabled) revert FeeConfigDisabledError(feeConfigId);
    }

    function requireConfigurableVault(bytes32 vaultId) internal view returns (ConfigurableVault storage vault) {
        vault = LibOnReStorage.appStorage().configurableVaults[vaultId];
        if (!vault.exists) revert ConfigurableVaultNotFoundError(vaultId);
    }

    function requireVaultKind(bytes32 vaultId, ConfigurableVaultKind expectedKind)
        internal
        view
        returns (ConfigurableVault storage vault)
    {
        vault = requireConfigurableVault(vaultId);
        if (vault.kind != expectedKind) {
            revert InvalidConfigurableVaultKindError(vaultId, uint8(expectedKind), uint8(vault.kind));
        }
    }

    function requireOfferConfig(bytes32 offerConfigId) internal view returns (OfferConfig storage offerConfig) {
        offerConfig = LibOnReStorage.appStorage().offerConfigs[offerConfigId];
        if (!offerConfig.exists) revert OfferConfigNotFoundError(offerConfigId);
    }

    function requireExecutableOfferConfig(bytes32 offerConfigId)
        internal
        view
        returns (OfferConfig storage offerConfig)
    {
        if (LibOnReStorage.appStorage().isKilled) {
            revert KilledError();
        }
        offerConfig = requireOfferConfig(offerConfigId);
        if (offerConfig.disabled) revert OfferConfigDisabledError(offerConfigId);
        address onReToken =
            offerConfig.direction == OfferDirection.AssetToOnRe ? offerConfig.tokenOut : offerConfig.tokenIn;
        requireExecutablePricer(OnReIds.usdPricerId(onReToken));
        requireExecutableQuoter(offerConfig.quoterId);
        requireExecutableFeeConfig(offerConfig.feeConfigId);
    }

    function requireFulfillmentRequest(bytes32 fulfillmentRequestId)
        internal
        view
        returns (FulfillmentRequest storage request)
    {
        request = LibOnReStorage.appStorage().fulfillmentRequests[fulfillmentRequestId];
        if (!request.exists) {
            revert FulfillmentRequestNotFoundError(fulfillmentRequestId);
        }
    }
}
