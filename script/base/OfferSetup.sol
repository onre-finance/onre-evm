// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {console} from "forge-std/Script.sol";
import {OfferConfiguration} from "./OfferConfiguration.sol";
import {IDiamondProxy} from "../../src/generated/IDiamondProxy.sol";
import {OnReIds} from "../../src/libraries/OnReIds.sol";
import {
    ConfigurableVaultNotFoundError,
    FeeConfigNotFoundError,
    OfferConfigNotFoundError,
    PricerNotFoundError,
    QuoterNotFoundError
} from "../../src/types/OnReAppErrors.sol";
import {
    ConfigurableVault,
    FeeConfig,
    MakeOfferConfigParams,
    OfferConfig,
    OfferDirection,
    OfferFlow,
    Pricer,
    PricingVector,
    PropAmmState,
    Quoter,
    QuoterKind
} from "../../src/types/OnReTypes.sol";

/// Resolves named configuration references, creates missing components, and verifies reused state.
abstract contract OfferSetup is OfferConfiguration {
    struct NamedIds {
        string[] names;
        bytes32[] ids;
    }

    struct References {
        NamedIds pricers;
        NamedIds quoters;
        NamedIds vaults;
        NamedIds fees;
    }

    /// Compatibility scripts select offers by their explicit flow, direction, and quoter kind.
    function _setupMatchingOffers(OfferFlow flow, OfferDirection direction, QuoterKind kind) internal {
        Configuration memory config = _loadOfferConfiguration();
        uint256 count;
        for (uint256 i; i < config.offers.length; ++i) {
            if (_matchesSelection(config, config.offers[i], flow, direction, kind)) ++count;
        }
        require(count != 0, "No matching offers configured; use SetupOffers for all definitions");
        OfferDefinition[] memory selected = new OfferDefinition[](count);
        count = 0;
        for (uint256 i; i < config.offers.length; ++i) {
            if (_matchesSelection(config, config.offers[i], flow, direction, kind)) {
                selected[count++] = config.offers[i];
            }
        }
        config.offers = selected;
        _setupOffers(_loadEnvironment(), config);
        _printTxs();
    }

    function _matchesSelection(
        Configuration memory config,
        OfferDefinition memory offer,
        OfferFlow flow,
        OfferDirection direction,
        QuoterKind kind
    ) private pure returns (bool) {
        if (offer.flow != flow || offer.direction != direction) return false;
        for (uint256 i; i < config.quoters.length; ++i) {
            if (_is(config.quoters[i].name, offer.quoter)) return config.quoters[i].kind == kind;
        }
        revert(string.concat("Unknown component reference: ", offer.quoter));
    }

    function _setupOffers(Environment memory env, Configuration memory config) internal {
        _init(env.diamond, env.safe);
        References memory refs = _resolve(config);
        // The contract validates fee limits, vault kinds, quoter/flow compatibility,
        // and Prop AMM pairs during simulation. Only the named pricer binding is off-chain.
        for (uint256 i; i < config.offers.length; ++i) {
            OfferDefinition memory offer = config.offers[i];
            require(
                _ref(refs.pricers, offer.pricer) == OnReIds._usdPricerId(offer.managedToken),
                "Offer pricer must be managed token USD pricer"
            );
        }
        bool permissionless;
        for (uint256 i; i < config.offers.length; ++i) {
            if (config.offers[i].flow == OfferFlow.Permissionless) permissionless = true;
        }
        if (permissionless) {
            require(env.settlementAccount != address(0), "SETTLEMENT_ACCOUNT not set");
            if (IDiamondProxy(diamond).permissionlessSettlementAccount() != env.settlementAccount) {
                _setPermissionlessSettlementAccount(env.settlementAccount);
            }
        }
        for (uint256 i; i < config.pricers.length; ++i) {
            _ensurePricer(config.pricers[i], refs.pricers.ids[i]);
        }
        for (uint256 i; i < config.vaults.length; ++i) {
            _ensureVault(config.vaults[i], refs.vaults.ids[i]);
        }
        for (uint256 i; i < config.quoters.length; ++i) {
            _ensureQuoter(config.quoters[i], refs.quoters.ids[i]);
        }
        for (uint256 i; i < config.feeConfigs.length; ++i) {
            FeeDefinition memory fee = config.feeConfigs[i];
            _ensureFee(fee, refs.fees.ids[i], _ref(refs.vaults, fee.feeVault));
        }
        for (uint256 i; i < config.offers.length; ++i) {
            OfferDefinition memory definition = config.offers[i];
            (address tokenIn, address tokenOut) = _tokens(definition);
            MakeOfferConfigParams memory params = MakeOfferConfigParams({
                tokenIn: tokenIn,
                tokenOut: tokenOut,
                flow: definition.flow,
                quoterId: _ref(refs.quoters, definition.quoter),
                feeConfigId: _ref(refs.fees, definition.feeConfig),
                proceedsVaultId: _ref(refs.vaults, definition.proceedsVault),
                liquidityVaultId: _is(definition.liquidityVault, "none")
                    ? bytes32(0)
                    : _ref(refs.vaults, definition.liquidityVault)
            });
            bytes32 offerId = _ensureOffer(params, definition.enabled);
            console.log("Offer:", definition.name);
            console.log("Enabled:", definition.enabled);
            _log("Offer ID", offerId);
            _log("USD pricer ID", _ref(refs.pricers, definition.pricer));
        }
    }

    function _resolve(Configuration memory c) internal pure returns (References memory r) {
        r.pricers = _allocate(c.pricers.length);
        r.quoters = _allocate(c.quoters.length);
        r.vaults = _allocate(c.vaults.length);
        r.fees = _allocate(c.feeConfigs.length);
        for (uint256 i; i < c.pricers.length; ++i) {
            require(c.pricers[i].managedToken != address(0), "Pricer managed token not set");
            _define(
                r.pricers, i, c.pricers[i].name, OnReIds._pricerId(c.pricers[i].managedToken, c.pricers[i].denomination)
            );
        }
        for (uint256 i; i < c.quoters.length; ++i) {
            _define(r.quoters, i, c.quoters[i].name, OnReIds._quoterId(c.quoters[i].kind, c.quoters[i].instanceId));
        }
        for (uint256 i; i < c.vaults.length; ++i) {
            _define(
                r.vaults, i, c.vaults[i].name, OnReIds._configurableVaultId(c.vaults[i].kind, c.vaults[i].instanceId)
            );
        }
        for (uint256 i; i < c.feeConfigs.length; ++i) {
            _define(r.fees, i, c.feeConfigs[i].name, OnReIds._feeConfigId(c.feeConfigs[i].instanceId));
        }
        NamedIds memory offers = _allocate(c.offers.length);
        require(c.offers.length > 0, "No offers configured");
        for (uint256 i; i < c.offers.length; ++i) {
            OfferDefinition memory offer = c.offers[i];
            require(
                offer.managedToken != address(0) && offer.assetToken != address(0)
                    && offer.managedToken != offer.assetToken,
                "Invalid offer tokens"
            );
            (address tokenIn, address tokenOut) = _tokens(offer);
            _define(offers, i, offer.name, OnReIds._offerConfigId(tokenIn, tokenOut, offer.flow));
        }
    }

    function _ensurePricer(PricerDefinition memory definition, bytes32 pricerId) private {
        if (!_exists(abi.encodeCall(IDiamondProxy.getPricer, (pricerId)), PricerNotFoundError.selector)) {
            _createPricer(definition.managedToken, definition.denomination);
        }
        Pricer memory pricer = IDiamondProxy(diamond).getPricer(pricerId);
        require(
            pricer.enabled && pricer.managedToken == definition.managedToken
                && pricer.denomination == definition.denomination,
            "Existing pricer differs or is disabled"
        );
        PricingVector memory desired = definition.vector;
        if (pricer.vectorCount > 0) {
            PricingVector memory latest = pricer.vectors[pricer.vectorCount - 1];
            require(
                latest.baseTime == desired.baseTime && latest.basePrice == desired.basePrice
                    && latest.apr == desired.apr && latest.priceFixDuration == desired.priceFixDuration
                    && (desired.startTime == 0 || latest.startTime == desired.startTime),
                "Existing pricing vector differs; update pricing explicitly"
            );
            _log("Vector activation", latest.startTime);
            return;
        }
        if (desired.startTime == 0) {
            require(definition.activationDelaySeconds > 0, "Set a future vector activation or activation delay");
            uint256 activation = block.timestamp + definition.activationDelaySeconds;
            require(activation <= type(uint64).max, "Vector activation exceeds uint64");
            desired.startTime = uint64(activation);
        }
        _addPricingVector(pricerId, desired);
        _log("Vector activation (execute Safe batch before this time)", desired.startTime);
    }

    function _ensureVault(VaultDefinition memory definition, bytes32 vaultId) private {
        if (!_exists(
                abi.encodeCall(IDiamondProxy.getConfigurableVault, (vaultId)), ConfigurableVaultNotFoundError.selector
            )) {
            _createConfigurableVault(
                definition.kind, definition.instanceId, definition.withdrawalDestination, definition.refillTargetBps
            );
        }
        ConfigurableVault memory vault = IDiamondProxy(diamond).getConfigurableVault(vaultId);
        require(
            vault.kind == definition.kind && vault.withdrawalDestination == definition.withdrawalDestination
                && vault.refillTargetBps == definition.refillTargetBps,
            "Existing vault differs from config"
        );
    }

    function _ensureQuoter(QuoterDefinition memory definition, bytes32 quoterId) private {
        if (!_exists(abi.encodeCall(IDiamondProxy.getQuoter, (quoterId)), QuoterNotFoundError.selector)) {
            _createQuoter(definition.kind, definition.instanceId);
        }
        Quoter memory quoter = IDiamondProxy(diamond).getQuoter(quoterId);
        require(
            quoter.enabled && quoter.kind == definition.kind && quoter.instanceId == definition.instanceId,
            "Existing quoter differs or is disabled"
        );
        if (definition.kind == QuoterKind.PropAmm) {
            PropAmmState memory state = IDiamondProxy(diamond).getPropAmmState(quoterId);
            if (state.managedToken == address(0)) {
                _configurePropAmm(quoterId, definition.assetToken, definition.managedToken, definition.propAmm);
            } else {
                require(
                    state.managedToken == definition.managedToken && state.assetToken == definition.assetToken
                        && keccak256(abi.encode(state.config)) == keccak256(abi.encode(definition.propAmm)),
                    "Existing Prop AMM config differs"
                );
            }
        }
    }

    function _ensureFee(FeeDefinition memory definition, bytes32 feeId, bytes32 feeVaultId) private {
        if (!_exists(abi.encodeCall(IDiamondProxy.getFeeConfig, (feeId)), FeeConfigNotFoundError.selector)) {
            _createFeeConfig(definition.instanceId, definition.basisPoints, definition.minimumFeeAmount, feeVaultId);
        }
        FeeConfig memory fee = IDiamondProxy(diamond).getFeeConfig(feeId);
        require(
            fee.enabled && fee.basisPoints == definition.basisPoints
                && fee.minimumFeeAmount == definition.minimumFeeAmount && fee.feeVaultId == feeVaultId,
            "Existing fee config differs; choose another instanceId"
        );
    }

    function _ensureOffer(MakeOfferConfigParams memory params, bool enabled) private returns (bytes32 offerId) {
        offerId = OnReIds._offerConfigId(params.tokenIn, params.tokenOut, params.flow);
        IDiamondProxy app = IDiamondProxy(diamond);
        if (!_exists(abi.encodeCall(IDiamondProxy.getOfferConfig, (offerId)), OfferConfigNotFoundError.selector)) {
            _makeOfferConfig(params);
        }
        OfferConfig memory existing = app.getOfferConfig(offerId);
        // Creation defaults to enabled. Execute creation + disabling in one atomic Safe batch.
        // Disable existing offers before changing references; enable only after references match.
        if (!enabled && existing.enabled) _setOfferConfigEnabled(offerId, false);
        if (!_matches(existing, params)) {
            _diamondCall(
                "updateOfferConfigReferences",
                abi.encodeCall(
                    IDiamondProxy.updateOfferConfigReferences,
                    (offerId, params.quoterId, params.feeConfigId, params.proceedsVaultId, params.liquidityVaultId)
                )
            );
        }
        if (enabled && !existing.enabled) _setOfferConfigEnabled(offerId, true);
        OfferConfig memory offer = app.getOfferConfig(offerId);
        require(offer.enabled == enabled && _matches(offer, params), "Offer verification failed");
    }

    function _matches(OfferConfig memory offer, MakeOfferConfigParams memory params) private pure returns (bool) {
        return offer.quoterId == params.quoterId && offer.feeConfigId == params.feeConfigId
            && offer.proceedsVaultId == params.proceedsVaultId && offer.liquidityVaultId == params.liquidityVaultId;
    }

    function _allocate(uint256 count) private pure returns (NamedIds memory) {
        return NamedIds(new string[](count), new bytes32[](count));
    }

    function _define(NamedIds memory collection, uint256 position, string memory name, bytes32 componentId)
        private
        pure
    {
        require(bytes(name).length > 0 && !_is(name, "none"), "Invalid component name");
        for (uint256 j; j < position; ++j) {
            require(!_is(collection.names[j], name), "Duplicate component name");
            require(collection.ids[j] != componentId, "Duplicate component identity");
        }
        collection.names[position] = name;
        collection.ids[position] = componentId;
    }

    function _index(NamedIds memory collection, string memory name) private pure returns (uint256) {
        for (uint256 i; i < collection.names.length; ++i) {
            if (_is(collection.names[i], name)) return i;
        }
        revert(string.concat("Unknown component reference: ", name));
    }

    function _ref(NamedIds memory collection, string memory name) private pure returns (bytes32) {
        return collection.ids[_index(collection, name)];
    }

    function _exists(bytes memory query, bytes4 missingError) private view returns (bool) {
        (bool ok, bytes memory result) = diamond.staticcall(query);
        if (ok) return true;
        if (result.length >= 4 && bytes4(result) == missingError) return false;
        assembly ("memory-safe") { revert(add(result, 0x20), mload(result)) }
    }
}
