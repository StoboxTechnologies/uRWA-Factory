# 26 — Handoff

**Date:** 16 August 2026
**Covers:** everything on `main` — specification, contracts, tests, verifier, documentation site
**Supersedes:** the specification-to-build handoff of 15 August 2026, kept in git history
**Registry:** [24 — Work registry](24-work-registry.md)

This is the document to read first when picking the work up — a new engineer, a new week, or a new
session of the same work. It follows the six-part handoff protocol defined in
[24 — Handoff protocol](24-work-registry.md#handoff-protocol). Part 6 is the one usually skipped and
is the only one that makes a handoff checkable rather than believed.

---

## Part 0 · The first five minutes

Run these, in this order, before reading anything else.

```bash
python3 build-docs.py && python3 verify.py && python3 verify.py --self-test
```

```bash
forge build && forge test && forge fmt --check
```

```bash
python3 report.py
```

| Command | What it proves | Expected |
|---|---|---|
| `verify.py` | The documentation agrees with itself and with the Solidity | `44/44 checks passed` |
| `verify.py --self-test` | Every check still fails on its own known-bad fixture | `44/44 checks verified` |
| `forge test` | The runtime invariants hold | `141 tests passed` |
| `report.py` | Regenerates [33 — Test results](33-test-results.md) from a real run | A diff in the timestamp only |

If any of the three is red before you have changed anything, stop and fix that first. Everything in
this repository is built on the assumption that the baseline is green.

**Then read, in order:** `CLAUDE.md` (the working rules — they are enforced, not advisory), this
document, [24 — Work registry](24-work-registry.md) for what is left, and
[31 — Verification framework](31-verification.md) for what the checks mean.

---

## Part 1 · Scope — what exists

### The registry

87 items. **51 done, 2 ready, 31 planned, 3 parked.** Full census in
[24 — Totals](24-work-registry.md#totals).

| Group | Items | Done | State |
|---|---:|---:|---|
| SP — Specification | 7 | 7 | Complete |
| IF — Interfaces | 4 | 4 | Complete; storage frozen |
| CO — Core | 14 | 14 | Complete |
| ID — Identity | 4 | 4 | Complete; three adapters, one interface |
| PO — Policy | 9 | 9 | Complete — presets registered and applied at creation |
| CU — Custody | 7 | 6 | Complete but the facet split (`CU-07`), parked behind the audit |
| AG — Agents | 4 | 3 | Mandates and DvP built |
| PA — Passport | 7 | 0 | Not started — the whole of Phase 4 |
| UI — Interfaces | 11 | 2 | Prototypes only; no real surface |
| TO — Tooling | 5 | 0 | Conformance kit not started |
| OP — Operations | 9 | 2 | CI built; audit and release remain |
| ST — Standards | 6 | 0 | Parked for this cycle |

### The code

| Area | Files | Lines | What |
|---|---:|---:|---|
| `src/interfaces/` | 13 | 934 | Every signature, event, error and role constant |
| `src/storage/` | 2 | 143 | Seven namespaced slots; the frozen layout |
| `src/libraries/` | 2 | 167 | `LibDiamond` (immutability, upgrade delay), `Clones` |
| `src/facets/` | 5 | 871 | Compliance, freeze, lockup, monetary, roles, cut |
| `src/rules/` | 1 | 267 | Eight rules, all stateless and shareable |
| `src/identity/` | 1 | 278 | Allowlist, EAS and StoboxDID adapters |
| Top level | 8 | 1,544 | Token, factory, treasury, offering registry, policy set, mandates, DvP |
| **`src/` total** | **32** | **4,204** | No implementation stubs; everything compiles and is exercised |

### The tests

**184 tests across 16 suites, all passing.**

| Suite | Tests | Holds |
|---|---:|---|
| `InterfacePackage.t.sol` | 6 | The interface id is computed from our own declaration, not copied |
| `LedgerPlane.t.sol` | 12 | The ledger cannot be cut out, and fails closed when compliance is |
| `Loupe.t.sol` | 11 | The report and the router agree, after every kind of cut |
| `CompliancePipeline.t.sol` | 15 | Seven gates, in order, with the reason preserved |
| `SubjectAccounting.t.sol` | 7 | Caps count people; the counters cannot be moved from outside |
| `Restrictions.t.sol` | 11 | Freeze and lockups compose into one available balance |
| `Supply.t.sol` | 12 | Issue, redeem, cap — monotonic and lockable |
| `RolesAndCustody.t.sol` | 11 | Four roles, separated; revoking one reaches the money |
| `FreshChain.t.sol` | 9 | The whole stack on a chain with no Stobox contract on it |
| `Policy.t.sol` | 14 | AND of ORs, a **per-rule** gas ceiling, and a rule that reverts refuses |
| `Identity.t.sol` | 11 | Three adapters behind one interface; a reverting registry is survived |
| `Offering.t.sol` | 30 | Purchases, pricing, offering rules that fail closed, refunds that cannot be taken twice |
| `PurchaseDoor.t.sol` | 4 | Primary issuance end to end through the real stack — no stubs on the money path |
| `Deploy.t.sol` | 4 | The deployment script's own code stands the stack up and sells through it |
| `AgentsAndSettlement.t.sol` | 21 | Mandates that cannot be exceeded; trades that cannot half-settle |
| `Preset.t.sol` | 6 | A regime preset is applied at creation and enforces |

Line coverage over `src/` is **75%**, branch coverage **57%**. Coverage is not a measure of whether
the tests are any good — but a branch never taken is a branch nobody has observed, and the weakest
files are named in part 5.

```bash
forge coverage --ir-minimum --report summary
```

### The documentation

**34 numbered documents, 17 diagrams, 3 generated surfaces, 5 prototypes.**

| Surface | Built from | What it is |
|---|---|---|
| `index.html` | `docs/*.md` + `theme.css` | The whole documentation on one page — what the folder opens on |
| `start.html` | the same | One card per document |
| `pages/*.html` | the same | Each document as a page, with previous and next |

All three are committed and CI fails if they are stale, so `python3 build-docs.py` belongs in the
same commit as any change to a document or to the theme. Never hand-edit them.

### Not built — explicitly

- **The asset passport.** `PA-01`…`PA-07`, the whole of Phase 4. The interface exists; nothing behind it.
- **Any real interface.** The five files under `prototypes/` are drawings. Nothing connects to a chain.
- **The conformance kit.** `TO-01` — the thing that would let a third party test somebody else's
  ERC-7943 token against the same invariants.
- **Deployment.** No script, no testnet, no address on any chain.
- **An audit.** No mainnet issuance until one clears.

---

## Part 2 · Interfaces

Every signature is in [07 — Function reference](07-functions.md), and `L3.1`/`L3.2` fail the build if
that document and the Solidity disagree in either direction.

**Frozen:**

- The ERC-7943 surface exactly as the standard defines it, plus two additive extensions —
  `forcedTransfer` with a reason string, and `whyBlocked`.
- `IRule` and its `Context` struct.
- `IIdentityRegistry` and the `Claim` struct.
- `IPolicySet` composition: groups AND together, rules within a group OR.
- `IAgentAuthority` and `IAtomicDvP`.
- `IAssetPassport`, including the bidirectional handshake — specified, not implemented.

**Not frozen:** internal helpers, event parameter ordering beyond the canonical ERC-7943 events, and
gas choices. Those belong to implementation.

---

## Part 3 · Storage

[04 — Storage](04-storage.md) defines seven namespaced slots. `L3.3` compares each struct with that
document field for field, in order, and `L3.4` derives every slot constant from the documented string.

```
urwa.storage.core.v1        CoreStorage        ledger plane, never replaceable
urwa.storage.compliance.v1  ComplianceStorage  policy, trust list, subject accounting, pause
urwa.storage.freeze.v1      FreezeStorage      admin freeze
urwa.storage.lockup.v1      LockupStorage      dated lockups
urwa.storage.monetary.v1    MonetaryStorage    treasury, registry, totalIssued
urwa.storage.roles.v1       RolesStorage       role assignments
urwa.storage.upgrade.v1     UpgradeStorage     scheduled cuts and the delay
```

**Every struct is append-only, and has been since `IF-02` merged.** New field at the end, or a new
`.v2` slot with its own constant. Never reorder, never remove, never change a type — in a diamond
those fields hold live balances, and the field that moves takes somebody's money with it.

---

## Part 4 · Invariants and their owners

Sixteen runtime invariants, each named in [31](31-verification.md#l4--runtime-invariants) and each
claimed by at least one test. `L3.8` fails the build if any of them stops having an owner.

| Invariant | Holds | Owner |
|---|---|---|
| `L4.1` | ERC-20 selectors cannot be replaced or removed | `LedgerPlane.t.sol` |
| `L4.2` | The four views never revert, over fuzzed addresses | `CompliancePipeline.t.sol` |
| `L4.3` | Removing the compliance facet halts transfers | `LedgerPlane.t.sol` |
| `L4.4` | No value moves outside the pipeline except forced operations | `Supply.t.sol` |
| `L4.5` | Holder caps count subjects, not addresses | `SubjectAccounting.t.sol` |
| `L4.6` | `Σ balances == Σ subjectBalance == totalSupply` | `SubjectAccounting.t.sol` |
| `L4.7` | `totalIssued` monotonic; `capLocked` irreversible | `Supply.t.sol` |
| `L4.8` | A compromised upgrade admin cannot change a balance | `LedgerPlane.t.sol` |
| `L4.9` | Trust never bypasses pause or frozen balance | `CompliancePipeline.t.sol` |
| `L4.10` | A refunded purchase cannot be refunded twice | `Offering.t.sol` |
| `L4.11` | `getFrozenTokens` may exceed balance without reverting | `CompliancePipeline.t.sol` |
| `L4.12` | The default deployment charges zero, and any fee is readable | `FreshChain.t.sol` |
| `L4.13` | The whole stack deploys with no Stobox contract present | `FreshChain.t.sol` |
| `L4.14` | A payment leg cannot settle without its security leg | `AgentsAndSettlement.t.sol` |
| `L4.15` | No agent action exceeds its mandate | `AgentsAndSettlement.t.sol` |
| `L4.16` | The loupe agrees with the router, after every kind of cut | `Loupe.t.sol` |

An invariant with an owner is not the same as an invariant that is well tested. `L3.8` proves the
first, and nothing automatic can prove the second.

---

## Part 5 · Findings

### The multi-agent audit of 16 August 2026

After the loupe work, a parallel audit swept every Solidity subsystem and the Python tooling — eight
finders by subsystem, each finding sent to two adversarial reviewers prompted to refute it. It
returned **18 confirmed defects, one split, three refuted, two low**. Seventeen were fixed, each with
a test that fails without the fix; one (subject re-link, below) is deferred with reasons. The full
disposition of every finding — including the rejected ones and why — is in
`_internal/AUDIT-2026-08-16.md`.

The severe ones, by area:

| Area | Finding | Fix |
|---|---|---|
| **Treasury** | `withdrawERC20` never checked any payment lock — a `SUPPLY_OPERATOR` could drain locked investor funds (**critical**) | Both withdrawal doors check `freeBalance(asset)`; the lock is tracked by amount and asset |
| **Offerings** | refund returned cash but never reclaimed delivered tokens, so a failed offering left investors tokens for free | **Deliver at settlement, not at purchase** — a failed offering delivers nothing to reclaim |
| **Offerings** | the test suite's permissive stub hid that a real `purchase` reverts — primary issuance was dead on arrival | The registry is authorised for `distributeFromTreasury`; the real path is tested |
| **DvP** | `cancel` keyed on the bare nonce was still forgeable after the first fix | Settlement state keyed on the instruction digest, which binds the parties |
| **Identity** | `StoboxDIDAdapter.hasValidClaim` hardcoded `false` refused every tier-2 transfer | The base gate is `isActive`; the redundant subject-keyed check is dropped |
| **Policy** | the 100k gas ceiling wrapped the whole policy set, so documented presets ran out of gas | The ceiling is per rule; the set gets a ceiling sized for all its rules |
| **Agents** | `consume` enforced only amounts, not scope/token/counterparty | It now enforces every dimension of the mandate |
| **Monetary** | `issue(to)` minted straight to a holder, skipping the pipeline | Issuance credits the treasury only |

Plus five mediums (loupe `Add`-over-mutable, self-transfer holder inflation, `frozenOf` overflow,
epochless cap, `report.py`'s false "clean") and three test-quality fixes (tests that could not fail
now can). `L3.6`, added just before the audit, is the check that would have caught the access-control
class; the audit found the rest by reading logic against its own claims.

### Fixed just before the audit

Three access-control defects, found by reading every state-changing external function for a caller
check. Each was documented as restricted and none was. `L3.6` now asks the same question every build.

| Finding | What it allowed | Fix |
|---|---|---|
| **`ComplianceFacet.afterUpdate` had no caller check** | Anyone could move the subject counters `MaxHolders` decides on, without moving a balance. | Refuses any caller but the diamond. `test_theSubjectCountersCannotBeMovedFromOutside`. |
| **`AtomicDvP.cancel` took only the nonce** | A bystander could cancel pending trades — though the digest fix in the audit is what finally closed it. | Now keyed on the instruction digest. `test_aForgedInstructionCannotCancelARealTrade`. |
| **The treasury trusted a stored address, not a role** | Revoking a role did not reach the money — a compromised key kept its withdrawal rights. | Both withdrawal doors ask the token's role register. `test_revokingTheRoleReachesTheMoney`. |

`beforeUpdate` needs no such guard — it is a `view`. `releaseExpired` and `createToken` are
permissionless deliberately, and say so in their own comments.

### Open, with owners

| # | Finding | Where it lands |
|---|---|---|
| 1 | **Subject accounting cannot follow a wallet re-link** (audit finding, deferred). Re-binding a wallet to a new DID subject strands the old subject's balance and holder flag, so a concentration cap can be bypassed and `subjectHolderCount` leaks. The correct fix needs a re-sync path keyed off registry events the registries do not emit uniformly, and touches the frozen `ComplianceStorage`. A re-link is rare and admin-driven; the exposure is a wrong holder cap, not lost funds. | `CO-05` follow-up — a re-sync entry point, argued against the storage layout. |
| 2 | **`L3.7` is specified and not implemented** — storage structs only ever grow, diffed against the previous release. It needs a previous release. | The first tag. |
| 3 | **Branch coverage is 57%** (line 75%). The audit tests lifted the thinnest files — `AtomicDvP` branch 39% → 79%, `uRWAToken` line 18% → 62% — but `RolesFacet` (66%), `uRWAFactory` (69%) and `RuleLibrary` (57%) still want more. | Before the pre-audit freeze. A branch nobody has taken is where the next finding is. |
| 4 | **`RuleLibrary` is 56% covered** and is the surface an issuer actually configures. | `PO-08`, with the presets. |
| 5 | **The offering registry is one contract, not five facets.** Recorded in [03](03-contracts.md) rather than left as a silent divergence. | `CU-07`. |
| 6 | **Claim freshness windows are not settled** per datapoint group. | `PA-03`. Cheap now, expensive after rules encode it. |
| 7 | **The timelock default offered in the console is undecided.** Whatever ships becomes the de-facto standard. | `UI-01`. |
| 8 | **MiCA claim key names are unconfirmed** against a real configuration. | `PO-08`. |

### Outside this repository

| Finding | Status |
|---|---|
| **The public STV3 documentation claims ERC-7943 support the deployed tokens do not have.** Verified on Arbitrum One: every ERC-7943 selector resolves to the zero address. | **Correction deferred by the issuer, 15 August 2026.** Recorded here so the finding survives the decision. |
| **`StoboxDID` reverts on unknown wallets** — `getUserDID` and `getAttribute` carry a `hasDID` modifier, which unwrapped would break conformance on the most common case in existence: a transfer to a new address. | Fixed in `StoboxDIDAdapter` and pinned by `Identity.t.sol`, with a mock that reverts exactly as the deployed contract does. |
| **`deactivateAddressOfDID` is reversible by the holder** and is therefore never an enforcement signal. Only `blockDID` stops a person. | Documented in [09](09-identity-did.md). The adapter reads it as no signal at all. |

### Parked, with reasons

- **Fiat investment flow** — out of scope for v1; a large surface and a trusted-recorder dependency.
- **Cross-chain** — the mint/burn seam is retained, nothing is wired.
- **Subgraph / indexer** — `TO-05`. A performance question, never a correctness one.
- **Standards outreach** — `ST-*`, parked for this cycle. `ST-02` lands better with the conformance
  kit behind it: *here is a failure mode, here is the test that catches it*.

---

## Part 6 · Verification

**How to confirm this handoff is real without asking anyone.** Each row is a command.

| Claim | Check |
|---|---|
| The documentation agrees with the code | `python3 verify.py` — 44 checks, all four levels |
| The checks are not decorative | `python3 verify.py --self-test` — each one fails on its own known-bad fixture |
| The invariants hold at runtime | `forge test` — 184 tests, 16 suites |
| Every invariant has an owner | `L3.8`, which fails if a test stops naming one |
| Every documented caller is enforced | `L3.6` — delete any guard in `src/` and it names the function |
| The documentation cannot drift | Edit any `docs/*.md`, push, and watch CI fail until `build-docs.py` is run and committed |
| The open boundary is enforced | Add a Stobox address under `src/` and watch the `open-boundary` job fail |
| The stack needs nothing of ours | `forge test --match-contract FreshChain` — deploys and transfers with no Stobox contract present |
| The deploy script works | `forge test --match-contract DeployTest` — CI runs the operator's exact code |
| The ledger cannot be cut out | `forge test --match-test test_theLedgerCannotBeReplaced` |
| ERC-7943 is genuinely absent from STV3 | `cast call --rpc-url https://arb1.arbitrum.io/rpc 0x998a0beaf37ca4ba61b5cfac59fdee0da2211a46 "facetAddress(bytes4)(address)" $(cast sig "canTransfer(address,address,uint256)")` returns the zero address |

---

## Continuing in a new session

### The rules that bite

Seven things that have cost time here, each now enforced by a check. Read them before writing anything.

| Rule | Why | Enforced by |
|---|---|---|
| A function added to an interface is documented in [07](07-functions.md) **in the same commit** | The documentation is the specification, and drift is invisible until somebody trusts it | `L3.1`, `L3.2` |
| An event or error added anywhere is added to [14](14-events-errors.md) | Same, in both directions | `L3.5` |
| `python3 build-docs.py` runs in the same commit as any doc or theme change | Three surfaces are generated and committed | `L0.6`, a content digest — not a timestamp |
| A new check needs a row in [31](31-verification.md) **and** a fixture it fails on | A check nobody has seen fail is a check nobody has tested | `L2.16`, `L5` |
| No page declares a token, loads a font, or restates a rule from `theme.css` | One edit changes how everything looks; that only works if there is one file | `L0.12`, `L0.14` |
| Storage structs only grow | Those fields hold live balances | `L3.3`, and `L3.7` when there is a release to diff against |
| Whoever doc 07 says may call a function is who the code lets call it | Documentation is not a guard, and three functions were guarded by nothing else | `L3.6` |

And one that no check can catch: **`vm.prank` and `vm.expectRevert` are consumed by the very next
call, including a call in an argument list.** `dvp.settle(i, _sign(k, i), ...)` spends the cheat on
`_sign`. Hoist every helper call to its own statement. This has cost eight tests in one sitting.

`report.py` writes [33 — Test results](33-test-results.md) and then judges a corpus containing it, so
it rebuilds the documentation on both sides of the run. It carries a timestamp: commit it when the
results changed, not on every run.

### What to do next, in order

| # | Item | Why this order |
|---|---|---|
| 1 | `OP-04` — run `DeployStack` + `DeployDemoToken` on Base Sepolia, verify, publish the addresses | The scripts and their CI test exist; a real chain is the remaining step to the first demo token |
| 2 | Branch coverage on `uRWAToken`, `uRWAFactory`, `RolesFacet`, `AtomicDvP` | Findings 2 and 3, before anything is frozen |
| 3 | `TO-01` — the conformance kit | Unparks `ST-02`, and is the piece that makes the work useful to somebody else's token |

Phase 4 (`PA-*`) and Phase 5 (`UI-*`) can start in parallel at any point. Neither is on the critical
path to an audit.

---

## Roadmap

```
  HERE                                                     AUDIT      LIVE
   │                                                         │          │
   ├─ CU ─────────────────────────────────────────────────────┼──▶ OP ──▶│
   │   2.75w                                                  │   audit  │
   │                                                         │
   ├──▶ PA   5.25w   (parallel, not on the critical path)    │
   ├──▶ TO   3.75w   (conformance kit first)                 │
   └──▶ UI  10w      (parallel)
```

| Phase | Registry | State |
|---|---|---|
| **0 · Interfaces** | IF-01…04 | **Done** — storage frozen |
| **1 · Core** | CO, ID | **Done** — 14 of 14 |
| **2 · Policy** | PO | **Done** — 9 of 9 |
| **3 · Custody** | CU, AG | **9 of 11** — the facet split and the reference agent remain |
| **4 · Passport** | PA | Not started |
| **5 · Interfaces** | UI | Prototypes only |
| **6 · Release** | OP-05…08 | Audit, remediation, mainnet |

**≈27.25 engineer-weeks remaining**, arithmetic over the registry rather than a fresh estimate. The
groups that have shipped were re-estimated by being built; `PA`, `UI` and `OP` still carry their
original figures and should be re-argued before anyone commits to them.

---

## Related documents

- [24 — Work registry](24-work-registry.md) — the item-level plan and the handoff protocol
- [31 — Verification framework](31-verification.md) — what each check means and why it exists
- [33 — Test results](33-test-results.md) — the last recorded run
- [20 — Development plan](20-development-plan.md) — the phase narrative
