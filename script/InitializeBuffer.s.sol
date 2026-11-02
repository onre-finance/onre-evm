// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IDiamondProxy} from "../src/generated/IDiamondProxy.sol";
import {ManagedToken} from "../src/ManagedToken.sol";
import {BufferState, ConfigurableVault, ConfigurableVaultKind} from "../src/types/OnReTypes.sol";
import {OnReIds} from "../src/libraries/OnReIds.sol";
import {OfferConfiguration} from "./base/OfferConfiguration.sol";

/// @notice Initialize ONyc BUFFER on Base Sepolia and print simulated Safe transactions.
/// @dev Run: ONRE_ENV=base-sepolia forge script script/InitializeBuffer.s.sol --rpc-url "$BASE_SEPOLIA_RPC_URL"
/// initializeBuffer creates all three vaults; BUFFER fees are configured together, independently of offer FeeConfigs.
/// Rates are fixed in the local Base Sepolia config. Supply, timestamp and watermark seed from EVM state.
/// The buffer section references named vaults; their token-derived identities and destinations live under vaults.
/// This script requires a fresh BUFFER. It neither submits nor executes the printed Safe transactions.
contract InitializeBuffer is OfferConfiguration {
    struct BufferConfiguration {
        address managedToken;
        VaultDefinition reserveVault;
        VaultDefinition managementFeeVault;
        VaultDefinition performanceFeeVault;
        uint64 grossApr;
        uint16 managementFeeBasisPoints;
        uint16 performanceFeeBasisPoints;
        bool performanceFeeHighWatermarkEnabled;
    }

    function run() external {
        require(block.chainid == 84532, "BUFFER setup is Base Sepolia only");
        Environment memory env = _loadEnvironment();
        BufferConfiguration memory config = _loadBufferConfiguration();
        _init(env.diamond, env.safe);
        IDiamondProxy app = IDiamondProxy(diamond);
        ManagedToken token = ManagedToken(config.managedToken);
        address controller = token.bufferController();
        require(controller == address(0) || controller == diamond, "Managed token has another BUFFER controller");
        _validateVault(
            config.reserveVault, OnReIds._bufferReserveVaultId(config.managedToken), ConfigurableVaultKind.BufferReserve
        );
        _validateVault(
            config.managementFeeVault,
            OnReIds._bufferManagementFeeVaultId(config.managedToken),
            ConfigurableVaultKind.Fee
        );
        _validateVault(
            config.performanceFeeVault,
            OnReIds._bufferPerformanceFeeVaultId(config.managedToken),
            ConfigurableVaultKind.Fee
        );

        _diamondCall("initializeBuffer", abi.encodeCall(IDiamondProxy.initializeBuffer, (config.managedToken)));
        BufferState memory state = app.getBufferState(config.managedToken);
        require(
            state.reserveVaultId == OnReIds._bufferReserveVaultId(config.managedToken)
                && state.managementFeeVaultId == OnReIds._bufferManagementFeeVaultId(config.managedToken)
                && state.performanceFeeVaultId == OnReIds._bufferPerformanceFeeVaultId(config.managedToken),
            "Unexpected BUFFER vault IDs"
        );
        _configureVault(state.reserveVaultId, config.reserveVault);
        _configureVault(state.managementFeeVaultId, config.managementFeeVault);
        _configureVault(state.performanceFeeVaultId, config.performanceFeeVault);

        if (controller != diamond) {
            _call(
                config.managedToken, "setBufferController", abi.encodeCall(ManagedToken.setBufferController, (diamond))
            );
        }
        _diamondCall(
            "setBufferFeeConfig",
            abi.encodeCall(
                IDiamondProxy.setBufferFeeConfig,
                (
                    config.managedToken,
                    config.managementFeeBasisPoints,
                    config.performanceFeeBasisPoints,
                    config.performanceFeeHighWatermarkEnabled
                )
            )
        );
        _diamondCall(
            "setBufferGrossApr", abi.encodeCall(IDiamondProxy.setBufferGrossApr, (config.managedToken, config.grossApr))
        );

        state = app.getBufferState(config.managedToken);
        require(token.bufferController() == diamond, "BUFFER controller not set");
        require(
            state.exists && state.grossApr == config.grossApr
                && state.managementFeeBasisPoints == config.managementFeeBasisPoints
                && state.performanceFeeBasisPoints == config.performanceFeeBasisPoints
                && state.performanceFeeHighWatermarkEnabled == config.performanceFeeHighWatermarkEnabled,
            "BUFFER parameters not set"
        );
        require(state.previousSupply == token.totalSupply(), "BUFFER supply baseline not seeded");
        _log("Managed token", config.managedToken);
        _log("Reserve vault", state.reserveVaultId);
        _log("Management fee vault", state.managementFeeVaultId);
        _log("Performance fee vault", state.performanceFeeVaultId);
        _log("Gross APR (1e6 scale)", state.grossApr);
        _log("Management fee (bps)", state.managementFeeBasisPoints);
        _log("Performance fee (bps)", state.performanceFeeBasisPoints);
        _printTxs();
    }

    function _validateVault(VaultDefinition memory definition, bytes32 expectedId, ConfigurableVaultKind kind)
        private
        pure
    {
        require(
            _vaultId(definition) == expectedId && definition.kind == kind,
            "Named vault does not match BUFFER role/token"
        );
        require(definition.withdrawalDestination != address(0), "BUFFER vault destination not set");
        require(definition.refillTargetBps == 0, "BUFFER vault refill target must be zero");
    }

    function _configureVault(bytes32 vaultId, VaultDefinition memory definition) private {
        _diamondCall(
            "updateConfigurableVault",
            abi.encodeCall(IDiamondProxy.updateConfigurableVault, (vaultId, definition.withdrawalDestination, 0))
        );
        ConfigurableVault memory vault = IDiamondProxy(diamond).getConfigurableVault(vaultId);
        require(
            vault.exists && vault.kind == definition.kind
                && vault.withdrawalDestination == definition.withdrawalDestination && vault.refillTargetBps == 0,
            "BUFFER vault not configured"
        );
    }

    function _loadEnvironment() internal view virtual override returns (Environment memory) {
        require(
            keccak256(bytes(vm.envString("ONRE_ENV"))) == keccak256("base-sepolia"), "BUFFER setup is Base Sepolia only"
        );
        return super._loadEnvironment();
    }

    function _loadBufferConfiguration() internal view virtual returns (BufferConfiguration memory config) {
        string memory json = vm.readFile(string.concat(vm.projectRoot(), "/script/config/base-sepolia.json"));
        config.managedToken = vm.parseJsonAddress(json, ".buffer.managedToken");
        config.reserveVault = _parseVaultDefinition(json, vm.parseJsonString(json, ".buffer.reserveVault"));
        config.managementFeeVault = _parseVaultDefinition(json, vm.parseJsonString(json, ".buffer.managementFeeVault"));
        config.performanceFeeVault =
            _parseVaultDefinition(json, vm.parseJsonString(json, ".buffer.performanceFeeVault"));
        uint256 grossApr = vm.parseJsonUint(json, ".buffer.grossApr");
        uint256 managementFee = vm.parseJsonUint(json, ".buffer.managementFeeBasisPoints");
        uint256 performanceFee = vm.parseJsonUint(json, ".buffer.performanceFeeBasisPoints");
        require(config.managedToken != address(0), "BUFFER managed token not set");
        require(grossApr > 0 && grossApr <= 1_000_000, "Invalid BUFFER gross APR");
        require(managementFee <= 10_000 && performanceFee <= 10_000, "Invalid BUFFER fee basis points");
        config.grossApr = uint64(grossApr);
        config.managementFeeBasisPoints = uint16(managementFee);
        config.performanceFeeBasisPoints = uint16(performanceFee);
        config.performanceFeeHighWatermarkEnabled = vm.parseJsonBool(json, ".buffer.performanceFeeHighWatermarkEnabled");
    }
}
