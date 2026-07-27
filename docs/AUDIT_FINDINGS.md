# EVM architecture and security review

Reviewed commit: `56cde412433202e48e1b2861cf2768ee5015326a`

Review scope:

- Diamond architecture and selector routing
- access control and emergency behavior
- offer, pricing, quoting, fulfillment, and vault accounting
- ERC-20, ERC-165, ERC-2535, EIP-712, ERC-7201, and UUPS behavior
- common attack vectors and privileged trust boundaries
- Foundry tests, fuzzing, coverage, gas, contract sizes, lint, and Slither

No Critical or High-severity asset-theft vulnerability was found.

## Runtime and economic findings

### I-01: Liquidity refill uses pre-sale TVL

Classification: Informational, accepted design behavior

`LibOnReOffer._settleAssetToOnRe` calculates the asset-liquidity refill before
transferring sold OnRe inventory to the buyer. The TVL calculation excludes
tokens held by the inventory source, so the current sale is not part of the TVL
used to calculate its own refill.

Example:

- NAV is $1.
- Circulating supply and TVL are initially zero.
- The USDC liquidity-vault target is 10%.
- A user purchases 1,000 OnRe for 1,000 USDC with zero fees.
- The refill calculation sees zero TVL and sends zero USDC to liquidity.
- All 1,000 USDC is accounted as proceeds.
- After inventory is transferred to the buyer, TVL is $1,000 and the configured
  liquidity target is $100, but the liquidity vault still contains zero.

This leaves the asset liquidity vault one forward sale behind the value that
would result from applying the target to post-sale TVL.

Scope clarification:

- the configured target belongs only to the asset liquidity vault, such as the
  USDC or USDG vault;
- this finding does not propose targets for the OnRe inventory, fee, or
  proceeds vaults; and
- the target describes the desired vault size and guides future inflow routing;
  it is not a guaranteed post-transaction reserve.

Relevant code:

- `src/libraries/LibOnReOffer.sol`
- `src/libraries/LibOnReMarketStats.sol`
- `src/libraries/OnReMath.sol`

No remediation is required. User-facing redemption availability is determined
from the actual liquidity-vault balance, not from its configured target. An
empty vault is therefore reported and enforced as empty even when its target
is higher.

#### Solana parity check

Confirmed: the current implementation in `~/Documents/projects/onre-sol` has
the same pre-sale-TVL behavior.

The shared `calculate_redemption_vault_refill_amount` helper reads the cached
`MarketStats.tvl` and applies `vault_target_bps`. Each asset-to-OnRe execution
path calls it before minting or transferring the current OnRe output:

- permissioned `take_offer_v2`;
- permissionless `take_offer_permissionless_v2`; and
- Prop AMM `open_swap_buy`.

Each path refreshes market stats only after output settlement. When settlement
transfers excluded inventory rather than minting, the cached excluded-balance
PDA must also be refreshed before the newly circulating inventory is reflected
in TVL.

The LiteSVM regression tests encode the lag directly. With a 15% target and
initial TVL of zero, the first 1 USDC-equivalent buy routes zero to the
redemption liquidity vault and all input to proceeds. After refreshing
circulating-supply exclusions and market stats, the second buy routes 0.15 USDC
to liquidity. The same expectation exists for all three paths above.

Validation:

- `cargo test -p onreapp refills_redemption_vault -- --nocapture`
- result: 3 passed, 0 failed, 561 filtered out across 24 suites.

Therefore the EVM behavior is parity with Solana. Both implementations converge
toward the desired target as future inflows arrive; neither represents the
target as currently available liquidity.

### M-02: Anyone can empty a live liquidity vault

Severity: Medium

Status: Resolved in the current working tree

At the reviewed commit, `withdrawConfigurableVault` had no authorization
requirement. Passing an amount of zero withdrew the complete logical balance to
the vault's fixed destination.

An arbitrary account can front-run a redemption, sweep all USDC/USDG liquidity
to the configured multisig, and cause the redemption to fail. The attacker can
repeat this after every refill.

This does not steal funds because the destination is fixed, but it permits
indefinite availability and MEV griefing.

Resolution:

- `Liquidity` vault withdrawals now require `DEFAULT_ADMIN_ROLE`, whose
  singleton holder is the current boss.
- The restriction follows two-step boss transfers because the role moves with
  the boss.
- `Fee` and `Proceeds` vault withdrawals remain permissionless triggers to
  their fixed configured destinations.

Regression coverage:

- an `ADMIN_ROLE` holder cannot withdraw liquidity;
- a failed unauthorized attempt leaves accounting and token balances unchanged;
- the boss can withdraw liquidity to the configured destination; and
- the existing non-boss proceeds-vault withdrawal test continues to pass.

### I-02: Worker partial fills round percentage fees independently

Classification: Informational, accepted trusted-worker behavior

The worker chooses each partial-fill amount, and every fragment independently
applies percentage-fee ceiling rounding. Compared with calculating the fee once
over the same aggregate input, each additional fragment can add less than one
smallest unit of the input token.

The configurable minimum fee was removed from the current working tree, so it
cannot be multiplied through fragmentation. Making the remaining rounding
difference economically meaningful would require an impractical number of
worker-authorized fulfillment transactions, and the worker does not receive
the fee.

No remediation is required under the intended trusted-worker model.

### M-04: Worker requests lack user execution constraints

Severity: Medium, with a trusted or compromised worker precondition

A fulfillment request stores no deadline, minimum output, limit price, maximum
aggregate fee, or cumulative output. Every fill uses the current mutable price
and fee configuration.

A request created at a $1 NAV can later be filled at $0.50. The worker can also
front-run cancellation or choose fragments that round to zero output while
still charging the fee and burning net OnRe input.

Recommended remediation:

- store a deadline;
- store a minimum output rate or limit price;
- store a maximum aggregate fee;
- track cumulative fee and output; and
- reject any positive fill producing zero output.

### M-05: Sender-pays-fee tokens can make vault accounting insolvent

Severity: Medium for unsupported or behavior-changing token contracts

Outgoing exact transfers verify only the recipient's balance increase. They do
not verify the Diamond's balance decrease.

If a token credits the recipient with 100 units but debits the Diamond by 110,
the transfer check passes while the logical vault balance decreases by only
100. Physical assets then fall below aggregate logical vault liabilities.

Worker-request cancellation is weaker: it uses `safeTransfer` without any
recipient or sender balance-delta check.

Recommended remediation:

- verify that both recipient increase and sender decrease equal the requested
  amount;
- use the same exact-transfer helper for cancellation; and
- enforce and document an allowlist of canonical, non-rebasing, non-taxed
  assets.

## Low-severity findings

### L-01: Nonzero input can settle for zero output

`previewExecution` rejects zero input but not zero quoted output. Decimal
conversion rounds down, and reverse settlement can burn the input even when
the output is zero.

Reject `amountOut == 0`.

### L-02: ERC-165 declarations can become stale after Diamond cuts

Interface-support flags are initialized separately from selector routing.
Removing an `IAccessControl`, `IDiamondLoupe`, or `IDiamondCut` selector does
not clear the corresponding ERC-165 flag.

Update interface flags atomically with cuts and assert selector completeness
after every upgrade.

### L-03: An upgrader can accidentally remove `diamondCut`

The `diamondCut` selector resides in a removable facet. An authorized cut can
remove its own upgrade entry point and permanently prevent later recovery.

If deliberate immutability is required, provide an explicit finalization path.
Otherwise protect the selector from removal.

## Pre-deployment assurance gaps

### A-01: Production selector wiring is not directly regression-tested

The strongest selector tests use a separately assembled test deployment helper.
The production deployment script is checked mainly for facet count and roles.

Use the production cut builder in selector tests or assert every expected
selector against a script-deployed Diamond.

### A-02: No stateful financial invariant suite

There is no invariant handler covering randomized sequences of:

- vault deposit and withdrawal;
- direct offer execution;
- request creation;
- partial fulfillment;
- cancellation; and
- configuration changes.

Important invariants should include:

- physical custody covers logical vault balances plus outstanding escrow;
- gross input equals fee plus net input;
- forward net input equals refill plus proceeds;
- partial fills conserve remaining request input; and
- terminal requests are deleted.

### A-03: UUPS validation artifacts are not generated by the normal build

Normal Foundry configuration does not emit build information and storage
layouts required by OpenZeppelin's upgrade validator. The current OnReToken
passes validation when those artifacts are generated explicitly.

Enable build information and storage-layout output and run the validator in CI.

### A-04: Diamond storage has no machine-checkable layout baseline

Application, routing, and access-control storage structs are owned by libraries.
Standard UUPS storage-layout validation does not cover these namespaces.

Create and gate a custom ordered-field snapshot for all three ERC-7201
namespaces before production deployment.

### A-05: Gas, coverage, lint, Slither, and storage-layout checks are not CI gates

`forge snapshot --check` currently fails because entries are missing or stale.
CI runs formatting, deployable-size compilation, and tests, but does not enforce
coverage, static analysis, gas, or storage-layout compatibility.

### A-06: Excluded-supply accounts increase execution gas

`marketStats` performs one external `balanceOf` per excluded account.

Measured gas:

- without a populated list: approximately 35,484;
- at the 20-account capacity: approximately 144,466;
- increase: approximately 108,982 gas.

The loop is bounded, but the max-cardinality execution path should have an
end-to-end gas regression test.

## Informational and operational observations

### Global reusable approvals

The EIP-712 approval contains only the user and expiry. It is intentionally
reusable across all permissioned offers until expiry and is not a one-time or
offer-specific authorization.

Document this explicitly. If scoped approvals are required, bind the offer,
limits, nonce, and deadline. ERC-1271 contract approvers are not supported.

### Rebasing and direct-transfer behavior

Rebasing assets can desynchronize physical custody from logical vault books.
Positive rebases and direct transfers can also create surplus tokens that are
not credited to any vault and cannot be withdrawn through normal accounting.

### Native value can be trapped

The Diamond has a payable constructor and fallback but no native-asset
accounting or recovery mechanism.

### Deployment is a 13-transaction broadcast

The deployment sends 11 facet deployments, one initializer deployment, and one
Diamond deployment.

For delegated accounts and RPCs with in-flight transaction limits, use
sequential `--slow` broadcasting and `--resume` partial broadcasts rather than
starting a new deployment.

### Compatibility changes

- `OnReToken.setCCIPAdmin(address(0))` now reverts.
- Adding `burn(uint256)` to `IOnReToken` is source-breaking for external
  interface implementers, although the runtime selector already existed.
- Removing `FeeConfig.minimumAmount` changes the `createFeeConfig` and
  `updateFeeConfig` selectors, their event signatures, and the tuple returned
  by `getFeeConfig`. This is an intentional pre-deployment ABI break.

## Architecture and standards conclusions

Positive conclusions:

- facets are thin and domain-specific;
- pricing, quoting, market statistics, custody, and fulfillment are separated;
- all current selectors match the facet ABIs and no collision was found;
- all three ERC-7201 namespace constants are correct and distinct;
- boss transfer is singleton and two-step;
- admin can only activate the kill switch;
- worker and upgrader authorization is consistently enforced;
- current ERC-2535 routing, loupe, and cut behavior is sound;
- EIP-712 domain separation and ECDSA handling are correct;
- standard-token settlement follows checks-effects-interactions sufficiently
  that Slither's event-order warnings did not expose an additional exploit;
- full-precision arithmetic and operational fuzz bounds passed.

Privileged trust assumptions:

- `DEFAULT_ADMIN_ROLE` controls application economics and configuration;
- `UPGRADER_ROLE` is a root authority because it can replace facets and execute
  initializer delegatecalls;
- `WORKER_ROLE` can currently determine fill timing and fragmentation;
- OnRe token minters, burners, and UUPS upgraders are trusted;
- supported ERC-20 contracts must not change into taxed or rebasing behavior.

## Measured validation

- Foundry tests: 80 passed, 0 failed, 0 skipped.
- Extended fuzzing: 10,000 runs passed.
- Coverage:
  - lines: 97.96%;
  - statements: 97.39%;
  - branches: 91.87%;
  - functions: 98.55%.
- Largest production runtime:
  - `OnReOfferFacet`: 9,871 bytes;
  - EIP-170 margin: 14,705 bytes.
- Principal gas observations:
  - `takeOffer`: up to 201,247;
  - `createFulfillmentRequest`: up to 162,758;
  - `fulfillWorkerRequest`: up to 176,996.
- Slither 0.11.5:
  - 80 contracts;
  - 101 detectors;
  - 36 diagnostics manually triaged;
  - no additional Critical or High path found.
- `forge lint`: only the expected direct-offer timestamp/deadline warning.
- Base Sepolia loupe: expected 11 facets.
- Deployed access-control facet bytecode: matches the reviewed commit.

## Recommended implementation order

1. Add request-level worker user protections.
2. Enforce exact token compatibility and cancellation refunds.
3. Add Diamond/UUPS storage-layout gates and stateful invariants.
4. Add coverage, gas, lint, and static-analysis CI gates.
