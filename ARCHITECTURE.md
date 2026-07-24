# EVM application architecture

The EVM application is an EIP-2535 Diamond. `OnReDiamond` is the permanent
address used by tokens, the mint gateway, users, and integrations. Its fallback
delegates each function selector to an installed facet.

The offer domain is documented in
[`docs/OFFER_ARCHITECTURE.md`](docs/OFFER_ARCHITECTURE.md), including the
Mermaid graph, deterministic IDs, compatibility matrix, and settlement rules.

## Facets

- `DiamondCutFacet` performs atomic add, replace, and remove upgrades.
- `DiamondLoupeFacet` exposes selector-to-facet discovery and ERC-165 support.
- `DiamondOwnershipFacet` controls the upgrade owner.
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
- `OnReMarketStatsFacet` derives APY, NAV, circulating supply, and TVL from the
  canonical USD Pricer.

Facets are thin external ABI adapters. Domain behavior lives in internal
libraries so Solidity inlines reachable logic without an `address(this)`
cross-facet call.

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

The upgrade owner is separate from application roles. Production ownership
should be a timelocked multisig. Application roles are:

- `DEFAULT_ADMIN_ROLE`: grants and revokes application roles.
- `CONFIG_ADMIN_ROLE`: token, Pricer, Quoter, FeeConfig, OfferConfig, approver,
  and mint-gateway configuration.
- `WORKER_ROLE`: partial fulfillment and worker-authorized cancellation.
- `VAULT_ADMIN_ROLE`: ConfigurableVault creation and configuration.
- `PAUSER_ROLE`: kill-switch changes.

The initial application admin receives all roles. The initial worker receives
only `WORKER_ROLE`. Diamond ownership transfers do not transfer application
roles.

## Vault boundary

The Diamond has three reusable vault kinds: `Fee`, `Proceeds`, and `Liquidity`.
Each vault instance has one fixed withdrawal destination and an independent
logical balance per ERC-20 token. Tokens remain physically held by the Diamond.

Anyone may deposit or trigger withdrawal. Withdrawal can only send to the
configured destination, amount zero means the full logical balance, and
fee-on-transfer assets are rejected by exact balance accounting.

Buffer and Prop AMM are out of scope. They have no facets, storage, enum
variants, or deployment configuration in this implementation.

## Deployment

`script/DeployOnReDiamond.s.sol` reads:

- `PRIVATE_KEY`;
- optional `ONRE_DIAMOND_OWNER`, defaulting to `ONRE_ADMIN`;
- `ONRE_ADMIN`;
- `ONRE_WORKER`;
- optional `ONRE_APPROVER_1`;
- optional `ONRE_APPROVER_2`.

Pricers, Quoters, FeeConfigs, vaults, and OfferConfigs are explicit
post-deployment configuration transactions.

`LibOnReSelectors` is the canonical fresh-deployment selector manifest. ERC-165
advertises only stable Diamond, ownership, and access-control interfaces. The
mutable application ABI is discovered through the loupe.
