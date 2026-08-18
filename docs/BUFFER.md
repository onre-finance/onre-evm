# Buffer accounting

Buffer accounting is configured independently for every registered OnRe token.
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

`OnReToken.mint`, `burn`, and `burnFrom` call the configured controller before
changing supply. The Diamond settles the interval using the old supply and then
records the expected post-operation supply. The token operation reverts if
settlement or reconciliation fails.

The controller-only `mintBuffer` path is different by design: it always mints
to the controller and does not invoke the callback. This is the recursion
boundary for Diamond-initiated Buffer accrual.

The controller is optional until activated. Once configured, the callback is
strict; it does not fall back to an untracked mint or burn.

## Activation order

Configure a token in this order:

1. Register and enable the OnRe token in the Diamond.
2. Create its deterministic USD Pricer and add an active pricing vector.
3. Call `initializeBuffer(onReToken)`. It derives token-specific reserve,
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
