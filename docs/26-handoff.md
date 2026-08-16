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
| `verify.py` | The documentation agrees with itself and with the Solidity | `43/43 checks passed` |
| `verify.py --self-test` | Every check still fails on its own known-bad fixture | `43/43 checks verified` |
| `forge test` | The runtime invariants hold | `130 tests passed` |
| `report.py` | Regenerates [33 — Test results](33-test-results.md) from a real run | A diff in the timestamp only |

If any of the three is red before you have changed anything, stop and fix that first. Everything in
this repository is built on the assumption that the baseline is green.

**Then read, in order:** `CLAUDE.md` (the working rules — they are enforced, not advisory), this
document, [24 — Work registry](24-work-registry.md) for what is left, and
[31 — Verification framework](31-verification.md) for what the checks mean.

---

## Part 1 · Scope — what exists

### The registry

87 items. **46 done, 4 ready, 34 planned, 3 parked.** Full census in
[24 — Totals](24-work-registry.md#totals).

| Group | Items | Done | State |
|---|---:|---:|---|
| SP — Specification | 7 | 7 | Complete |
| IF — Interfaces | 4 | 4 | Complete; storage frozen |
| CO — Core | 14 | 13 | `CO-02a`, the full loupe facet, remains |
| ID — Identity | 4 | 4 | Complete; three adapters, one interface |
| PO — Policy | 9 | 8 | Rule library built; `PO-08`, the regime presets, remains |
| CU — Custody | 7 | 3 | Treasury and registry built; pricing and the facet split remain |
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

**130 tests across 12 suites, all passing.**

| Suite | Tests | Holds |
|---|---:|---|
| `InterfacePackage.t.sol` | 6 | The interface id is computed from our own declaration, not copied |
| `LedgerPlane.t.sol` | 12 | The ledger cannot be cut out, and fails closed when compliance is |
| `CompliancePipeline.t.sol` | 13 | Seven gates, in order, with the reason preserved |
| `SubjectAccounting.t.sol` | 6 | Caps count people; the counters cannot be moved from outside |
| `Restrictions.t.sol` | 10 | Freeze and lockups compose into one available balance |
| `Supply.t.sol` | 9 | Issue, redeem, cap — monotonic and lockable |
| `RolesAndCustody.t.sol` | 9 | Four roles, separated; the treasury holds the tokens |
| `FreshChain.t.sol` | 9 | The whole stack on a chain with no Stobox contract on it |
| `Policy.t.sol` | 13 | AND of ORs, a gas ceiling per rule, and a rule that reverts refuses |
| `Identity.t.sol` | 11 | Three adapters behind one interface; a reverting registry is survived |
| `Offering.t.sol` | 14 | Purchases, allocations, refunds that cannot be taken twice |
| `AgentsAndSettlement.t.sol` | 18 | Mandates that cannot be exceeded; trades that cannot half-settle |

Line coverage over `src/` is **73%**, branch coverage **57%**. Coverage is not a measure of whether
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

Fifteen runtime invariants, each named in [31](31-verification.md#l4--runtime-invariants) and each
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

An invariant with an owner is not the same as an invariant that is well tested. `L3.8` proves the
first, and nothing automatic can prove the second.

---

## Part 5 · Findings

### Fixed while writing this handoff

Both were found the same way: by reading every state-changing external function in `src/` and asking
what stops the wrong caller. Each was documented as restricted, and neither was.

| Finding | What it allowed | Fix |
|---|---|---|
| **`ComplianceFacet.afterUpdate` had no caller check** | Anyone could move `subjectBalance` and `subjectHolderCount` — the numbers `MaxHolders` and `MaxBalancePerHolder` decide on — without moving a balance. A holder cap could be made to refuse an honest investor, or admit a forbidden one. | Refuses any caller but the diamond. `test_theSubjectCountersCannotBeMovedFromOutside`. |
| **`AtomicDvP.cancel` took only the nonce** | Documented as "either party"; callable by anyone. A bystander watching a relayer could cancel every pending trade on the contract for the price of the gas. | Takes the instruction and checks the caller is the seller or the buyer. `test_onlyAPartyMayCancel`. |

`beforeUpdate` needs no such guard — it is a `view`. `releaseExpired` and `createToken` are
permissionless deliberately, and say so in their own comments.

### Open, with owners

| # | Finding | Where it lands |
|---|---|---|
| 1 | **`L3.6` is specified and not implemented** — every access modifier checked against the caller documented in [07](07-functions.md). It was blocked on there being implementation contracts to read; there are now 32. | The first job of the next session. Both findings above are the same shape: a documented caller with nothing enforcing it. |
| 2 | **`L3.7` is specified and not implemented** — storage structs only ever grow, diffed against the previous release. It needs a previous release. | The first tag. |
| 3 | **Branch coverage is 57%.** The thin files are `uRWAToken` (18%), `uRWAFactory` (25%), `RolesFacet` (35%), `AtomicDvP` (39%). | Before the pre-audit freeze. A branch nobody has taken is where the next finding is. |
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
| The documentation agrees with the code | `python3 verify.py` — 43 checks, all four levels |
| The checks are not decorative | `python3 verify.py --self-test` — each one fails on its own known-bad fixture |
| The invariants hold at runtime | `forge test` — 130 tests, 12 suites |
| Every invariant has an owner | `L3.8`, which fails if a test stops naming one |
| The documentation cannot drift | Edit any `docs/*.md`, push, and watch CI fail until `build-docs.py` is run and committed |
| The open boundary is enforced | Add a Stobox address under `src/` and watch the `open-boundary` job fail |
| The stack needs nothing of ours | `forge test --match-contract FreshChain` — deploys and transfers with no Stobox contract present |
| The ledger cannot be cut out | `forge test --match-test test_theLedgerCannotBeReplaced` |
| ERC-7943 is genuinely absent from STV3 | `cast call --rpc-url https://arb1.arbitrum.io/rpc 0x998a0beaf37ca4ba61b5cfac59fdee0da2211a46 "facetAddress(bytes4)(address)" $(cast sig "canTransfer(address,address,uint256)")` returns the zero address |

---

## Continuing in a new session

### The rules that bite

Six things that have cost time here, each now enforced by a check. Read them before writing anything.

| Rule | Why | Enforced by |
|---|---|---|
| A function added to an interface is documented in [07](07-functions.md) **in the same commit** | The documentation is the specification, and drift is invisible until somebody trusts it | `L3.1`, `L3.2` |
| An event or error added anywhere is added to [14](14-events-errors.md) | Same, in both directions | `L3.5` |
| `python3 build-docs.py` runs in the same commit as any doc or theme change | Three surfaces are generated and committed | `L0.6`, a content digest — not a timestamp |
| A new check needs a row in [31](31-verification.md) **and** a fixture it fails on | A check nobody has seen fail is a check nobody has tested | `L2.16`, `L5` |
| No page declares a token, loads a font, or restates a rule from `theme.css` | One edit changes how everything looks; that only works if there is one file | `L0.12`, `L0.14` |
| Storage structs only grow | Those fields hold live balances | `L3.3`, and `L3.7` when there is a release to diff against |

And one that no check can catch: **`vm.prank` and `vm.expectRevert` are consumed by the very next
call, including a call in an argument list.** `dvp.settle(i, _sign(k, i), ...)` spends the cheat on
`_sign`. Hoist every helper call to its own statement. This has cost eight tests in one sitting.

`report.py` writes [33 — Test results](33-test-results.md) and then judges a corpus containing it, so
it rebuilds the documentation on both sides of the run. It carries a timestamp: commit it when the
results changed, not on every run.

### What to do next, in order

| # | Item | Why this order |
|---|---|---|
| 1 | Implement `L3.6` — access modifiers against the callers documented in [07](07-functions.md) | It can only be written now that the contracts exist, and it closes the gap both part 5 findings came through |
| 2 | `CO-02a` — the full loupe facet | The last item in Phase 1, and every tool that introspects a diamond wants it |
| 3 | `PO-08` — the four regime presets, with the MiCA key names confirmed | Closes Phase 2 and settles finding 8 |
| 4 | `CU-03`, `CU-06`, `CU-07` — pricing, the purchase facet, the registry split | Closes the money paths before the pre-audit freeze |
| 5 | Branch coverage on `uRWAToken`, `uRWAFactory`, `RolesFacet`, `AtomicDvP` | Findings 3 and 4, before anything is frozen |
| 6 | `TO-01` — the conformance kit | Unparks `ST-02`, and is the piece that makes the work useful to somebody else's token |

Phase 4 (`PA-*`) and Phase 5 (`UI-*`) can start in parallel at any point. Neither is on the critical
path to an audit.

---

## Roadmap

```
  HERE                                                     AUDIT      LIVE
   │                                                         │          │
   ├─ CO-02a ─▶ PO-08 ─▶ CU ─────────────────────────────────┼──▶ OP ──▶│
   │   0.25w    0.5w     2.75w                               │   audit  │
   │                                                         │
   ├──▶ PA   5.25w   (parallel, not on the critical path)    │
   ├──▶ TO   3.75w   (conformance kit first)                 │
   └──▶ UI  10w      (parallel)
```

| Phase | Registry | State |
|---|---|---|
| **0 · Interfaces** | IF-01…04 | **Done** — storage frozen |
| **1 · Core** | CO, ID | **13 of 14** — `CO-02a` remains |
| **2 · Policy** | PO | **8 of 9** — `PO-08` remains |
| **3 · Custody** | CU, AG | **6 of 11** — pricing, purchase facet, registry split |
| **4 · Passport** | PA | Not started |
| **5 · Interfaces** | UI | Prototypes only |
| **6 · Release** | OP-05…08 | Audit, remediation, mainnet |

**≈29.75 engineer-weeks remaining**, arithmetic over the registry rather than a fresh estimate. The
groups that have shipped were re-estimated by being built; `PA`, `UI` and `OP` still carry their
original figures and should be re-argued before anyone commits to them.

---

## Related documents

- [24 — Work registry](24-work-registry.md) — the item-level plan and the handoff protocol
- [31 — Verification framework](31-verification.md) — what each check means and why it exists
- [33 — Test results](33-test-results.md) — the last recorded run
- [20 — Development plan](20-development-plan.md) — the phase narrative
