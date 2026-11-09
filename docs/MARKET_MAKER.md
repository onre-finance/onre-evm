# Uniswap v4 market maker

`OnReMarketMakerFacet` mirrors the custody and execution controls of the Solana
`mmbot-sc` program. The bot executor trades inventory; the current OnRe boss
configures the bot and authorizes withdrawals. A boss transfer immediately changes
that authority; funds always go to the vault's configured withdrawal destination.
No separate owner or initialization call is
introduced, and the Diamond's existing initializer remains unchanged.

The implementation targets a single boss-approved ERC20 pair and Uniswap v4
PoolManager. The managed side must be an enabled OnRe managed token. The asset
side is explicitly configured by the boss (USDC for the initial deployment).
The pool must already be initialized, have a fixed fee below 100%, and have no
hooks. Native ETH, dynamic fees, hooks, multihop routing, and LP position
management are not supported.

## Setup and authority

1. Install the facet with the normal Gemforge Diamond upgrade process.
2. Initialize and fund the desired hookless Uniswap pool separately.
3. The boss creates a vault with `createConfigurableVault(MarketMaker,
   instanceId, withdrawalDestination, 0)`. The destination follows normal vault
   semantics and can be changed by the boss with `updateConfigurableVault`.
4. The boss calls `configureMarketMaker` with `MarketMakerConfig`: PoolManager,
   managed token, asset token, fee, tick spacing, and the MarketMaker `vaultId`.
   Uniswap fees use millionths:
   `500` means 0.05%, not 500 basis points. Token ordering is derived internally.
5. The boss calls `setMarketMakerExecutor` with the authorized bot address.
6. Anyone can approve the Diamond and call `depositConfigurableVault(vaultId,
   token, amount)`. Amounts are integer ERC20 base units. Deposits
   credit the MM ledger and do not create depositor shares or withdrawal rights.

Only the executor can call `swapUniswapV4`. The executor cannot configure pools,
change its authorization, or withdraw funds. As in `mmbot-sc`, the executor is
trusted to choose the trade amount, minimum output, and price limit; no NAV
strategy or automatic market-price oracle is implemented on-chain.

The boss or an OnRe admin can enable `setMarketMakerKillSwitch(true)`; only the
boss can clear it. Either this local switch or the application-wide kill switch
blocks swaps. A local MM pause does not block standard deposits or withdrawals;
the application-wide kill switch blocks vault withdrawals as usual.
`withdrawConfigurableVault(vaultId, token, amount)` and
`withdrawAllConfigurableVault(vaultId, token)` require the boss for MarketMaker
vaults and always send to `withdrawalDestination`. There are no separate MM
deposit, withdrawal, or balance APIs. Use `configurableVaultBalance(vaultId,
token)` to inspect inventory. Ordinary vault deposits can hold additional tokens,
but swaps are restricted to the boss-approved pool's pair.

## Swap and settlement

`MarketMakerSwapParams` contains:

- `sellManagedToken`: `true` sells ONyc for the asset; `false` buys ONyc.
- `amountIn`: maximum exact-input budget in token-in base units, limited to the
  positive `int128` range used by v4 balance deltas.
- `minimumAmountOut`: absolute output floor, in token-out base units. Slippage
  percentages are converted into this floor by the off-chain bot.
- `sqrtPriceLimitX96`: Uniswap's Q64.96 square-root price in sorted token1/token0
  raw units, independent of trade direction and human token decimals. Zero
  selects the directional protocol boundary. A nonzero limit can cause a
  partial fill and is not a substitute for the minimum output floor.
- `deadline`: latest accepted block timestamp.

The facet reserves the requested amount from the MM ledger, unlocks the
PoolManager, and authenticates exactly one `unlockCallback` using the configured
manager and the hash of the active request. The callback swaps, checks signed
input/output deltas and the output floor, then pays only the actual input using
`sync`, an exact ERC20 transfer, and `settle`. Output is taken directly to the
Diamond. No ERC20 approvals or Universal Router commands are used.

After settlement, physical Diamond balance changes must equal the swap deltas.
Only actual input is debited, unused input is restored to MM inventory, and
output is credited to MM inventory. Any failed check reverts the pool operation,
token transfers, callback authorization, and ledger changes together. Zero-fill
or zero-output swaps revert. Fee-on-transfer tokens are rejected by exact
balance checks.

## Inventory isolation and future redemption

MM configuration, authorization, and callback state occupy the separate ERC-7201
namespace `onre.storage.MarketMaker`. Inventory uses the existing configurable
vault balance mapping and standard vault events, with a dedicated `MarketMaker`
kind appended to preserve all prior enum values and vault IDs. Existing fee and
fulfillment escrow accounting is unchanged. A Diamond ERC20 balance is not the
bot's spending balance: `configurableVaultBalance(config.vaultId, token)` is the
limit. Direct ERC20 donations do not credit it. Reconfiguring the pool or selected
vault preserves old inventory, which remains accessible through the standard
vault withdrawal APIs.

Funds are physically held by the same Diamond, so the facet is part of the
Diamond's trusted code and upgrade boundary. Logical isolation is enforced by
the MM vault debit/credit rules; it is not a separate custody contract. MM swaps
and all standard deposit/withdraw entrypoints for MarketMaker-kind vaults share a
transient reentrancy lock, including calls across facets. Other vault kinds keep
their existing withdrawal permissions and destination rules.

`marketMakerState` returns the pool configuration, executor, and local kill
switch. Pool prices, quotes, NAV-band decisions, trade sizing, and transaction
simulation remain off-chain, as in the existing bot.

Internal ONyc redemption/minting through OnRe offers is a separate future path.
It must explicitly debit and credit the MM and offer vault ledgers and reuse
pricing, fees, liquidity constraints, supply-change callbacks, and Prop AMM
execution accounting. Calling `this.takeOffer` is not an inventory settlement
implementation.

## Dependency and tests

The core dependency is pinned to Uniswap `v4-core` tag `v4.0.0`, commit
`e50237c43811bd9b526eff40f26772152a42daba`. Its PoolManager uses EIP-1153
transient storage and requires a Cancun-compatible EVM, including Ethereum
mainnet. Initialize dependencies with `git submodule update --init --recursive`.
Foundry auto-detects compilers: first-party pragmas remain pinned to 0.8.35,
while the unmodified canonical PoolManager fixture is compiled separately with
its required 0.8.26 and deployed from its artifact by the integration tests.

Run `pnpm exec gemforge build`, then `forge test --match-contract
OnReMarketMakerTest -vv`. Tests deploy the real pinned PoolManager and exercise
both swap directions, partial fills, output floors, independent inventory,
boss succession, executor rotation, emergency controls, callback authorization,
and transfer-tax rejection. These are local protocol integration tests, not a
claim of mainnet deployment or a live ONyc/USDC pool test.
