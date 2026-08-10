// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ConfigurableVaultKind, OfferFlow, PricingDenomination, QuoterKind} from "../types/OnReTypes.sol";

library OnReIds {
    bytes32 internal constant PRICER_SEED = keccak256("onre.pricer");
    bytes32 internal constant QUOTER_SEED = keccak256("onre.quoter");
    bytes32 internal constant FEE_CONFIG_SEED = keccak256("onre.fee_config");
    bytes32 internal constant CONFIGURABLE_VAULT_SEED = keccak256("onre.configurable_vault");
    bytes32 internal constant OFFER_CONFIG_SEED = keccak256("onre.offer_config");
    bytes32 internal constant FULFILLMENT_REQUEST_SEED = keccak256("onre.fulfillment_request");

    function pricerId(address onReToken, PricingDenomination denomination) internal pure returns (bytes32) {
        return keccak256(abi.encode(PRICER_SEED, onReToken, denomination));
    }

    function usdPricerId(address onReToken) internal pure returns (bytes32) {
        return pricerId(onReToken, PricingDenomination.Usd);
    }

    function quoterId(QuoterKind kind, uint64 quoterId_) internal pure returns (bytes32) {
        return keccak256(abi.encode(QUOTER_SEED, kind, quoterId_));
    }

    function feeConfigId(uint64 feeConfigId_) internal pure returns (bytes32) {
        return keccak256(abi.encode(FEE_CONFIG_SEED, feeConfigId_));
    }

    function configurableVaultId(ConfigurableVaultKind kind, uint64 vaultId_) internal pure returns (bytes32) {
        return keccak256(abi.encode(CONFIGURABLE_VAULT_SEED, kind, vaultId_));
    }

    function offerConfigId(address tokenIn, address tokenOut, OfferFlow flow) internal pure returns (bytes32) {
        return keccak256(abi.encode(OFFER_CONFIG_SEED, tokenIn, tokenOut, flow));
    }

    function fulfillmentRequestId(bytes32 offerConfigId_, address user, uint64 requestId)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(FULFILLMENT_REQUEST_SEED, offerConfigId_, user, requestId));
    }
}
