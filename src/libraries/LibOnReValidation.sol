// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {LibOnReStorage} from "../diamond/LibOnReStorage.sol";
import {
    ConfigurableVaultNotFoundError,
    FeeConfigDisabledError,
    FeeConfigNotFoundError,
    FulfillmentRequestNotFoundError,
    InvalidConfigurableVaultKindError,
    InvalidOfferDirectionError,
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
    ManagedTokenConfig,
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

    function _requireRegisteredManagedToken(address managedToken) internal view {
        if (!_isManagedToken(managedToken)) {
            revert TokenNotRegisteredError(managedToken);
        }
    }

    function _requireEnabledManagedToken(address managedToken) internal view {
        ManagedTokenConfig storage config = LibOnReStorage._appStorage().managedTokenConfigs[managedToken];
        if (!config.exists) revert TokenNotRegisteredError(managedToken);
        if (!config.enabled) revert InvalidTokenError();
    }

    function _isManagedToken(address token) internal view returns (bool) {
        return LibOnReStorage._appStorage().managedTokenConfigs[token].exists;
    }

    function _requirePricer(bytes32 pricerId) internal view returns (Pricer storage pricer) {
        pricer = LibOnReStorage._appStorage().pricers[pricerId];
        if (!pricer.exists) revert PricerNotFoundError(pricerId);
    }

    function _requireExecutablePricer(bytes32 pricerId) internal view returns (Pricer storage pricer) {
        pricer = _requirePricer(pricerId);
        if (pricer.disabled) revert PricerDisabledError(pricerId);
        _requireEnabledManagedToken(pricer.managedToken);
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
        _requireExecutablePricer(OnReIds._usdPricerId(_offerManagedToken(offerConfig)));
        _requireExecutableQuoter(offerConfig.quoterId);
        _requireExecutableFeeConfig(offerConfig.feeConfigId);
    }

    function _offerManagedToken(OfferConfig storage offerConfig) internal view returns (address) {
        if (offerConfig.direction == OfferDirection.AssetToManaged) return offerConfig.tokenOut;
        if (offerConfig.direction == OfferDirection.ManagedToAsset) return offerConfig.tokenIn;
        revert InvalidOfferDirectionError();
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
