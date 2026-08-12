// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

import {ConfigurableVaultKind, OfferDirection, OfferFlow, PricingDenomination, QuoterKind} from "./OnReTypes.sol";

event OnReTokenRegistered(address indexed onReToken, address indexed inventorySource, uint8 decimals);
event OnReTokenEnabledSet(address indexed onReToken, bool enabled);
event OnReTokenInventorySourceUpdated(
    address indexed onReToken, address indexed oldInventorySource, address indexed newInventorySource
);
event ExcludedSupplyAddressAdded(address indexed onReToken, address indexed account);
event ExcludedSupplyAddressRemoved(address indexed onReToken, address indexed account);

event PricerCreated(bytes32 indexed pricerId, address indexed onReToken, PricingDenomination denomination);
event PricingVectorAdded(
    bytes32 indexed pricerId, uint64 startTime, uint64 baseTime, uint256 basePrice, uint256 apr, uint64 priceFixDuration
);
event PricingVectorDeleted(bytes32 indexed pricerId, uint64 startTime);
event PricingVectorEvicted(bytes32 indexed pricerId, uint64 startTime);
event AllPricingVectorsDeleted(bytes32 indexed pricerId, uint8 vectorsDeletedCount);
event PricerEnabledSet(bytes32 indexed pricerId, bool enabled);

event QuoterCreated(bytes32 indexed quoterId, QuoterKind indexed kind, uint64 indexed instanceId);
event QuoterEnabledSet(bytes32 indexed quoterId, bool enabled);
event PropRfqQuoterConfigured(
    bytes32 indexed quoterId,
    address indexed assetToken,
    address indexed onReToken,
    uint16 curvePegHaircutBps,
    uint32 curveExponentScaled,
    uint32 cadenceThreshold,
    uint32 cadenceWaveScaled,
    uint64 epochDurationSeconds,
    uint32 wallSensitivityScaled,
    uint256 minimumSellHaircutOnRe
);

event FeeConfigCreated(bytes32 indexed feeConfigId, uint64 indexed instanceId, uint16 basisPoints, bytes32 feeVaultId);
event FeeConfigUpdated(bytes32 indexed feeConfigId, uint16 basisPoints, bytes32 feeVaultId);
event FeeConfigEnabledSet(bytes32 indexed feeConfigId, bool enabled);

event OfferConfigCreated(
    bytes32 indexed offerConfigId,
    address indexed tokenIn,
    address indexed tokenOut,
    OfferFlow flow,
    OfferDirection direction,
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
event OfferConfigEnabledSet(bytes32 indexed offerConfigId, bool enabled);
event OfferExecuted(
    bytes32 indexed offerConfigId,
    address indexed user,
    OfferFlow indexed flow,
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
    ConfigurableVaultKind indexed kind,
    uint64 indexed instanceId,
    address withdrawalDestination,
    uint16 refillTargetBps
);
event ConfigurableVaultUpdated(bytes32 indexed vaultId, address withdrawalDestination, uint16 refillTargetBps);
event ConfigurableVaultAccrued(bytes32 indexed vaultId, address indexed token, uint256 amount, uint256 newBalance);
event ConfigurableVaultWithdrawn(
    bytes32 indexed vaultId, address indexed token, address indexed destination, uint256 amount
);

event ApproverAdded(address indexed approver);
event ApproverRemoved(address indexed approver);
event KillSwitchSet(bool isKilled);

event BossTransferStarted(address indexed currentBoss, address indexed pendingBoss);
event BossTransferCancelled(address indexed currentBoss, address indexed cancelledPendingBoss);
event BossTransferred(address indexed previousBoss, address indexed newBoss);
