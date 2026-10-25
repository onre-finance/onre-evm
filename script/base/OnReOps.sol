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

/// Shared operations record and simulate calls through SafeScript.
abstract contract OnReOps is SafeScript {
    function _setPermissionlessSettlementAccount(address account) internal {
        _diamondCall(
            "setPermissionlessSettlementAccount",
            abi.encodeCall(IDiamondProxy.setPermissionlessSettlementAccount, (account))
        );
    }

    function _createPricer(address managedToken, PricingDenomination denomination) internal {
        _diamondCall("createPricer", abi.encodeCall(IDiamondProxy.createPricer, (managedToken, denomination)));
    }

    function _addPricingVector(bytes32 pricerId, PricingVector memory vector) internal {
        _diamondCall("addPricingVector", abi.encodeCall(IDiamondProxy.addPricingVector, (pricerId, vector)));
    }

    function _createQuoter(QuoterKind kind, uint64 instanceId) internal {
        _diamondCall("createQuoter", abi.encodeCall(IDiamondProxy.createQuoter, (kind, instanceId)));
    }

    function _configurePropAmm(bytes32 quoterId, address assetToken, address managedToken, PropAmmConfig memory config)
        internal
    {
        _diamondCall(
            "configurePropAmm",
            abi.encodeCall(IDiamondProxy.configurePropAmm, (quoterId, assetToken, managedToken, config))
        );
    }

    function _createConfigurableVault(
        ConfigurableVaultKind kind,
        uint64 instanceId,
        address destination,
        uint16 refillTargetBps
    ) internal {
        _diamondCall(
            "createConfigurableVault",
            abi.encodeCall(IDiamondProxy.createConfigurableVault, (kind, instanceId, destination, refillTargetBps))
        );
    }

    function _createFeeConfig(uint64 instanceId, uint16 basisPoints, uint256 minimumFeeAmount, bytes32 feeVaultId)
        internal
    {
        _diamondCall(
            "createFeeConfig",
            abi.encodeCall(IDiamondProxy.createFeeConfig, (instanceId, basisPoints, minimumFeeAmount, feeVaultId))
        );
    }

    function _makeOfferConfig(MakeOfferConfigParams memory params) internal {
        _diamondCall("makeOfferConfig", abi.encodeCall(IDiamondProxy.makeOfferConfig, (params)));
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

    /// Approves only when needed; reset first for tokens requiring a zero allowance.
    function _ensureApproval(address token, uint256 amount) internal {
        require(token != address(0), "Approval token not set");
        uint256 allowance = IERC20(token).allowance(safe, diamond);
        if (allowance >= amount) return;
        if (allowance != 0) _call(token, "approve", abi.encodeCall(IERC20.approve, (diamond, 0)));
        _call(token, "approve", abi.encodeCall(IERC20.approve, (diamond, amount)));
        require(IERC20(token).allowance(safe, diamond) >= amount, "Token approval not set");
    }
}
