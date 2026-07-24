// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {OnReTypes} from "../types/OnReTypes.sol";

interface IOnReAppEvents {
    event OnReTokenRegistered(address indexed onReToken, uint8 decimals, uint256 maxSupply, uint256 maxMintAmount);
    event OnReTokenEnabledSet(address indexed onReToken, bool enabled);
    event OnReTokenLimitsUpdated(address indexed onReToken, uint256 maxSupply, uint256 maxMintAmount);
    event ExcludedSupplyAddressAdded(address indexed onReToken, address indexed account);
    event ExcludedSupplyAddressRemoved(address indexed onReToken, address indexed account);

    event PricerCreated(
        bytes32 indexed pricerId, address indexed onReToken, OnReTypes.PricingDenomination denomination
    );
    event PricingVectorAdded(
        bytes32 indexed pricerId,
        uint64 startTime,
        uint64 baseTime,
        uint256 basePrice,
        uint256 apr,
        uint64 priceFixDuration
    );
    event PricingVectorDeleted(bytes32 indexed pricerId, uint64 startTime);
    event PricingVectorEvicted(bytes32 indexed pricerId, uint64 startTime);
    event AllPricingVectorsDeleted(bytes32 indexed pricerId, uint8 vectorsDeletedCount);
    event PricerDisabledSet(bytes32 indexed pricerId, bool disabled);

    event QuoterCreated(bytes32 indexed quoterId, OnReTypes.QuoterKind indexed kind, uint64 indexed instanceId);
    event QuoterDisabledSet(bytes32 indexed quoterId, bool disabled);

    event FeeConfigCreated(
        bytes32 indexed feeConfigId,
        uint64 indexed instanceId,
        uint16 basisPoints,
        uint256 minimumAmount,
        bytes32 feeVaultId
    );
    event FeeConfigUpdated(bytes32 indexed feeConfigId, uint16 basisPoints, uint256 minimumAmount, bytes32 feeVaultId);
    event FeeConfigEnabledSet(bytes32 indexed feeConfigId, bool enabled);

    event OfferConfigCreated(
        bytes32 indexed offerConfigId,
        address indexed tokenIn,
        address indexed tokenOut,
        OnReTypes.OfferFlow flow,
        OnReTypes.OfferDirection direction,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    );
    event OfferConfigReferencesUpdated(
        bytes32 indexed offerConfigId,
        bytes32 quoterId,
        bytes32 feeConfigId,
        bytes32 proceedsVaultId,
        bytes32 liquidityVaultId
    );
    event OfferConfigDisabledSet(bytes32 indexed offerConfigId, bool disabled);
    event OfferExecuted(
        bytes32 indexed offerConfigId,
        address indexed user,
        OnReTypes.OfferFlow indexed flow,
        uint256 grossInputAmount,
        uint256 feeAmount,
        uint256 netInputAmount,
        uint256 amountOut,
        uint256 price,
        uint256 liquidityRefillAmount,
        uint256 proceedsAmount
    );

    event FulfillmentRequested(
        bytes32 indexed fulfillmentRequestId,
        bytes32 indexed offerConfigId,
        address indexed user,
        uint64 requestId,
        uint256 inputAmount
    );
    event FulfillmentRequestCancelled(
        bytes32 indexed fulfillmentRequestId,
        bytes32 indexed offerConfigId,
        address indexed user,
        uint256 returnedAmount,
        address cancelledBy
    );
    event FulfillmentRequestFilled(
        bytes32 indexed fulfillmentRequestId,
        bytes32 indexed offerConfigId,
        address indexed user,
        uint256 fulfilledInputAmount,
        uint256 totalFulfilledInputAmount,
        uint256 feeAmount,
        uint256 amountOut,
        uint256 price,
        bool fullyFulfilled
    );

    event ConfigurableVaultCreated(
        bytes32 indexed vaultId,
        OnReTypes.ConfigurableVaultKind indexed kind,
        uint64 indexed instanceId,
        address withdrawalDestination,
        uint16 refillTargetBps
    );
    event ConfigurableVaultUpdated(bytes32 indexed vaultId, address withdrawalDestination, uint16 refillTargetBps);
    event ConfigurableVaultAccrued(bytes32 indexed vaultId, address indexed token, uint256 amount, uint256 newBalance);
    event ConfigurableVaultWithdrawn(
        bytes32 indexed vaultId, address indexed token, address indexed destination, uint256 amount
    );

    event MintGatewayUpdated(address indexed oldMintGateway, address indexed newMintGateway);
    event ApproverAdded(address indexed approver);
    event ApproverRemoved(address indexed approver);
    event KillSwitchSet(bool isKilled);
}
