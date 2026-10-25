// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReIds} from "../../src/libraries/OnReIds.sol";
import {OnReOps} from "./OnReOps.sol";
import {
    ConfigurableVaultKind,
    OfferDirection,
    OfferFlow,
    PricingDenomination,
    PricingVector,
    PropAmmConfig,
    QuoterKind
} from "../../src/types/OnReTypes.sol";

/// Named components and explicit offers from script/config/<ONRE_ENV>.json.
abstract contract OfferConfiguration is OnReOps {
    struct PricerDefinition {
        string name;
        address managedToken;
        PricingDenomination denomination;
        PricingVector vector;
        uint64 activationDelaySeconds;
    }

    struct QuoterDefinition {
        string name;
        QuoterKind kind;
        uint64 instanceId;
        address managedToken;
        address assetToken;
        PropAmmConfig propAmm;
    }

    struct VaultDefinition {
        string name;
        ConfigurableVaultKind kind;
        uint64 instanceId;
        address withdrawalDestination;
        uint16 refillTargetBps;
    }

    struct FeeDefinition {
        string name;
        uint64 instanceId;
        uint16 basisPoints;
        uint256 minimumFeeAmount;
        string feeVault;
    }

    struct OfferDefinition {
        string name;
        address managedToken;
        address assetToken;
        OfferDirection direction;
        OfferFlow flow;
        string pricer;
        string quoter;
        string feeConfig;
        string proceedsVault;
        string liquidityVault;
    }

    struct Configuration {
        PricerDefinition[] pricers;
        QuoterDefinition[] quoters;
        VaultDefinition[] vaults;
        FeeDefinition[] feeConfigs;
        OfferDefinition[] offers;
    }

    function _loadOfferConfiguration() internal view virtual returns (Configuration memory config) {
        string memory json =
            vm.readFile(string.concat(vm.projectRoot(), "/script/config/", vm.envString("ONRE_ENV"), ".json"));
        return _parseOfferConfiguration(json);
    }

    function _parseOfferConfiguration(string memory json) internal pure returns (Configuration memory config) {
        string[] memory names = vm.parseJsonKeys(json, ".pricers");
        config.pricers = new PricerDefinition[](names.length);
        for (uint256 i; i < names.length; ++i) {
            string memory p = _path("pricers", names[i]);
            require(
                _is(vm.parseJsonString(json, string.concat(p, ".denomination")), "usd"),
                "Only USD pricers are supported"
            );
            config.pricers[i] = PricerDefinition({
                name: names[i],
                managedToken: vm.parseJsonAddress(json, string.concat(p, ".managedToken")),
                denomination: PricingDenomination.Usd,
                vector: PricingVector({
                    startTime: _u64(json, string.concat(p, ".vector.startTime")),
                    baseTime: _u64(json, string.concat(p, ".vector.baseTime")),
                    basePrice: _u64(json, string.concat(p, ".vector.basePrice")),
                    apr: _u64(json, string.concat(p, ".vector.apr")),
                    priceFixDuration: _u64(json, string.concat(p, ".vector.priceFixDuration"))
                }),
                activationDelaySeconds: _u64(json, string.concat(p, ".activationDelaySeconds"))
            });
        }
        names = vm.parseJsonKeys(json, ".quoters");
        config.quoters = new QuoterDefinition[](names.length);
        for (uint256 i; i < names.length; ++i) {
            string memory p = _path("quoters", names[i]);
            QuoterDefinition memory q;
            q.name = names[i];
            q.kind = _quoterKind(vm.parseJsonString(json, string.concat(p, ".kind")));
            q.instanceId = _u64(json, string.concat(p, ".instanceId"));
            if (q.kind == QuoterKind.PropAmm) {
                q.managedToken = vm.parseJsonAddress(json, string.concat(p, ".managedToken"));
                q.assetToken = vm.parseJsonAddress(json, string.concat(p, ".assetToken"));
                q.propAmm = PropAmmConfig({
                    epochDurationSeconds: _u64(json, string.concat(p, ".config.epochDurationSeconds")),
                    curveExponentScaled: _u32(json, string.concat(p, ".config.curveExponentScaled")),
                    cadenceThreshold: _u32(json, string.concat(p, ".config.cadenceThreshold")),
                    cadenceWaveScaled: _u32(json, string.concat(p, ".config.cadenceWaveScaled")),
                    wallSensitivityScaled: _u32(json, string.concat(p, ".config.wallSensitivityScaled")),
                    curvePegHaircutBps: _u16(json, string.concat(p, ".config.curvePegHaircutBps"))
                });
            }
            config.quoters[i] = q;
        }
        names = vm.parseJsonKeys(json, ".vaults");
        config.vaults = new VaultDefinition[](names.length);
        for (uint256 i; i < names.length; ++i) {
            string memory p = _path("vaults", names[i]);
            config.vaults[i] = VaultDefinition({
                name: names[i],
                kind: _vaultKind(vm.parseJsonString(json, string.concat(p, ".kind"))),
                instanceId: _u64(json, string.concat(p, ".instanceId")),
                withdrawalDestination: vm.parseJsonAddress(json, string.concat(p, ".withdrawalDestination")),
                refillTargetBps: _u16(json, string.concat(p, ".refillTargetBps"))
            });
        }
        names = vm.parseJsonKeys(json, ".feeConfigs");
        config.feeConfigs = new FeeDefinition[](names.length);
        for (uint256 i; i < names.length; ++i) {
            string memory p = _path("feeConfigs", names[i]);
            config.feeConfigs[i] = FeeDefinition({
                name: names[i],
                instanceId: _u64(json, string.concat(p, ".instanceId")),
                basisPoints: _u16(json, string.concat(p, ".basisPoints")),
                minimumFeeAmount: vm.parseJsonUint(json, string.concat(p, ".minimumFeeAmount")),
                feeVault: vm.parseJsonString(json, string.concat(p, ".feeVault"))
            });
        }
        names = vm.parseJsonKeys(json, ".offers");
        config.offers = new OfferDefinition[](names.length);
        for (uint256 i; i < names.length; ++i) {
            string memory p = _path("offers", names[i]);
            config.offers[i] = OfferDefinition({
                name: names[i],
                managedToken: vm.parseJsonAddress(json, string.concat(p, ".managedToken")),
                assetToken: vm.parseJsonAddress(json, string.concat(p, ".assetToken")),
                direction: _direction(vm.parseJsonString(json, string.concat(p, ".direction"))),
                flow: _flow(vm.parseJsonString(json, string.concat(p, ".flow"))),
                pricer: vm.parseJsonString(json, string.concat(p, ".pricer")),
                quoter: vm.parseJsonString(json, string.concat(p, ".quoter")),
                feeConfig: vm.parseJsonString(json, string.concat(p, ".feeConfig")),
                proceedsVault: vm.parseJsonString(json, string.concat(p, ".proceedsVault")),
                liquidityVault: vm.parseJsonString(json, string.concat(p, ".liquidityVault"))
            });
        }
    }

    function _offer(Configuration memory config, string memory name) internal pure returns (OfferDefinition memory) {
        for (uint256 i; i < config.offers.length; ++i) {
            if (_is(config.offers[i].name, name)) return config.offers[i];
        }
        revert(string.concat("Unknown offer: ", name));
    }

    function _liquidityVaultId(Configuration memory config, string memory name) internal pure returns (bytes32) {
        require(!_is(name, "none"), "Offer has no liquidity vault");
        for (uint256 i; i < config.vaults.length; ++i) {
            VaultDefinition memory vault = config.vaults[i];
            if (!_is(vault.name, name)) continue;
            require(vault.kind == ConfigurableVaultKind.Liquidity, "Offer vault must be liquidity kind");
            return OnReIds._configurableVaultId(vault.kind, vault.instanceId);
        }
        revert(string.concat("Unknown liquidity vault: ", name));
    }

    function _path(string memory collection, string memory name) private pure returns (string memory) {
        bytes memory chars = bytes(name);
        require(chars.length > 0 && !_is(name, "none"), "Invalid component name");
        for (uint256 i; i < chars.length; ++i) {
            bytes1 c = chars[i];
            require(
                (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") || (c >= "0" && c <= "9") || c == "-" || c == "_",
                "Invalid component name"
            );
        }
        return string.concat(".", collection, '["', name, '"]');
    }

    function _u64(string memory json, string memory key) private pure returns (uint64) {
        uint256 v = vm.parseJsonUint(json, key);
        require(v <= type(uint64).max, string.concat("Config value exceeds uint64: ", key));
        return uint64(v);
    }

    function _u32(string memory json, string memory key) private pure returns (uint32) {
        uint64 v = _u64(json, key);
        require(v <= type(uint32).max, string.concat("Config value exceeds uint32: ", key));
        return uint32(v);
    }

    function _u16(string memory json, string memory key) private pure returns (uint16) {
        uint64 v = _u64(json, key);
        require(v <= type(uint16).max, string.concat("Config value exceeds uint16: ", key));
        return uint16(v);
    }

    function _is(string memory a, string memory b) internal pure returns (bool) {
        return keccak256(bytes(a)) == keccak256(bytes(b));
    }

    function _flow(string memory name) private pure returns (OfferFlow) {
        if (_is(name, "permissionless")) return OfferFlow.Permissionless;
        if (_is(name, "permissioned")) return OfferFlow.Permissioned;
        if (_is(name, "worker")) return OfferFlow.Worker;
        revert("Unknown offer flow");
    }

    function _direction(string memory name) private pure returns (OfferDirection) {
        if (_is(name, "assetToManaged")) return OfferDirection.AssetToManaged;
        if (_is(name, "managedToAsset")) return OfferDirection.ManagedToAsset;
        revert("Unknown offer direction");
    }

    function _quoterKind(string memory name) private pure returns (QuoterKind) {
        if (_is(name, "nav")) return QuoterKind.Nav;
        if (_is(name, "navPermissionless")) return QuoterKind.NavPermissionless;
        if (_is(name, "propAmm")) return QuoterKind.PropAmm;
        revert("Unknown quoter kind");
    }

    function _vaultKind(string memory name) private pure returns (ConfigurableVaultKind) {
        if (_is(name, "fee")) return ConfigurableVaultKind.Fee;
        if (_is(name, "proceeds")) return ConfigurableVaultKind.Proceeds;
        if (_is(name, "liquidity")) return ConfigurableVaultKind.Liquidity;
        if (_is(name, "bufferReserve")) return ConfigurableVaultKind.BufferReserve;
        revert("Unknown vault kind");
    }

    function _tokens(OfferDefinition memory offer) internal pure returns (address tokenIn, address tokenOut) {
        return offer.direction == OfferDirection.AssetToManaged
            ? (offer.assetToken, offer.managedToken)
            : (offer.managedToken, offer.assetToken);
    }
}
