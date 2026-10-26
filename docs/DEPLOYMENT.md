# Deploying and upgrading the OnRe Diamond

Deployments and upgrades run through [Gemforge](https://gemforge.xyz). Gemforge
diffs the compiled facet ABIs against the on-chain loupe and applies exactly the
cuts that differ, so there is no hand-written deployment script to keep in sync
with the facet set.

## Configured offers

`script/config/<ONRE_ENV>.json` defines named `pricers`, `quoters`, `vaults`,
`feeConfigs`, and `offers`. Each offer explicitly specifies its `managedToken`,
`assetToken`, `direction`, `flow`, `enabled`, and references to its components. Names are
configuration references; contract IDs are still derived by `OnReIds`.

- Pricers specify a managed token, `denomination: "usd"`, vector, and activation delay.
- Quoters specify `kind` (`nav`, `navPermissionless`, or `propAmm`) and `instanceId`.
  Prop AMM definitions also specify their exact managed/asset pair and `config`.
- Vaults specify `kind` (`fee`, `proceeds`, `liquidity`, or `bufferReserve`),
  `instanceId`, `withdrawalDestination`, and `refillTargetBps`.
- Fee configs specify `instanceId`, `basisPoints`, `minimumFeeAmount`, and their
  named `feeVault`. Different offers can reference different fee configs and quoters.
- Offers specify `direction` (`assetToManaged` or `managedToAsset`) and `flow`
  (`permissionless`, `permissioned`, or `worker`). `liquidityVault: "none"` encodes
  a zero liquidity-vault reference. Sells require a named liquidity-kind vault.
  Each offer requires an explicit `enabled` boolean; setup reconciles that state on-chain.

A named pricer reference must match the offer's managed token and its on-chain USD
pricer identity: the contracts derive this binding rather than storing a separate
pricer ID in each offer. Permissioned and worker offers require a `nav` quoter;
worker offers must use `managedToAsset`. Permissionless offers use
`navPermissionless` or a pair-matching `propAmm` quoter. Repeated component IDs and
repeated directed token-pair/flow identities are rejected, even under different
configuration names. Separate quoter/fee instances need separate instance IDs.

Production (`ethereum-mainnet-live`) contains two permissionless NAV buy offers using
native Ethereum [USDC](https://developers.circle.com/stablecoins/usdc-contract-addresses)
and [USDG](https://docs.paxos.com/guides/stablecoin/usdg/mainnet). They reference the
same `onyc-usd` pricer, `nav-permissionless` quoter, `buy-fee` config, and `proceeds`
vault. These references are independent per offer and can be changed separately.
Both buys use `liquidityVault: "none"`; proceeds/fees are accounted per token.

Production also defines `onyc-to-usdg-prop`: a permissionless `managedToAsset`
offer referencing `onyc-usd`, its own `usdg-prop-amm` quoter, a new `usdg-prop-fee`
config at 30 bps, a new `usdg-prop-proceeds` vault, and `usdg-liquidity`. The fee is
charged in ONyc. The liquidity vault has refill target zero, so it must be funded
explicitly; no automatic refill is configured. The Prop AMM parameters are the
values from the existing sell script: 300-second epochs, curve exponent 19000,
cadence threshold 20, cadence wave 2000, wall sensitivity 20000, and peg haircut
3650. Sell input is burned after its fee, USDG is paid from liquidity, and sell
pressure is recorded in this separate quoter instance.

All three production offers currently have `"enabled": false` in their individual
entries under `offers`. Base Sepolia and mainnet-test offers remain enabled.
Setup disables existing active offers when configured false, and enables existing
disabled offers only when explicitly configured true. Missing offers are created
and then disabled: the current contract always creates offers enabled. **Execute
all prepared creation and disable calls in one atomic Safe MultiSend batch** so
new offers cannot be traded between creation and disabling. Separate transactions
would leave a temporary active window.

`DisableOffer.s.sol` takes an on-chain offer ID and prepares
`setOfferConfigEnabled(offerId, false)` if needed. It does not edit the JSON.
Keep `enabled: false` there to preserve the disabled state on subsequent setup runs.

The pricing baseline matches both Solana production offers observed at slot
461251574: `baseTime=1789776000`, `basePrice=1146935367`, `apr=104555`, and
`priceFixDuration=86400`. EVM rejects historical activation times. A pricer's
`vector.startTime=0` prepares activation at simulation time plus
`activationDelaySeconds` (currently 3600), preserving the Solana baseline.
Execute the Safe batch before the printed activation timestamp; offers configured
as enabled become executable at that time. Regenerate unexecuted batches if their activation passes.

```bash
ONRE_ENV=ethereum-mainnet-live forge script script/SetupOffers.s.sol --rpc-url "$ETH_MAINNET_RPC_URL"
ONRE_ENV=ethereum-mainnet-live forge script script/ApproveSettlementTokens.s.sol --rpc-url "$ETH_MAINNET_RPC_URL"
```

Setup creates missing components in dependency order, reuses matching components,
and updates existing offer references and enabled states to match the configuration.
It does not rewrite shared pricing/fee policies. A matching completed setup emits
no new calls. The legacy buy, permissioned-buy, and Prop AMM sell script names
select matching flow/direction/quoter definitions from this same configuration.
The allowance script approves the Diamond for both tokens of each configured
permissionless offer, skipping maximum allowances and permissioned/worker offers.
Execute setup calls from the admin Safe and allowance calls from the settlement
Safe. Neither script broadcasts. There are no top-level token defaults: the
token pair comes from each offer, and the pricer/quoter pair bindings are explicit.

To fund the configured USDG liquidity vault, use its offer name and an amount in
USDG base units (the example is 10,000 USDG with six decimals):

```bash
ONRE_ENV=ethereum-mainnet-live forge script script/DepositLiquidityVault.s.sol --sig "run(string,uint256)" "onyc-to-usdg-prop" 10000000000 --rpc-url "$ETH_MAINNET_RPC_URL"
```

The deposit script reads that offer's asset token and named liquidity vault,
checks the live offer's vault reference, requires the admin Safe to already hold
the funds, and prints any needed approval followed by the deposit call. It does
not mint tokens, and funding is separate from offer creation.

```bash
pnpm test:buy-offers:anvil
```

This runs setup and allowance scripts against a disposable production fork,
applies their calls through local Safe impersonation, checks the configured enabled
states and rejected trades for disabled offers, then temporarily enables them only
on Anvil for trading and withdrawal tests. It advances to vector activation, funds a local user from forked holders, and takes both production buy
offers. It also funds the admin Safe locally, runs the named liquidity deposit
script, and sells 100 ONyc through the USDG Prop AMM offer. It verifies per-offer
references, minimum output, fees, separate proceeds, liquidity debits, recorded
sell pressure, unchanged settlement balances, and repeat setup. It also exercises
the legacy buy/sell entry points, token deployment, settlement updates, and disabling
an offer, including repeat calls. It restores the configured disabled states through
setup before verifying that a repeat setup emits no calls. Evidence is saved
under `.ignore/buy-offers-anvil/`. No mainnet transactions are sent. Override the
fork provider with `ETH_MAINNET_RPC_URL`; `USDC_HOLDER`/`USDG_HOLDER` select fork-only
funding donors when automatic discovery is unavailable.

The remaining operations use the same Safe simulation and calldata output:

```bash
ONRE_ENV=ethereum-mainnet-live forge script script/SetSettlementAccount.s.sol --rpc-url "$ETH_MAINNET_RPC_URL"
ONRE_ENV=ethereum-mainnet-live forge script script/DisableOffer.s.sol --sig "run(bytes32)" <offerId> --rpc-url "$ETH_MAINNET_RPC_URL"
ONRE_ENV=ethereum-mainnet-test forge script script/DeployManagedToken.s.sol --sig "run(string,string,uint8,bytes32)" "Test Token" "TEST" 9 0x0000000000000000000000000000000000000000000000000000000000000001 --rpc-url "$ETH_MAINNET_RPC_URL"
```

Settlement updates and disabling an offer emit no calls when already applied.
Token deployment accepts metadata and the implementation's CREATE2 salt as arguments;
choose an unused salt. It prints the implementation deployment and Diamond token
creation calls for the configured admin Safe. The simulated token address depends
on the Diamond nonce when the batch executes.

## Quick start

```bash
cd evm
pnpm install --frozen-lockfile
cp .env.example .env         # fill in the values

pnpm build                   # regenerates src/generated, then runs forge build
forge test

anvil &                      # in another shell
pnpm deploy:local
```

## Deployment wallet

The `testnet` and `mainnet` targets sign with an encrypted Foundry keystore
rather than a plaintext key in `.env`:

```bash
cast wallet import deployer --interactive   # once: paste the key, choose a password
pnpm gemforge deploy testnet                # prompts for the keystore password
```

Set `ONRE_DEPLOYER_ACCOUNT` to use a keystore with another name. For CI, set
`CAST_UNSAFE_PASSWORD` to skip the prompt. `PRIVATE_KEY`, if set, bypasses the
keystore. Do not run a real deploy with `-v`: its trace output prints the
decrypted key. Dry runs (`--dry`) sign with a throwaway key instead, so they
need no password and are safe to run verbosely.

## Commands

| Command | What it does |
| --- | --- |
| `gemforge build` | Writes `src/generated/`, then runs `commands.build` (`forge build --sizes src`) |
| `gemforge deploy <target>` | Deploys a new diamond, or upgrades an existing one |
| `gemforge deploy <target> --dry` | Prints the cuts without sending anything (`pnpm deploy:testnet:dry` adds `-v` for per-selector detail) |
| `gemforge deploy <target> --new` | Forces a fresh diamond at a new address |
| `gemforge query <target>` | Lists on-chain facets and selectors, flagging unrecognized ones |
| `gemforge verify <target>` | Verifies the diamond and its facets on the block explorer |

Targets are `local`, `testnet` (Base Sepolia) and `mainnet`, defined in
`gemforge.config.cjs`.

`gemforge build` must run before `forge test`: the test helper deploys through
`src/generated/DiamondProxy.sol` and `src/generated/LibDiamondHelper.sol`, which
are generated and git-ignored. `pnpm test` does both in order.

## What a fresh deployment does

1. Deploys `DiamondProxy` through Gemforge's CREATE3 factory. The address is
   derived from `(deployer, ONRE_CREATE3_SALT)`, so the same pair produces the
   same diamond address on every chain.
2. The proxy constructor installs `DiamondCutFacet` and `DiamondLoupeFacet`,
   registers the ERC-165 ids, and grants `UPGRADER_ROLE` to the deployment
   wallet so it can sign the next step.
3. Deploys the eleven application facets and `OnReDiamondInit`.
4. Sends one `diamondCut` that adds every application selector and delegatecalls
   `OnReDiamondInit.init` with `initArgs`.
5. `init` seeds boss/admin/worker/upgrader and the approvers, then revokes the deployer's
   bootstrap `UPGRADER_ROLE` — unless the deployer *is* `ONRE_UPGRADER`.

Step 5 is the one to keep in mind: **after a fresh deployment, the deployment
wallet can no longer upgrade the diamond** unless it was named as
`ONRE_UPGRADER`. For local and testnet iteration, set `ONRE_UPGRADER` to the
deployment wallet. For mainnet, set it to the upgrade multisig.

## Registering a managed token

Managed tokens are issued and redeemed by the Diamond; they are not pre-minted.
Deploy and verify a `ManagedToken` implementation before deploying its first
proxy. The Diamond does not store a default implementation address.

After verifying the Diamond, connect the application boss through the block
explorer's **Write Contract** page and call `deployManagedToken` with the
previously deployed implementation address, name, symbol, decimals, token
administrator, CCIP administrator, and any additional initial minters and
burners. The facet validates the implementation, atomically deploys and
initializes an `ERC1967Proxy`, grants the Diamond mint and burn authority,
registers the token, records it in the Diamond's deployment registry, and emits
`ManagedTokenDeployed`. No per-token proxy bytecode, initializer transaction,
role-grant transaction, or registration transaction is required.

Each managed token upgrades independently. Its token administrator calls
`upgradeToAndCall(newImplementation, data)` on that token proxy. Other managed
tokens remain on their current implementations. For a later factory deployment,
the application boss supplies whichever verified implementation that new proxy
should use directly to `deployManagedToken`.

For an externally deployed compatible token, its token administrator must call
`grantMintAndBurnRoles(diamond)` and the application boss must call
`registerManagedToken(managedToken)`. Tokens deployed through the Diamond facet
already have both permissions and are already registered. A missing mint role
makes `AssetToManaged` execution revert atomically, and a missing burn role makes
`ManagedToAsset` execution revert atomically.

The Diamond accepts ManagedToken deployments configured with 0 through 18
decimals. Larger values remain valid at the standalone token layer but cannot be
registered because the Diamond's fixed-point arithmetic is bounded to 18 decimals.

Before enabling permissionless offers, the application boss calls
`setPermissionlessSettlementAccount(account)`. That dedicated account must
approve the Diamond for every input and output token used by permissionless
offers, normally with `type(uint256).max`. A permissionless trade then routes
input as user to settlement account to Diamond and output as Diamond or mint to
settlement account to user. The account is a transient hop, not an inventory
source, and its token balances are unchanged after successful settlement.

## What an upgrade does

`gemforge deploy <target>` on an existing deployment reads `facets()` from the
diamond, compares each live facet's deployed bytecode against the freshly
compiled artifacts, and resolves the difference into Add / Replace / Remove
cuts. It redeploys only the facets that actually changed.

Because `foundry.toml` sets `bytecode_hash = "none"` and `cbor_metadata = false`,
compiled bytecode is deterministic — a comment-only edit produces no cut.

`diamond.protectedMethods` in `gemforge.config.cjs` lists the `diamondCut`,
loupe, and standard `IAccessControl` selectors, which Gemforge will never
remove. Protecting `IAccessControl` keeps the static ERC-165 declaration
truthful if the access-control facet is accidentally omitted from a build;
replacing that facet remains possible. `LibDiamond` independently refuses to
remove the `diamondCut` selector on-chain.

The initializer does **not** re-run on an upgrade. When a cut needs storage
migration, pass one explicitly:

```bash
pnpm exec gemforge deploy mainnet \
  --upgrade-init-contract MyMigration --upgrade-init-method migrate
```

## Mainnet: upgrading through the multisig

Cuts require `UPGRADER_ROLE`, which on mainnet belongs to a multisig rather than
a hot key. The `mainnet` target therefore sets `upgrades.manualCut`, so Gemforge
deploys the new facets and then **prints** the `diamondCut` calldata instead of
sending it:

```
Diamond: 0x...
Tx data: 0x1f931c1c...
```

Submit that calldata to the diamond address from the multisig.

To review before deploying anything, run `pnpm exec gemforge deploy mainnet --dry`
first — it resolves and prints the cuts without broadcasting.

## Why the diamond library is our own

`paths.lib.diamond` points at `src/diamond`, not at Gemforge's default
`lib/diamond-2-hardhat`.

The OnRe diamond core is a hardened descendant of
[mudgen/diamond-3-hardhat](https://github.com/mudgen/diamond-3-hardhat): same
storage shape and cut algorithms, but with an ERC-7201 storage namespace,
`UPGRADER_ROLE`-gated cuts instead of an ERC-173 owner, custom errors, checked
`uint32` position casts, an immutable `diamondCut` selector, and strict
init/calldata pairing. Gemforge's default library is diamond-2, which uses a
completely different `selectorSlots` storage layout and an owner-gated cut, so
adopting it would mean giving all of that up.

Gemforge only requires that the path it is given has this shape, which
`src/diamond/contracts/` provides:

```
contracts/Diamond.sol
contracts/libraries/LibDiamond.sol
contracts/facets/{DiamondCutFacet,DiamondLoupeFacet}.sol
contracts/interfaces/{IDiamondCut,IDiamondLoupe,IERC165,IERC173}.sol
```

Two consequences worth knowing:

- **`templates/DiamondProxy.sol`** overrides Gemforge's stock proxy template,
  which assumes an ERC-173 `OwnershipFacet`. Ours installs the two core facets
  and grants the bootstrap upgrader instead. `diamond.coreFacets` omits
  `OwnershipFacet` for the same reason.
- **`interfaces/IERC165.sol` and `interfaces/IERC173.sol`** exist because
  Gemforge's `IDiamondProxy` template — which is *not* overridable — imports
  them from that fixed path. `IERC165.sol` re-exports the OpenZeppelin
  declaration so there is one `IERC165` type in the build. `IERC173` is an empty
  marker: the diamond has no owner, and declaring the interface empty stops the
  generated `IDiamondProxy` from advertising an `owner()` that does not exist.

The core stays under `src/` rather than `lib/` so that `forge build --sizes`,
`forge coverage` and Slither keep treating it as first-party source.

## Deployment records

`gemforge.deployments.json` records the diamond and facet addresses per target.
Commit it — Gemforge reads it to find the existing deployment to upgrade. If it
is missing for a target, `gemforge deploy` treats that target as a fresh
deployment.

## Java bindings

`bindings/java` holds a Gradle build that generates a
[web3j](https://github.com/LFDT-web3j/web3j) wrapper for the diamond from the
merged ABI Gemforge writes to `src/generated/abi.json`, and publishes it as
`com.onre.evm:onre-evm-java:<version>` to this repository's GitHub Packages
Maven registry. The `Java bindings` workflow publishes the version set in
`bindings/java/gradle.properties` on demand; CI only checks that the wrapper
still generates and compiles. See `bindings/java/README.md`.
