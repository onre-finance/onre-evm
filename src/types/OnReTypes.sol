// SPDX-License-Identifier: MIT
pragma solidity 0.8.35;

enum PricingDenomination {
    Usd
}

enum OfferFlow {
    Permissioned,
    Permissionless,
    Worker
}

enum OfferDirection {
    AssetToOnRe,
    OnReToAsset
}

enum QuoterKind {
    Nav,
    NavPermissionless,
    PropRfq
}

enum ConfigurableVaultKind {
    Fee,
    Proceeds,
    Liquidity
}

struct InitializeParams {
    /// @dev Initial DEFAULT_ADMIN_ROLE holder with full application authority.
    address boss;
    /// @dev Initial ADMIN_ROLE holder; can only enable the kill switch.
    address admin;
    /// @dev Initial WORKER_ROLE holder; can fulfill or administratively cancel requests.
    address worker;
    /// @dev Initial UPGRADER_ROLE holder; can execute Diamond cuts.
    address upgrader;
    address[] approvers;
}

struct OnReTokenConfig {
    address inventorySource;
    bool enabled;
    uint8 decimals;
}

struct PricingVector {
    uint64 startTime;
    uint64 baseTime;
    uint64 basePrice;
    uint64 apr;
    uint64 priceFixDuration;
}

struct Pricer {
    PricingVector[10] vectors;
    address onReToken;
    PricingDenomination denomination;
    uint8 vectorCount;
    bool disabled;
    bool exists;
}

struct Quoter {
    QuoterKind kind;
    uint64 instanceId;
    bool disabled;
    bool exists;
}

struct PropRfqQuoterConfig {
    uint64 epochDurationSeconds;
    uint32 curveExponentScaled;
    uint32 cadenceThreshold;
    uint32 cadenceWaveScaled;
    uint32 wallSensitivityScaled;
    uint16 curvePegHaircutBps;
}

struct PropRfqQuoterState {
    uint256 currentSellValueStable;
    uint256 currentBuyValueStable;
    uint256 previousNetSellValueStable;
    PropRfqQuoterConfig config;
    address onReToken;
    uint64 epochStart;
    uint32 currentSellTradeCount;
    address assetToken;
}

struct FeeConfig {
    bytes32 feeVaultId;
    uint64 feeConfigId;
    uint16 basisPoints;
    bool enabled;
    bool exists;
    uint256 minimumFeeAmount;
}

struct ConfigurableVault {
    ConfigurableVaultKind kind;
    uint64 vaultId;
    address withdrawalDestination;
    uint16 refillTargetBps;
    bool exists;
}

struct OfferConfig {
    address tokenIn;
    OfferFlow flow;
    OfferDirection direction;
    bytes32 quoterId;
    bytes32 feeConfigId;
    bytes32 proceedsVaultId;
    bytes32 liquidityVaultId;
    address tokenOut;
    uint8 tokenOutDecimals;
    uint8 tokenInDecimals;
    bool disabled;
    bool exists;
}

struct MakeOfferConfigParams {
    address tokenIn;
    address tokenOut;
    OfferFlow flow;
    bytes32 quoterId;
    bytes32 feeConfigId;
    bytes32 proceedsVaultId;
    bytes32 liquidityVaultId;
}

struct FulfillmentRequest {
    bytes32 offerConfigId;
    uint256 inputAmount;
    uint256 fulfilledInputAmount;
    uint64 requestId;
    address user;
    bool exists;
}

struct MarketStats {
    uint256 apy;
    uint256 circulatingSupply;
    uint256 nav;
    int256 navAdjustment;
    uint256 tvl;
    uint64 lastUpdatedAt;
    uint64 lastUpdatedBlock;
}

struct ApprovalMessage {
    address user;
    uint64 expiry;
}

struct TakeOfferParams {
    bytes32 offerConfigId;
    uint256 grossInputAmount;
    uint256 minimumAmountOut;
    uint64 deadline;
    ApprovalMessage approval;
    bytes signature;
}

struct QuoteResult {
    uint256 price;
    uint256 amountOut;
}

struct ExecutionAccounting {
    uint256 price;
    uint256 grossInputAmount;
    uint256 feeAmount;
    uint256 netInputAmount;
    uint256 amountOut;
    uint256 liquidityRefillAmount;
    uint256 proceedsAmount;
}
