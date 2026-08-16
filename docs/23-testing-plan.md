# 23 — Testing plan

## Layers

| Layer | Tool | Runs | Purpose |
|---|---|---|---|
| Unit | `forge test` | Every commit | Function behaviour in isolation |
| Fuzz | `forge test` | Every commit | Property behaviour over random inputs |
| Invariant | `forge test --match-test invariant_` | Every commit | System properties across random call sequences |
| Integration | `forge test` | Every commit | Multi-contract flows end to end |
| Fork | `forge test --fork-url` | Nightly and pre-release | Real StoboxDID, real EAS, real USDC |
| Fresh-chain | anvil in CI | Every commit | A fork of this repo deploys and works with no Stobox dependency |
| Conformance | separate repo | Every commit | ERC-7943 conformance, runnable by anyone |
| Gas | `forge snapshot` | Every commit | Regression on the pipeline cost |

## Coverage targets

| Area | Line | Branch |
|---|---:|---:|
| Ledger core and facets | 100% | 95% |
| Compliance pipeline | 100% | 100% |
| Rules | 100% | 100% |
| Freeze and lockup | 100% | 100% |
| Treasury and offerings | 95% | 90% |
| Passport and proofs | 95% | 90% |
| Agent authority and DvP | 100% | 95% |
| Factory | 90% | 85% |

The pipeline and the rules are at 100% branch because every branch there is a compliance decision. A
missed branch is a transfer that should have been blocked and was not, or the reverse.

---

## Invariants

Run under `forge` invariant testing with a bounded handler. These correspond to
[17 — Security](17-security.md#invariants--assert-in-tests).

```solidity
invariant_ledgerImmutable()          // ERC-20 selectors still map to the diamond
invariant_supplyMatchesBalances()    // Σ balances == totalSupply
invariant_subjectSumMatchesSupply()  // Σ subjectBalance == totalSupply
invariant_supplyWithinCap()          // totalSupply <= maxSupply when set
invariant_totalIssuedMonotonic()     // never decreases
invariant_capLockNeverUnlocks()      // capLocked: true never becomes false
invariant_subjectCountLeHolderCount()
invariant_viewsNeverRevert()         // canSend/canReceive/canTransfer/whyBlocked, fuzzed addresses
invariant_noValueMovesOutsidePipeline()
invariant_trustNeverBypassesPauseOrFreeze()
invariant_refundOnce()               // a purchase cannot be refunded twice
invariant_treasuryAvailableNonNegative()
invariant_agentWithinMandate()       // no agent action exceeds its limits
invariant_noStoboxReference()        // source and bytecode scan
invariant_feeIsZero()                // open distribution
```

### The one that matters most

`invariant_viewsNeverRevert` fuzzes addresses — including zero, contracts, EOAs with no identity,
blocked subjects and expired claims — and asserts that all four view functions return rather than
revert. This is the ERC-7943 requirement most likely to break in integration, because the naive
StoboxDID adapter reverts on unknown wallets.

---

## Critical test cases

### Compliance pipeline

| Case | Expect |
|---|---|
| Paused token, trusted → trusted | Reverts `ProtocolPaused` — pause overrides trust |
| Trusted → untrusted | Rules run on the receiving side |
| Untrusted → trusted | Rules run |
| Trusted → trusted | Rules skipped, pause and freeze still applied |
| Trusted treasury, amount exceeds unfrozen | Reverts — trust never bypasses freeze |
| Unknown wallet, `canTransfer` | Returns `false`, does not revert |
| Mint to ineligible recipient | Reverts `ERC7943CannotReceive` |
| Burn from ineligible sender | Reverts `ERC7943CannotSend` |
| Compliance facet removed | Every transfer reverts `FunctionNotFound` |
| `whyBlocked` vs actual revert | Same stage and reason, always |

### Subject accounting

| Case | Expect |
|---|---|
| One subject, three wallets, cap of two holders | Third wallet still receives — one subject |
| Two subjects, cap of one | Second subject blocked |
| Wallet with no subject | Counted under a synthetic subject; never under-counts |
| Subject balance falls to zero across all wallets | `subjectHolderCount` decrements exactly once |
| Wallet deactivated, other wallets of the subject | Continue to work |

### Freeze and lockup

| Case | Expect |
|---|---|
| Admin freeze 200 + lockups 300, 200 | `getFrozenTokens` = 700 |
| After the June lockup expires, no transaction | `getFrozenTokens` = 400 |
| Frozen exceeds balance | Returns, does not revert |
| `setFrozenTokens` | Writes only the admin component; `Frozen` carries the composed total |
| Transfer of exactly the unfrozen amount | Succeeds |
| One wei more | Reverts `ERC7943InsufficientUnfrozenBalance` |

### Forced operations

| Case | Expect |
|---|---|
| `forcedTransfer` of frozen tokens | `Frozen` emitted before `Transfer`, then `ForcedTransfer` |
| `forcedTransfer` to an ineligible address | Reverts — `canReceive` enforced |
| Both signatures present | Canonical 3-arg and 4-arg overload behave identically otherwise |
| `EmergencyFacet` not installed | Selector absent; call reverts `FunctionNotFound` |

### Rules

| Case | Expect |
|---|---|
| A rule that reverts | Counts as reject, `RuleFailed` emitted, token still usable |
| A rule that consumes all gas | Gas ceiling enforced, counts as reject |
| Rules beyond `maxRules` | `addRule` reverts `RuleLimitExceeded` |
| OR group, first fails, second passes | Group passes |
| AND across groups, one fails | Evaluation fails with that group's reason |
| Policy set swapped mid-flight | Next transfer uses the new set; balances untouched |

### Offerings

| Case | Expect |
|---|---|
| Full happy path | create → activate → purchase → close → settle |
| Soft cap missed | `beginRefunding` callable by anyone; both refund paths work |
| Double refund via both paths | Second attempt reverts `AlreadyRefunded` |
| Withdraw before soft cap | Reverts `PaymentsAreLocked` |
| Operator absent after close | `settle` / `beginRefunding` still callable by anyone |
| Purchase by an offering-eligible but token-ineligible investor | Reverts on the distribution leg |

### Passport

| Case | Expect |
|---|---|
| Declared but unconfirmed link | `isConfirmed` false; not presentable as provenance |
| Token declares a passport it does not own | Confirmation never granted; link stays unconfirmed |
| Proof of a disclosed value | `verify` true |
| Proof with the wrong salt | `verify` false |
| Absence proof for an unset code | `verifyAbsence` true |
| Revoked attestation | Not usable as evidence |
| Snapshot older than the window | `snapshotOf` returns the stale flag set |
| Attestor key rotated | Historical signatures still verify against the key valid at signing |

### Agents and settlement

| Case | Expect |
|---|---|
| Agent action within mandate | Succeeds, `AgentActed` emitted |
| Exceeds `maxPerAction` | Reverts |
| Exhausts `maxPerEpoch` | Reverts until the epoch rolls |
| Token outside the allowlist | Reverts |
| Mandate expired | Reverts |
| `revoke` mid-flight | Next action reverts immediately, no timelock |
| Agent attempts mint, role change or pause | No scope grants it; reverts |
| `previewSettle` false, then `settle` | Reverts with the same reason |
| Counterparty becomes ineligible between sign and settle | `settle` reverts, nothing moves |
| Instruction replayed | Reverts, nonce settled |
| `cancel` then `settle` | Reverts |
| Payment succeeds, security leg fails | Whole transaction reverts — no partial state |

The last one is the atomicity proof and should be written as an explicit test that forces the security
leg to fail after the payment leg has executed within the same call.

---

## Fork tests

Against Base and Arbitrum forks with real dependencies.

| Test | Verifies |
|---|---|
| StoboxDID adapter against the live contract | `try/catch` behaviour on real unknown wallets |
| Real DID with expired attribute | `hasValidClaim` false, no revert |
| Real blocked DID | `isActive` false |
| EAS adapter against live EAS | Attestation reads and revocation |
| USDC settlement | Decimals handling, permit support |
| Gas on a real chain | Matches the snapshot within tolerance |

The first three are the highest-value tests in the suite. The `hasDID` revert behaviour is a live
property of a deployed contract, and a mock will not reproduce it.

---

## Conformance kit

Built, and **liftable**: `test/conformance/ERC7943Conformance.sol` imports nothing from `src/`, so
publishing it as its own repository is a copy, not a port. Any implementer inherits the harness,
answers six hooks — the token, an eligible holder and receiver, an ineligible account, the freeze
authority, and optionally a force authority — and every check judges their token. CI runs it against
this repository's own token on every commit; the first stranger the kit met was us.

```
forge test --match-path "test/conformance/*"
```

| Group | Checks |
|---|---|
| Interface | `supportsInterface(0x3edbb4c4)` and ERC-165; the sentinel `0xffffffff` denied |
| Purity | The four views never revert and never write, over fuzzed inputs — including unknown wallets, the exact failure mode found live in a deployed registry |
| Semantics | `canTransfer` implies `canSend` and `canReceive`; ignores allowances; an ineligible party fails the pair from either side |
| Enforcement | A refused answer binds — the transfer itself fails, not only the preview |
| Freeze | May exceed balance without reverting; binds `canTransfer` and the ledger; emits `Frozen` |
| Forced | Judged only where an authority exists: compulsion bypasses the freeze, never `canReceive` |

`canTransfer` **includes** frozen balances — it answers "would this exact transfer succeed, right
now", as the interface defines it. An earlier draft of this table claimed it excluded balance, which
contradicted the interface's own words; the kit settled the question by running.

Canonical-error decoding and mint/burn gating are the kit's next checks, once the standard's error
surface is exercised by a second implementation worth comparing against.

---

## CI

| Job | Trigger | Fails the build |
|---|---|---|
| `forge build` | push, PR | ✅ |
| `forge test` | push, PR | ✅ |
| `forge test --match-test invariant_` | push, PR | ✅ |
| Coverage thresholds | PR | ✅ |
| `forge snapshot --check` | PR | ✅ on regression beyond tolerance |
| Fresh-chain deploy on anvil | push, PR | ✅ |
| Conformance kit | push, PR | ✅ |
| Fork tests | nightly, pre-release | ✅ pre-release only |
| Slither | PR | Warns |
| No-Stobox-reference scan | push, PR | ✅ |
| `build-docs.py` output committed | PR | ✅ if stale |

The fresh-chain job is the credibility test as a build step: it deploys the whole stack to a clean
anvil instance with no Stobox contract present and runs a complete token sale. If it fails, the
open-source claim has broken and the build stops.

---

## Pre-release checklist

- [ ] All invariants pass with ≥ 100k runs
- [ ] Coverage thresholds met per area
- [ ] Gas snapshot reviewed; regressions explained
- [ ] Fork tests pass against live StoboxDID, EAS and USDC
- [ ] Conformance kit passes
- [ ] Fresh-chain deploy passes
- [ ] Slither findings triaged
- [ ] Every checklist item in [16 — Deployment](16-deployment.md#post-deployment-checklist) verified on testnet
- [ ] Documentation regenerated and committed
- [ ] Deployment manifest updated
- [ ] Release tag signed

## Related documents

- [17 — Security](17-security.md)
- [20 — Development plan](20-development-plan.md)
- [16 — Deployment](16-deployment.md)
