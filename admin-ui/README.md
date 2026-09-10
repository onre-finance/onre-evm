# Local admin console

This is a local, entity-oriented operations console for the OnRe Diamond. Its
tabs cover tokens, pricing, Buffer accounting, quoters, vaults, fees, and offers.
Creation forms use readable token metadata and selectors populated from existing
compatible records. Raw bytes32 identifiers stay collapsed under **Technical
identifier** unless they are needed for debugging.

The **Advanced** tab still exposes every ABI read and write method. Entity lists
are reconstructed from creation events and their current state is loaded through
the existing ID-based getters because the contracts do not expose enumerable
registries.

## Docker: Anvil, deployment, and UI

The Docker image starts a fresh Anvil chain with a randomly generated mnemonic,
uses its first unlocked account as the Diamond boss and deployer, configures a
separate generated account as the permissionless settlement account, builds the
UI against that deployment, and serves the UI and RPC together. No boss key or
address is stored in the image or Compose configuration.

```bash
# Build once.
docker compose build

# Run in the foreground.
docker compose up

# Or run in the background.
docker compose up -d
```

Open `http://localhost:5173`. The Anvil RPC is exposed at
`http://localhost:8545` with chain ID `31337`.

After changing contracts or UI code, rebuild and replace the running container:

```bash
docker compose up -d --build --force-recreate
```

Useful lifecycle commands:

```bash
docker compose logs -f
docker compose down
```

The chain is intentionally disposable. Recreating or restarting the container
generates new local accounts and deploys a fresh local Diamond. The generated
boss address is printed in `docker compose logs`; its private key remains only
inside the running Anvil process during that disposable session. The UI reads
the boss address from the Diamond and uses Anvil's unlocked account for admin
transactions, so another developer does not need a `.env` file or private key.

## Manual setup

```bash
pnpm devnet
```

In another terminal, create `.env` from `.env.example`, then:

```bash
pnpm deploy:local
pnpm admin:dev
```

Open `http://127.0.0.1:5173` and connect the browser wallet that will act as the
offer user on chain `31337`. Click **Prepare Anvil actors** separately: the UI
reads the current boss from the Diamond and impersonates it for admin actions.
It also configures, impersonates, and funds the permissionless settlement
account. The connected user is funded for local gas without becoming the boss.
These Anvil-only RPC methods must never be used against a shared or production
RPC.

The Overview deployment action deploys a fresh `ManagedToken` implementation,
asks the Diamond factory to create and register the Mock ONyc UUPS proxy, and
deploys a fresh Mock USDC. It does not create pricing, Buffer, quoter, vault,
fee, or offer configuration.

Fixture and manually tracked token addresses are stored per local chain and
Diamond address. **Forget local token addresses** removes the current fixture
pair from browser storage; tokens still referenced by the active Diamond remain
visible because they are reconstructed from on-chain events.

The **Transactions** tab can mint either local mock, display the connected
wallet's balances, preview an existing direct offer, approve its input token,
and call `takeOffer`. Permissionless offers use the contract-required empty
approval automatically. Permissioned offers expose expiry and signature inputs.
Worker offers are excluded because they must use fulfillment requests.

Managed tokens are minted and burned by the Diamond; the UI does not configure an
inventory source. The permissionless settlement account grants the Diamond a
maximum allowance for each freshly deployed or registered token and re-checks
both tokens before a permissionless offer is created.

The **Buffer** tab follows the contract activation order. Initialize the Buffer
only after the registered token has an active USD pricing vector. Activation
then configures all three derived vault destinations, sets the Diamond as the
token's Buffer controller, and finally saves gross APR and fee settings. The UI
preserves each derived vault's existing refill target when updating its
withdrawal destination.

`pnpm admin:build` produces the static build under `admin-ui/dist`.

## Source layout

`main.js` is intentionally only the browser entry point. Application code is
split by responsibility under `app/`:

- `controller.js` owns startup, refresh orchestration, and form binding.
- `chain.js`, `data.js`, and `state.js` isolate RPC writes, indexed contract
  state, and browser-local state.
- `actions.js`, `transactions.js`, and `fixtures.js` own their respective user
  workflows.
- `selectors.js`, `model.js`, `ui.js`, and `utils.js` provide shared readable
  labels and presentation helpers.
- `tabs/` contains one renderer per domain tab.

New entity types should add their event/getter mapping in `config.js`, their
readable rendering in a focused `tabs/` module, and their write workflow in
`actions.js`. This keeps ABI access out of the view modules.
