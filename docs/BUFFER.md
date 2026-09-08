# Buffer accounting

Buffer accounting is configured independently for every registered managed token.
It mints the difference between the configured gross APR and the APR already
represented by the token's active USD pricing vector. Settlement happens before
every ordinary mint or burn, and may also be triggered manually by a worker.

## Accrual

For elapsed time `t`, previous supply `S`, configured gross APR `G`, and current
pricing-vector APR `A`, all APR values use a `1e6` scale:

```text
aprDelta = max(G - A, 0)
grossMint = S * aprDelta * t / (365 days * 1e6 + A * t)
```

The denominator discounts the mint by growth already represented by the
pricing vector. Integer division rounds down.

The management fee is expressed as an annual APR in basis points and is capped
at `aprDelta`. The performance fee is then applied to the amount remaining
after the management fee. When its high-watermark check is enabled, the
performance fee applies only when the current NAV is at or above the stored
high watermark. The rest goes to the BufferReserve vault.

The token mints the full amount to the Diamond once. The Diamond records the
reserve, management-fee, and performance-fee shares as logical vault balances;
it does not perform three separate token mints. These tokens remain included in
circulating supply and TVL and compound as part of the token's total supply.

## Supply-change callback

`ManagedToken.mint`, `burn`, and `burnFrom` call the configured controller before
changing supply. The Diamond settles the interval using the old supply and then
records the expected post-operation supply. The token operation reverts if
settlement or reconciliation fails.

The controller-only `mintBuffer` and `burnBuffer` paths do not invoke the
callback. They mint to or burn from the controller's own balance. These are the
recursion boundaries for Diamond-initiated Buffer accrual and NAV reserve burns;
the Diamond records the resulting supply baseline itself.

The controller is optional until activated. Once configured, the callback is
strict; it does not fall back to an untracked mint or burn.

## Activation order

Configure a token in this order:

1. Register and enable the managed token in the Diamond.
2. Create its deterministic USD Pricer and add an active pricing vector.
3. Call `initializeBuffer(managedToken)`. It derives token-specific reserve,
   management-fee, and performance-fee vault IDs and creates their configurable
   vault records.
4. Read the derived IDs from `getBufferState` and set each vault's withdrawal
   destination with `updateConfigurableVault`.
5. Set the token's Buffer controller to the Diamond.
6. Set the Buffer gross APR and fee configuration.

Steps 1 through 4 prepare the Diamond without affecting token operations. Step
5 activates strict callbacks for all subsequent ordinary mint and burn paths.
The first settlement seeds the supply baseline and NAV high watermark without
minting historical accrual.

Changing gross APR or fee configuration settles the elapsed interval under the
old configuration first. `settleBuffer` is worker-only and respects the
application kill switch. Token supply callbacks remain available while killed
so token-level mint and burn permissions do not become an accidental global
freeze.

## Burn for NAV preservation

The boss (`DEFAULT_ADMIN_ROLE`) calls
`burnForNavIncrease(managedToken, assetAdjustmentAmount)` to offset a reduction
in the effective USD asset base by burning managed tokens from that token's
BufferReserve vault. The name follows Solana's `burn_for_nav_increase`.
The function preserves the current quoted NAV; it does not edit pricing vectors
or transfer USD assets. The USD reduction is an accounting input supplied by the
boss, not an on-chain asset withdrawal.

`assetAdjustmentAmount` is USD scaled to the managed token's decimals, matching
`MarketStats.tvl`. For 9-decimal ONyc, `$100` is `100_000_000_000`; at a quoted
NAV of `$1.10`, this burns `90_909_090_909` base units (about `90.909090909 ONyc`).
NAV itself always uses the Pricer's `1e9` scale.

The call first settles pending Buffer accrual, including management and
performance fees, then applies the same rounding as Solana:

```text
totalAssets = floor(circulatingSupply * currentNav / 1e9)
requiredSupplyAfter = ceil((totalAssets - assetAdjustmentAmount) * 1e9 / currentNav)
burnAmount = circulatingSupply - requiredSupplyAfter
```

Only the reserve's logical balance funds the burn. Fee vault balances, other
vaults, and unaccounted tokens held by the Diamond cannot cover a reserve
shortfall. The Diamond records the reduced total supply as the next accrual
baseline and calls controller-only `burnBuffer`, which skips the supply-change
callback. Market statistics are derived on read and immediately reflect the
reduced circulating supply and TVL.

The operation respects the kill switch and requires an initialized Buffer, the
Diamond as token controller, and executable USD pricing. Ordinary token burner
permission is not required for the controller-only Buffer path.
It rejects zero adjustments, adjustments above circulating TVL, amounts that
produce no burn, and insufficient reserves. The Diamond must remain included
in circulating supply; otherwise burning its tokens cannot offset the asset
reduction. A failure reverts both the burn and preceding accrual atomically.
`BufferBurnedForNav` reports the token, burned amount, USD adjustment,
pre-burn total assets, and quoted target NAV.

### Business assumptions and Solana differences

NAV preservation assumes actual backing assets matched circulating supply times
the quoted NAV before the reported reduction. The contract derives `totalAssets`
from that quote; it does not verify off-chain assets or losses. For example,
1,000 ONyc backed by $1,100 has a $1.10 NAV. After a $110 loss, burning 100
reserve ONyc leaves $990 backing 900 ONyc, maintaining $1.10 per token. The
reserve gives up its claims; other holders keep their tokens. A reserve shortfall
reverts, so loss absorption is limited by available reserve tokens.

Burning without an actual asset reduction increases backing per remaining token
while leaving the quoted price unchanged. Changing the pricing vector to reflect
the same loss before burning targets that new price, not the original NAV.
The operator must reconcile the asset adjustment and the price configuration.

For positive adjustments, the burn formula matches Solana. EVM reads excluded
balances live and derives market stats on demand; Solana reads a cached excluded
balance and refreshes stored market stats. EVM additionally rejects an excluded
Diamond and always rejects a zero adjustment. Solana's arithmetic can produce a
dust burn for zero adjustment when NAV is below $1 and flooring TVL discards
enough value; that behavior is deliberately not reproduced.

Existing managed-token proxies need an implementation upgrade that includes
`burnBuffer` before using this entrypoint. Adding that method also changes the
`IManagedToken` ERC-165 interface ID checked when registering tokens or
validating factory implementations. This change adds no token or Diamond
storage fields; deploy the updated Buffer facet and use the regenerated
Diamond ABI for the new entrypoint.
