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
    function _enforceRole(bytes32 role) internal view {
        LibOnReAccessControl._checkRole(role);
    }

    function _requireRegisteredOnReToken(address onReToken) internal view {
        if (LibOnReStorage._appStorage().onReTokenConfigs[onReToken].decimals == 0) {
            revert TokenNotRegisteredError(onReToken);
        }
    }

    function _requireEnabledOnReToken(address onReToken) internal view {
        OnReTokenConfig storage config = LibOnReStorage._appStorage().onReTokenConfigs[onReToken];
        if (config.decimals == 0) revert TokenNotRegisteredError(onReToken);
        if (!config.enabled) revert InvalidTokenError();
    }

    function _requirePricer(bytes32 pricerId) internal view returns (Pricer storage pricer) {
        pricer = LibOnReStorage._appStorage().pricers[pricerId];
        if (!pricer.exists) revert PricerNotFoundError(pricerId);
    }

    function _requireExecutablePricer(bytes32 pricerId) internal view returns (Pricer storage pricer) {
        pricer = _requirePricer(pricerId);
        if (pricer.disabled) revert PricerDisabledError(pricerId);
        _requireEnabledOnReToken(pricer.onReToken);
    }

    function _requireQuoter(bytes32 quoterId) internal view returns (Quoter storage quoter) {
        quoter = LibOnReStorage._appStorage().quoters[quoterId];
        if (!quoter.exists) revert QuoterNotFoundError(quoterId);
    }

    function _requireExecutableQuoter(bytes32 quoterId) internal view returns (Quoter storage quoter) {
        quoter = _requireQuoter(quoterId);
        if (quoter.disabled) revert QuoterDisabledError(quoterId);
    }

    function _requireFeeConfig(bytes32 feeConfigId) internal view returns (FeeConfig storage feeConfig) {
        feeConfig = LibOnReStorage._appStorage().feeConfigs[feeConfigId];
        if (!feeConfig.exists) revert FeeConfigNotFoundError(feeConfigId);
    }

    function _requireExecutableFeeConfig(bytes32 feeConfigId) internal view returns (FeeConfig storage feeConfig) {
        feeConfig = _requireFeeConfig(feeConfigId);
        if (!feeConfig.enabled) revert FeeConfigDisabledError(feeConfigId);
    }

    function _requireConfigurableVault(bytes32 vaultId) internal view returns (ConfigurableVault storage vault) {
        vault = LibOnReStorage._appStorage().configurableVaults[vaultId];
        if (!vault.exists) revert ConfigurableVaultNotFoundError(vaultId);
    }

    function _requireVaultKind(bytes32 vaultId, ConfigurableVaultKind expectedKind)
        internal
        view
        returns (ConfigurableVault storage vault)
    {
        vault = _requireConfigurableVault(vaultId);
        if (vault.kind != expectedKind) {
            revert InvalidConfigurableVaultKindError(vaultId, uint8(expectedKind), uint8(vault.kind));
        }
    }

    function _requireOfferConfig(bytes32 offerConfigId) internal view returns (OfferConfig storage offerConfig) {
        offerConfig = LibOnReStorage._appStorage().offerConfigs[offerConfigId];
        if (!offerConfig.exists) revert OfferConfigNotFoundError(offerConfigId);
    }

    function _requireExecutableOfferConfig(bytes32 offerConfigId)
        internal
        view
        returns (OfferConfig storage offerConfig)
    {
        if (LibOnReStorage._appStorage().isKilled) {
            revert KilledError();
        }
        offerConfig = _requireOfferConfig(offerConfigId);
        if (offerConfig.disabled) revert OfferConfigDisabledError(offerConfigId);
        address onReToken =
            offerConfig.direction == OfferDirection.AssetToOnRe ? offerConfig.tokenOut : offerConfig.tokenIn;
        _requireExecutablePricer(OnReIds._usdPricerId(onReToken));
        _requireExecutableQuoter(offerConfig.quoterId);
        _requireExecutableFeeConfig(offerConfig.feeConfigId);
    }

    function _requireFulfillmentRequest(bytes32 fulfillmentRequestId)
        internal
        view
        returns (FulfillmentRequest storage request)
    {
        request = LibOnReStorage._appStorage().fulfillmentRequests[fulfillmentRequestId];
        if (!request.exists) {
            revert FulfillmentRequestNotFoundError(fulfillmentRequestId);
        }
    }
}
