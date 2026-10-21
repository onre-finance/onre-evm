// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IDiamondProxy} from "../../src/generated/IDiamondProxy.sol";
import {ManagedToken} from "../../src/ManagedToken.sol";
import {
    ConfigurableVaultKind,
    MakeOfferConfigParams,
    PricingDenomination,
    PricingVector,
    PropAmmConfig,
    QuoterKind
} from "../../src/types/OnReTypes.sol";
import {SafeScript} from "./SafeScript.sol";

/// Composable OnRe operations. Each op is recorded as a Safe tx, simulated, and returns the created ID if any.
abstract contract OnReOps is SafeScript {
    // --- Diamond ---

    function _addApprover(address approver) internal {
        _diamondCall("addApprover", abi.encodeCall(IDiamondProxy.addApprover, (approver)));
    }

    function _setPermissionlessSettlementAccount(address account) internal {
        _diamondCall(
            "setPermissionlessSettlementAccount",
            abi.encodeCall(IDiamondProxy.setPermissionlessSettlementAccount, (account))
        );
    }

    function _createPricer(address managedToken, PricingDenomination denomination) internal returns (bytes32) {
        bytes memory ret =
            _diamondCall("createPricer", abi.encodeCall(IDiamondProxy.createPricer, (managedToken, denomination)));
        return abi.decode(ret, (bytes32));
    }

    function _addPricingVector(bytes32 pricerId, PricingVector memory vector) internal {
        _diamondCall("addPricingVector", abi.encodeCall(IDiamondProxy.addPricingVector, (pricerId, vector)));
    }

    function _createQuoter(QuoterKind kind, uint64 instanceId) internal returns (bytes32) {
        bytes memory ret = _diamondCall("createQuoter", abi.encodeCall(IDiamondProxy.createQuoter, (kind, instanceId)));
        return abi.decode(ret, (bytes32));
    }

    function _configurePropAmm(bytes32 quoterId, address assetToken, address managedToken, PropAmmConfig memory config)
        internal
    {
        _diamondCall(
            "configurePropAmm",
            abi.encodeCall(IDiamondProxy.configurePropAmm, (quoterId, assetToken, managedToken, config))
        );
    }

    /// Withdrawal destination is the Safe.
    function _createConfigurableVault(ConfigurableVaultKind kind, uint64 instanceId, uint16 refillTargetBps)
        internal
        returns (bytes32)
    {
        bytes memory ret = _diamondCall(
            string.concat("createConfigurableVault (", _vaultKindName(kind), ")"),
            abi.encodeCall(IDiamondProxy.createConfigurableVault, (kind, instanceId, safe, refillTargetBps))
        );
        return abi.decode(ret, (bytes32));
    }

    function _createFeeConfig(uint64 instanceId, uint16 basisPoints, uint256 minimumFeeAmount, bytes32 feeVaultId)
        internal
        returns (bytes32)
    {
        bytes memory ret = _diamondCall(
            "createFeeConfig",
            abi.encodeCall(IDiamondProxy.createFeeConfig, (instanceId, basisPoints, minimumFeeAmount, feeVaultId))
        );
        return abi.decode(ret, (bytes32));
    }

    function _makeOfferConfig(MakeOfferConfigParams memory params) internal returns (bytes32) {
        bytes memory ret = _diamondCall("makeOfferConfig", abi.encodeCall(IDiamondProxy.makeOfferConfig, (params)));
        return abi.decode(ret, (bytes32));
    }

    function _setOfferConfigEnabled(bytes32 offerId, bool enabled) internal {
        _diamondCall("setOfferConfigEnabled", abi.encodeCall(IDiamondProxy.setOfferConfigEnabled, (offerId, enabled)));
    }

    function _depositConfigurableVault(bytes32 vaultId, address token, uint256 amount) internal {
        _diamondCall(
            "depositConfigurableVault", abi.encodeCall(IDiamondProxy.depositConfigurableVault, (vaultId, token, amount))
        );
    }

    // --- Managed token ---

    /// Deploys the ManagedToken implementation through the CREATE2 factory.
    function _deployManagedTokenImpl(bytes32 salt) internal returns (address impl) {
        bytes memory creationCode = type(ManagedToken).creationCode;
        impl = vm.computeCreate2Address(salt, keccak256(creationCode), CREATE2_FACTORY);
        require(impl.code.length == 0, "ManagedToken implementation already deployed");

        _call(CREATE2_FACTORY, "deploy ManagedToken implementation (CREATE2)", abi.encodePacked(salt, creationCode));
        require(impl.code.length != 0, "implementation deployment simulation failed");
    }

    /// Safe becomes admin and CCIP admin. Returned address is simulated and depends on the Diamond nonce.
    function _deployManagedToken(address impl, string memory name, string memory symbol, uint8 decimals)
        internal
        returns (address)
    {
        bytes memory ret = _diamondCall(
            "deployManagedToken",
            abi.encodeCall(
                IDiamondProxy.deployManagedToken,
                (impl, name, symbol, decimals, safe, safe, new address[](0), new address[](0))
            )
        );
        return abi.decode(ret, (address));
    }

    // --- ERC20 ---

    function _approve(address token, address spender, uint256 amount) internal {
        _call(token, "approve", abi.encodeCall(IERC20.approve, (spender, amount)));
    }

    function _mint(address token, address to, uint256 amount) internal {
        // `0x40c10f19` = mint(address, amount)
        _call(token, "mint", abi.encodeWithSelector(0x40c10f19, to, amount));
    }

    function _vaultKindName(ConfigurableVaultKind kind) private pure returns (string memory) {
        if (kind == ConfigurableVaultKind.Fee) return "Fee";
        if (kind == ConfigurableVaultKind.Proceeds) return "Proceeds";
        if (kind == ConfigurableVaultKind.Liquidity) return "Liquidity";
        return "BufferReserve";
    }
}
