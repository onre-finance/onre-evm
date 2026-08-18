// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ConfigurableVaultKind, OfferFlow, PricingDenomination, QuoterKind} from "../types/OnReTypes.sol";

library OnReIds {
    uint64 internal constant BUFFER_RESERVE_VAULT_INSTANCE_ID = 0;
    uint64 internal constant BUFFER_MANAGEMENT_FEE_VAULT_INSTANCE_ID = 1;
    uint64 internal constant BUFFER_PERFORMANCE_FEE_VAULT_INSTANCE_ID = 2;

    bytes32 internal constant BUFFER_RESERVE_VAULT_SEED = keccak256("onre.buffer_reserve_vault");
    bytes32 internal constant BUFFER_MANAGEMENT_FEE_VAULT_SEED = keccak256("onre.buffer_management_fee_vault");
    bytes32 internal constant BUFFER_PERFORMANCE_FEE_VAULT_SEED = keccak256("onre.buffer_performance_fee_vault");
    bytes32 internal constant PRICER_SEED = keccak256("onre.pricer");
    bytes32 internal constant QUOTER_SEED = keccak256("onre.quoter");
    bytes32 internal constant FEE_CONFIG_SEED = keccak256("onre.fee_config");
    bytes32 internal constant CONFIGURABLE_VAULT_SEED = keccak256("onre.configurable_vault");
    bytes32 internal constant OFFER_CONFIG_SEED = keccak256("onre.offer_config");
    bytes32 internal constant FULFILLMENT_REQUEST_SEED = keccak256("onre.fulfillment_request");

    function _pricerId(address onReToken, PricingDenomination denomination) internal pure returns (bytes32) {
        return keccak256(abi.encode(PRICER_SEED, onReToken, denomination));
    }

    function _usdPricerId(address onReToken) internal pure returns (bytes32) {
        return _pricerId(onReToken, PricingDenomination.Usd);
    }

    function _quoterId(QuoterKind kind, uint64 quoterId_) internal pure returns (bytes32) {
        return keccak256(abi.encode(QUOTER_SEED, kind, quoterId_));
    }

    function _feeConfigId(uint64 feeConfigId_) internal pure returns (bytes32) {
        return keccak256(abi.encode(FEE_CONFIG_SEED, feeConfigId_));
    }

    function _configurableVaultId(ConfigurableVaultKind kind, uint64 vaultId_) internal pure returns (bytes32) {
        return keccak256(abi.encode(CONFIGURABLE_VAULT_SEED, kind, vaultId_));
    }

    function _bufferReserveVaultId(address onReToken) internal pure returns (bytes32) {
        return keccak256(abi.encode(BUFFER_RESERVE_VAULT_SEED, onReToken));
    }

    function _bufferManagementFeeVaultId(address onReToken) internal pure returns (bytes32) {
        return keccak256(abi.encode(BUFFER_MANAGEMENT_FEE_VAULT_SEED, onReToken));
    }

    function _bufferPerformanceFeeVaultId(address onReToken) internal pure returns (bytes32) {
        return keccak256(abi.encode(BUFFER_PERFORMANCE_FEE_VAULT_SEED, onReToken));
    }

    function _offerConfigId(address tokenIn, address tokenOut, OfferFlow flow) internal pure returns (bytes32) {
        return keccak256(abi.encode(OFFER_CONFIG_SEED, tokenIn, tokenOut, flow));
    }

    function _fulfillmentRequestId(bytes32 offerConfigId_, address user, uint64 requestId)
        internal
        pure
        returns (bytes32)
    {
        return keccak256(abi.encode(FULFILLMENT_REQUEST_SEED, offerConfigId_, user, requestId));
    }
}
