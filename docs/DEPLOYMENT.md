# Deploying and upgrading the OnRe Diamond

Deployments and upgrades run through [Gemforge](https://gemforge.xyz). Gemforge
diffs the compiled facet ABIs against the on-chain loupe and applies exactly the
cuts that differ, so there is no hand-written deployment script to keep in sync
with the facet set.

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

## Commands

| Command | What it does |
| --- | --- |
| `gemforge build` | Writes `src/generated/`, then runs `commands.build` (`forge build --sizes src`) |
| `gemforge deploy <target>` | Deploys a new diamond, or upgrades an existing one |
| `gemforge deploy <target> --dry` | Prints the cuts without sending anything |
| `gemforge deploy <target> --new` | Forces a fresh diamond at a new address |
| `gemforge query <target>` | Lists on-chain facets and selectors, flagging unrecognized ones |
| `gemforge verify <target>` | Verifies the diamond and its facets on the block explorer |

Targets are `local`, `testnet` (Sepolia) and `mainnet`, defined in
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
3. Deploys the nine application facets and `OnReDiamondInit`.
4. Sends one `diamondCut` that adds every application selector and delegatecalls
   `OnReDiamondInit.init` with `initArgs`.
5. `init` seeds boss/admin/worker/upgrader and the approvers, then revokes the
   deployer's bootstrap `UPGRADER_ROLE` — unless the deployer *is*
   `ONRE_UPGRADER`.

Step 5 is the one to keep in mind: **after a fresh deployment, the deployment
wallet can no longer upgrade the diamond** unless it was named as
`ONRE_UPGRADER`. For local and testnet iteration, set `ONRE_UPGRADER` to the
deployment wallet. For mainnet, set it to the upgrade multisig.

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
