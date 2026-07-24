# EVM application architecture

The EVM application is an EIP-2535 Diamond. `OnReDiamond` is the permanent
address used by token inventory multisigs, users, and integrations. Its fallback
delegates each function selector to an installed facet.

The offer domain is documented in
[`docs/OFFER_ARCHITECTURE.md`](docs/OFFER_ARCHITECTURE.md), including the
Mermaid graph, deterministic IDs, compatibility matrix, and settlement rules.

## Facets

- `DiamondCutFacet` performs atomic add, replace, and remove upgrades.
- `DiamondLoupeFacet` exposes selector-to-facet discovery and ERC-165 support.
- `OnReAccessControlFacet` exposes the OpenZeppelin `IAccessControl` role API.
- `OnReConfigFacet` implements token and application administration.
- `OnRePricerFacet` implements the reusable USD Pricer and pricing vectors.
- `OnReQuoterFacet` implements reusable `Nav` and `NavPermissionless` dispatch.
- `OnReOfferFacet` implements FeeConfigs, OfferConfigs, and flow-dispatched
  `takeOffer` execution.
- `OnReFulfillmentFacet` implements escrowed worker requests and partial fills.
- `OnReConfigurableVaultFacet` implements reusable Fee, Proceeds, and Liquidity
  vault instances.
- `OnReViewFacet` exposes application and domain records.
- `OnReMarketStatsFacet` derives APY and NAV from the canonical USD Pricer,
  derives circulating supply from token balances, and combines them into TVL.

Facets are thin external ABI adapters. Domain behavior lives in internal
libraries so Solidity inlines reachable logic without an `address(this)`
cross-facet call.

The internal libraries follow the same responsibility boundaries:

- `LibOnRePricer` owns pricing-vector lifecycle and USD price production only.
- `LibOnReMarketStats` owns circulating supply, TVL, APY, and NAV-adjustment
  derivation. Offer settlement uses its canonical TVL calculation for
  liquidity-vault refill targets.
- `LibOnReConfig` owns OnRe-token and supply-exclusion configuration, while
  `LibOnReAppConfig` owns approvers and emergency control.
- `LibOnReFeeConfig` owns reusable fee policy and fee calculation.
- `LibOnReOfferConfig` owns pair-and-flow configuration and reference
  validation.
- `LibOnReApproval` owns EIP-712 approval verification.
- `LibOnReOffer` owns direct and worker settlement against validated
  configuration.
- `OnReMath` owns shared pure arithmetic; domain libraries add policy around
  those calculations rather than duplicating the formulas.

Each application facet explicitly implements its matching domain interface
(`IOnReConfig`, `IOnRePricer`, `IOnReQuoter`, and so on). This makes Solidity
check the facet ABI against the selector source at compile time. `IOnReApp`
only aggregates those domain interfaces for clients and integrations; it does
not duplicate their function declarations.

Each registered OnRe token has exactly one deterministic USD Pricer. Offers and
MarketStats derive that Pricer from the OnRe token address; there is no mutable
main-Pricer pointer or per-offer Pricer reference.

## Storage and upgrades

Diamond selector tables, OnRe application state, and application roles use
separate ERC-7201 namespaces. Facets must access shared state through the
corresponding storage library; they must not declare ordinary state variables.

This layout targets a fresh, not-yet-deployed Diamond. It is a breaking storage
and ABI replacement for the earlier combined offer/redemption prototype. Do not
install it over that prototype without a purpose-built migration initializer.

Fresh deployment installs every initial selector and calls
`OnReDiamondInit.init` in the same transaction. The runtime Diamond does not
expose a reusable initializer. Every later cut should include an initializer
when storage migration or invariant restoration is required.

Diamond cuts require `UPGRADER_ROLE`; there is no separate Diamond-owner
authority. Production should assign that role to a dedicated multisig.
Application roles are:

- `DEFAULT_ADMIN_ROLE`: boss authority over role administration, token
  inventory, Pricers, Quoters, FeeConfigs, OfferConfigs, ConfigurableVaults,
  approvers, and both kill-switch activation and recovery. Exactly one account
  holds this role.
- `ADMIN_ROLE`: may only activate the kill switch. It cannot recover the
  application or perform configuration.
- `WORKER_ROLE`: partial fulfillment and worker-authorized request cancellation.
- `UPGRADER_ROLE`: may execute Diamond cuts. The boss cannot hold this role.

Initialization takes separate boss, admin, worker, and upgrader addresses. The
boss starts a transfer and the pending boss must accept it; acceptance
atomically revokes the previous boss before granting the role to the new boss.
The standard `grantRole`, `revokeRole`, and `renounceRole` functions cannot
modify `DEFAULT_ADMIN_ROLE`. They remain available for `ADMIN_ROLE`,
`WORKER_ROLE`, and `UPGRADER_ROLE`. A current or pending boss cannot receive
`UPGRADER_ROLE`, and an upgrader cannot accept a boss nomination without first
losing the upgrader role. Request owners retain the ability to cancel their own
requests.

## Vault boundary

The Diamond has three reusable vault kinds: `Fee`, `Proceeds`, and `Liquidity`.
Each vault instance has one fixed withdrawal destination and an independent
logical balance per ERC-20 token. Tokens remain physically held by the Diamond.

Anyone may deposit or trigger withdrawal. Withdrawal can only send to the
configured destination, amount zero means the full logical balance, and
fee-on-transfer assets are rejected by exact balance accounting.

Buffer and Prop AMM are out of scope. They have no facets, storage, enum
variants, or deployment configuration in this implementation.

## OnRe token inventory

Each registered OnRe token has a configured inventory-source address. Production
uses a multisig holding pre-minted inventory. The multisig grants the Diamond a
maximum ERC-20 allowance, and successful `AssetToOnRe` settlement transfers the
quoted output directly from that multisig to the user. The Diamond never receives
mint authority and there is no mint-gateway contract.

Inventory held by the configured source is excluded from circulating supply.
Operational vault assets remain physically held by the Diamond.

## Deployment

`script/DeployOnReDiamond.s.sol` reads:

- `PRIVATE_KEY`;
- `ONRE_BOSS`;
- `ONRE_ADMIN`;
- `ONRE_WORKER`;
- `ONRE_UPGRADER`;
- optional `ONRE_APPROVER_1`;
- optional `ONRE_APPROVER_2`.

Pricers, Quoters, FeeConfigs, vaults, and OfferConfigs are explicit
post-deployment configuration transactions.

`LibOnReSelectors` is the canonical fresh-deployment selector manifest. It
derives each facet's selectors from that facet's domain interface, not from the
aggregate `IOnReApp`. ERC-165 advertises only stable Diamond and access-control
interfaces. The mutable application ABI is discovered through the loupe.
