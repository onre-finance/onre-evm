# EVM application architecture

The EVM application is an EIP-2535 Diamond. `OnReDiamond` is the permanent
address used by token inventory multisigs, users, and integrations. Its fallback
delegates each function selector to an installed facet.

The offer domain is documented in
[`docs/OFFER_ARCHITECTURE.md`](OFFER_ARCHITECTURE.md), including the
Mermaid graph, deterministic IDs, compatibility matrix, and settlement rules.

The diamond core lives in `src/diamond/contracts/`. That `contracts/`
subdirectory is not decoration: Gemforge resolves the diamond library it
generates against, so the layout has to match what its templates import. See
[`docs/DEPLOYMENT.md`](DEPLOYMENT.md).

## Facets

- `DiamondCutFacet` performs atomic add, replace, and remove upgrades.
- `DiamondLoupeFacet` exposes selector-to-facet discovery and ERC-165 support.
- `OnReAccessControlFacet` exposes the OpenZeppelin `IAccessControl` role API.
- `OnReConfigFacet` implements token and application administration.
- `OnRePricerFacet` implements the reusable USD Pricer and pricing vectors.
- `OnReQuoterFacet` implements reusable `Nav`, `NavPermissionless`, and
  pair-bound stateful `PropRfq` dispatch. Every quoter kind uses the same
  creation entrypoint; kind-specific state is applied through typed
  configuration functions.
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
- `LibOnRePropRfq` owns proprietary request-for-quote (Prop RFQ) configuration
  validation, rolling buy/sell pressure, the dynamic liquidity wall, and
  curve/cadence sell dampening.
- `LibOnReApproval` owns EIP-712 approval verification.
- `LibOnReOffer` owns direct and worker settlement against validated
  configuration.
- `OnReMath` owns shared pure arithmetic; domain libraries add policy around
  those calculations rather than duplicating the formulas.

Each application facet declares its own external ABI. There is no hand-written
domain interface layer: Gemforge parses the facet sources and generates
`src/generated/IDiamondProxy.sol`, the aggregate client interface, from them.
That interface is regenerated on every `gemforge build`, so it cannot drift from
the deployed selector set.

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

Fresh deployment is two transactions: `DiamondProxy`'s constructor installs
`DiamondCutFacet` and `DiamondLoupeFacet`, then a single cut installs every
application facet and calls `OnReDiamondInit.init`. The runtime Diamond does not
expose a reusable initializer. Every later cut should include an initializer
when storage migration or invariant restoration is required.

The proxy constructor grants `UPGRADER_ROLE` to its deployer so that first cut
can be signed; `OnReDiamondInit.init` revokes that grant once the configured
upgrader holds the role, unless the deployer is the configured upgrader.

Diamond cuts require `UPGRADER_ROLE`; there is no separate Diamond-owner
authority. Production may assign that role to the boss or to a dedicated
multisig.
Application roles are:

- `DEFAULT_ADMIN_ROLE`: boss authority over role administration, token
  inventory, Pricers, Quoters, FeeConfigs, OfferConfigs, ConfigurableVaults,
  approvers, and both kill-switch activation and recovery. Exactly one account
  holds this role.
- `ADMIN_ROLE`: may only activate the kill switch. It cannot recover the
  application or perform configuration.
- `WORKER_ROLE`: partial fulfillment and worker-authorized request cancellation.
- `UPGRADER_ROLE`: may execute Diamond cuts. The boss may also hold this role.

Initialization takes boss, admin, worker, and upgrader addresses; role holders
may overlap. The boss starts a transfer and the pending boss must accept it;
acceptance atomically revokes the previous boss before granting the role to the
new boss. The standard `grantRole`, `revokeRole`, and `renounceRole` functions
cannot modify `DEFAULT_ADMIN_ROLE`. They remain available for `ADMIN_ROLE`,
`WORKER_ROLE`, and `UPGRADER_ROLE`. Request owners retain the ability to cancel
their own requests.

## Vault boundary

The Diamond has three reusable vault kinds: `Fee`, `Proceeds`, and `Liquidity`.
Each vault instance has one fixed withdrawal destination and an independent
logical balance per ERC-20 token. Tokens remain physically held by the Diamond.

Anyone may deposit or trigger withdrawal. Withdrawal can only send to the
configured destination, amount zero means the full logical balance, and
fee-on-transfer assets are rejected by exact balance accounting.

Buffer remains out of scope. Prop RFQ is implemented as a quoter kind rather
than a separate facet. Each instance is bound to one asset/OnRe pair, stores its
own configuration and rolling pressure, and can be shared by both directed
permissionless OfferConfigs for that pair.

## OnRe token inventory

Each registered OnRe token has a configured inventory-source address. Production
uses a multisig holding pre-minted inventory. The multisig grants the Diamond a
maximum ERC-20 allowance, and successful `AssetToOnRe` settlement transfers the
quoted output directly from that multisig to the user. The Diamond never receives
mint authority and there is no mint-gateway contract.

Inventory held by the configured source is excluded from circulating supply.
Operational vault assets remain physically held by the Diamond.

## Deployment

Deployments and upgrades run through [Gemforge](https://gemforge.xyz), driven by
`gemforge.config.cjs`. `gemforge build` regenerates `src/generated/`, and
`gemforge deploy <target>` diffs the compiled facet ABIs against the on-chain
loupe and applies exactly the cuts that differ. Full workflow, environment
variables, and the multisig upgrade path:
[`docs/DEPLOYMENT.md`](DEPLOYMENT.md).

Because cuts are derived from the facet ABIs, there is no selector manifest and
no domain-interface layer to keep in sync. `src/generated/IDiamondProxy.sol` is
the interface clients, integrations and tests bind to.

Pricers, Quoters, FeeConfigs, vaults, and OfferConfigs are explicit
post-deployment configuration transactions.

ERC-165 advertises only interfaces with a stable, standardised id: `IERC165`,
`IDiamondCut`, `IDiamondLoupe` and OpenZeppelin's `IAccessControl`. The
application ABI — including the boss-transfer surface — is discovered through
the loupe. A stored ERC-165 flag is a static bool and cannot track a selector
set that a cut is free to change, so advertising a bespoke application id would
be a claim the diamond cannot keep.
