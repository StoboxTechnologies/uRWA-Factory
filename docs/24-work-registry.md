# 24 — Work registry

The complete inventory of what has to be built, in what order, with what handed over between stages.
Every item has a stable ID so it can be referenced in issues, commits and handoffs without ambiguity.

## Status vocabulary

| Status | Means |
|---|---|
| **Done** | Merged, documented, and its definition of done is satisfied |
| **Ready** | Unblocked; all inputs exist; can be started today |
| **Blocked** | Waiting on a named dependency |
| **Planned** | Sequenced but not yet unblocked |
| **Parked** | Deliberately deferred, with the reason recorded |

Effort is a planning estimate in engineer-weeks, to be re-estimated once `IF-01` compiles.

---

## Register

### SP — Specification

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| SP-01 | Architecture, contracts, storage, roles, states | **Done** | — | — |
| SP-02 | Function reference with intent per function | **Done** | SP-01 | — |
| SP-03 | Compliance pipeline, rules, identity model | **Done** | SP-01 | — |
| SP-04 | Passport, disclosure model, open boundary | **Done** | SP-01 | — |
| SP-05 | Agents and atomic settlement | **Done** | SP-03 | — |
| SP-06 | Development, testing and interface plans | **Done** | SP-01…05 | — |
| SP-07 | Documentation site and build pipeline | **Done** | SP-06 | — |

### IF — Interface package · Phase 0

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| IF-01 | All interfaces as compiling Solidity with NatSpec | **Done** | SP-02 | — |
| IF-02 | Storage structs and namespaced slot constants | **Done** | SP-01 | — |
| IF-03 | Event and error catalogue as Solidity | **Done** | SP-02 | — |
| IF-04 | Foundry skeleton, remappings, formatting, CI wiring | **Done** | — | — |

> **Gate.** Nothing in CO, PO or PA starts until `IF-02` is merged. The storage layout is the one
> decision that cannot be revised once facets exist.

### CO — Core token and factory · Phase 1

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| CO-01 | Diamond core: immutable ERC-20, ERC-2612, fallback router | **Done** | IF-02 | — |
| CO-02 | DiamondCutFacet with the upgrade delay; loupe reads on the core | **Done** | CO-01 | — |
| CO-02a | DiamondLoupeFacet — full introspection surface | Ready | CO-02 | 0.25 |
| CO-03 | ComplianceFacet: pipeline, ERC-7943 views, `whyBlocked` | **Done** | CO-01 | — |
| CO-04 | Trust list, global pause and per-address pause | **Done** | CO-03 | — |
| CO-05 | Subject-level holder accounting | **Done** | CO-03 | — |
| CO-06 | FreezeFacet and LockupFacet with composed frozen total | **Done** | CO-01 | — |
| CO-07 | MonetaryFacet: issue, redeem, distribute, caps | **Done** | CO-01 | — |
| CO-08 | RolesFacet | **Done** | CO-01 | — |
| CO-09 | Treasury clone | **Done** | CO-07 | — |
| CO-10 | uRWAFactory: create, packages, presets, registry | **Done** | CO-01…09 | — |
| CO-11 | ERC-1404 compatibility surface | **Done** | CO-03 | — |
| CO-12 | Per-address pause — blocks sending and receiving, reason evented | **Done** | CO-01 | — |
| CO-13 | Configurable upgrade delay in TokenParams, exposed for the verifier | **Done** | CO-01 | — |

### ID — Identity

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| ID-01 | `IIdentityRegistry` and claim-key registry | Planned | IF-01 | 0.5 |
| ID-02 | AllowlistRegistry — the open-source default | Planned | ID-01 | 0.5 |
| ID-03 | EAS adapter | Planned | ID-01 | 1 |
| ID-04 | StoboxDID adapter with `try/catch` on every call | Planned | ID-01 | 1 |

> **ID-04 carries the known integration defect.** `getUserDID` and `getAttribute` revert on unknown
> wallets. Its definition of done is a test proving all four interface functions return rather than
> revert for unknown, zero and contract addresses.

### PO — Policy engine and rules · Phase 2

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| PO-01 | PolicySet: AND groups of OR alternatives, gas ceiling, rule cap | Planned | IF-01 | 1 |
| PO-02 | HasValidIdentity | Planned | PO-01, ID-01 | 0.25 |
| PO-03 | JurisdictionAllow / JurisdictionDeny | Planned | PO-01 | 0.5 |
| PO-04 | USAccreditedOnly, EUProfessionalOnly, EUQualifiedExemption | Planned | PO-01 | 0.75 |
| PO-05 | MaxHolders, MaxBalancePerHolder | Planned | PO-01, CO-05 | 0.5 |
| PO-06 | HoldPeriod, TransferWindow | Planned | PO-01, CO-06 | 0.5 |
| PO-07 | SanctionsScreen, TravelRuleThreshold | Planned | PO-01 | 0.5 |
| PO-08 | Four regime presets registered in the factory — RegD506c, RegS, MiCA-ART, MiCA-EMT, Open | Planned | PO-02…09, CO-10 | 0.5 |
| PO-09 | MiCA rules: issuer authorised, token class, whitepaper notified, reserve attested | Ready | PO-01 | 0.75 |

### CU — Custody and offerings · Phase 3

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| CU-01 | Treasury reservation and payment locking | Planned | CO-09 | 1 |
| CU-02 | OfferingRegistry: governance and storage facets | Planned | CU-01 | 1.5 |
| CU-03 | Purchase, allocations, tiered pricing, multi payment token | Planned | CU-02 | 1.5 |
| CU-04 | Dual-path refunds with idempotency | Planned | CU-03 | 1 |
| CU-05 | Offering-level rule engine | Planned | CU-02, PO-01 | 0.5 |
| CU-06 | PurchaseFacet on the token side | Planned | CU-03 | 0.5 |

### AG — Agents and settlement · Phase 3

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| AG-01 | AgentAuthority: mandates, scopes, epoch limits, revoke | Planned | CO-08 | 1 |
| AG-02 | AtomicDvP: settle, previewSettle, cancel | Planned | CO-03 | 1.5 |
| AG-03 | EIP-712 instruction format and signature verification | Planned | AG-02 | 0.5 |
| AG-04 | Reference monitoring agent | Planned | AG-01, TO-04 | 1 |

### PA — Passport · Phase 4

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| PA-01 | `IAssetPassport` and the handshake contract | Planned | IF-01 | 0.75 |
| PA-02 | Sparse Merkle tree, salted leaves, revocation tree | Planned | PA-01 | 1.5 |
| PA-03 | ReferencePassport — mechanism only, no schema | Planned | PA-02 | 1 |
| PA-04 | Verifier library, dependency-free, separate package | Planned | PA-02 | 0.75 |
| PA-05 | AttestorRegistry with key validity windows | Planned | PA-01 | 0.5 |
| PA-06 | Access grants: group-scoped, expiring, revocable | Planned | PA-01 | 0.5 |
| PA-07 | PassportValidRule — optional | Planned | PA-01, PO-01 | 0.25 |

### UI — Interfaces · Phase 5

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| UI-00 | Prototypes: deploy, console, verifier, investor | **Done** | SP-06 | — |
| UI-01 | Wallet connection and identity resolution module | Planned | TO-04 | 1 |
| UI-02 | Deploy console | Planned | UI-01, CO-10 | 1.5 |
| UI-03 | Token console: facets, compliance, supply, holders, roles, verification | Planned | UI-01, CO-* | 2.5 |
| UI-04 | Public verifier and transfer simulator | Planned | UI-01, CO-03 | 1 |
| UI-05 | Investor page: position, eligibility, purchase | Planned | UI-01, CU-03 | 1.5 |
| UI-08 | Prototype: investor page | **Done** | SP-06 | — |
| UI-06 | Compliance console | Planned | UI-01, CO-06 | 1 |
| UI-07 | Passport proof verifier surface | Planned | PA-04 | 0.5 |
| UI-09 | Deploy console: eight steps, no default for upgrade delay or emergency facet | Ready | UI-01 | 0.5 |
| UI-10 | Verifier: upgrade delay, emergency facet, fee and passport state | Ready | UI-01 | 0.5 |

### TO — Tooling

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| TO-01 | **ERC-7943 conformance kit, separate repository** | Planned | CO-03 | 1 |
| TO-02 | Facet verification script and loupe report | Planned | CO-02 | 0.5 |
| TO-03 | Deployment manifest generator | Planned | CO-10 | 0.25 |
| TO-04 | TypeScript SDK and published ABIs | Planned | IF-01 | 1 |
| TO-05 | Subgraph or event indexer — optional, never a dependency | Parked | CO-03 | 1 |

### OP — Operations and release

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| OP-01 | CI: docs sync, anchors, open-boundary scan | **Done** | SP-07 | — |
| OP-01a | Model and documentation verifier — L0, L1, L2 and the L5 self-test | **Done** | OP-01 | — |
| OP-02 | CI: forge build, test, invariants, coverage, gas snapshot | Planned | IF-04 | 0.5 |
| OP-03 | CI: fresh-chain deploy on a clean anvil | Planned | CO-10 | 0.5 |
| OP-04 | Base Sepolia deployment and verification | Planned | CO-10 | 0.25 |
| OP-05 | Public audit contest | Planned | CU-04 | — |
| OP-06 | Remediation and signed release | Planned | OP-05 | 1 |
| OP-07 | Base mainnet deployment | Planned | OP-06 | 0.25 |
| OP-08 | Incident-response runbook and statement template | Planned | OP-04 | 0.25 |

### ST — Standards and adoption

| ID | Item | Status | Depends on | Effort |
|---|---|---|---|---|
| ST-01 | Ethereum Magicians thread on the specification | **Parked** | SP-06 | 0.25 |
| ST-02 | ERC-7943 errata: the revert-on-unknown-subject failure mode | **Parked** | TO-01 | 0.25 |
| ST-03 | Run the conformance kit against CMTAT, publish the result | Planned | TO-01 | 0.5 |
| ST-04 | Draft ERC — diagnostic interface | Planned | CO-03, TO-01 | 1 |
| ST-05 | Draft ERC — agent mandates | Planned | AG-01 | 1 |
| ST-06 | Base ecosystem listing and grant applications | Planned | OP-04 | 0.5 |

---

## Critical path

```
IF-02 ─▶ CO-01 ─▶ CO-03 ─▶ CO-05 ─▶ CO-10 ─▶ CU-01 ─▶ CU-04 ─▶ OP-05 ─▶ OP-07
                    │                  │
                    ├─▶ TO-01 ─▶ ST-03 │
                    ├─▶ PO-01 ─▶ PO-08 ┘
                    └─▶ PA-01 ─▶ PA-04
```

`PA-*` depends only on `CO-01` and can run in parallel with `PO-*`. `UI-*` can start once `TO-04`
exists. Nothing in `ST-*` after `ST-02` should ship before `TO-01`, because a standards claim without
a runnable test is an opinion.

## What can start today

`IF-01` · `IF-02` · `IF-03` · `IF-04`

Everything else is gated behind the storage layout. Standards work (`ST-*`) is parked for this cycle
by decision of 15 August 2026 — see [26 — Handoff](26-handoff.md#this-week-no-dependencies). The
critical path never ran through it.

---

## Handoff protocol

A handoff is how work moves between people or phases. An item is not handed over until all six parts
exist — a handoff missing any of them creates rework, and rework is what schedules actually die of.

| Part | Contents |
|---|---|
| **1 · Scope** | The registry IDs covered, and explicitly what is *not* covered |
| **2 · Interfaces** | Every signature the next stage will call, frozen and compiling |
| **3 · Storage** | Which slots are claimed, which structs are append-only from now |
| **4 · Invariants** | Which properties the next stage may assume, each backed by a passing test |
| **5 · Known gaps** | Everything deliberately left undone, with the reason |
| **6 · Verification** | How the receiver confirms the handoff is real, without asking the sender |

Part 6 is the one usually skipped. It is the only one that makes a handoff verifiable rather than
believed — a command to run, a test to execute, or an address to read.

### Handoffs in this project

| From → To | Must contain |
|---|---|
| **IF → CO** | Compiling interfaces; frozen storage layout; slot constants; the rule that structs are append-only forever |
| **CO → PO** | `IRule` and `Context` frozen; `subjectHolderCount` and `subjectBalanceOf` live; a worked example rule |
| **CO → PA** | Token address format, `supportsInterface` behaviour, event signatures for provenance |
| **CO → UI** | ABIs published; SDK typed; a Base Sepolia address; `whyBlocked` stage codes documented |
| **PO → CU** | Preset IDs registered; `bounds` semantics; which rules are offering-level versus token-level |
| **PA → UI** | Proof format specification; verifier library; a worked proof that verifies |
| **Any → OP-05** | Frozen interface; complete test suite; deployment manifest; the known-gaps list from part 5 |

---

## Development process

### The loop

```
issue or registry item
   ↓ branch
implement + tests in the same commit
   ↓
documentation updated in the same pull request
   ↓
python3 build-docs.py, output committed
   ↓
CI: build · test · invariants · coverage · gas · docs-sync · open-boundary
   ↓ review
merge → registry status updated in this document
```

### Rules that do not bend

1. **Documentation ships with the code, in the same pull request.** Not afterwards. A separate
   documentation pass never happens, and the specification is the product here.
2. **The storage layout is append-only** once `IF-02` merges. New field at the end, or a `.v2` slot.
3. **Every compliance-path branch is covered.** A missed branch is a transfer that should have been
   blocked and was not.
4. **The open boundary is CI-enforced**, not reviewed by eye. See [19](19-open-boundary.md).
5. **No mainnet issuance before the audit clears.** Written down now so it is not argued later under
   commercial pressure.

### Review gates

| Gate | When | Who | Blocks |
|---|---|---|---|
| Interface freeze | End of IF | Two engineers | All of CO, PO, PA |
| Pipeline review | CO-03 merged | External reviewer | CO-05 onward |
| Rule review | Each new rule | Compliance-literate reviewer | That rule only |
| Pre-audit freeze | End of CU | Team | OP-05 |
| Release sign-off | Each tag | Maintainer | Publication |

### Definition of done — every item

- Tests pass, including invariants, at the coverage target for that area
- Documentation updated in the same pull request
- `build-docs.py` run and the output committed
- Gas snapshot updated if it changed
- The registry status in this document updated
- All invariants in [17 — Security](17-security.md) still assert
- The fresh-chain deployment test passes

---

## Totals

| Group | Items | Done | Ready | Effort remaining |
|---|---:|---:|---:|---:|
| SP — Specification | 7 | 7 | 0 | — |
| IF — Interfaces | 4 | 0 | 4 | 2.5 |
| CO — Core | 11 | 0 | 0 | 10.75 |
| ID — Identity | 4 | 0 | 0 | 3 |
| PO — Policy | 8 | 0 | 0 | 4.5 |
| CU — Custody | 6 | 0 | 0 | 6 |
| AG — Agents | 4 | 0 | 0 | 4 |
| PA — Passport | 7 | 0 | 0 | 5.25 |
| UI — Interfaces | 9 | 2 | 0 | 9 |
| TO — Tooling | 5 | 0 | 0 | 2.75 |
| OP — Operations | 8 | 1 | 0 | 2.75 |
| ST — Standards | 6 | 0 | 0 | 3.5 |
| **Total** | **79** | **10** | **4** | **≈54 engineer-weeks** |

At two Solidity engineers and one front-end engineer, with UI overlapping, that is roughly **five to
six months to audit**, plus the audit and remediation window.

These are planning figures. Re-estimate at the `IF` gate, when the first real code exists and the
storage layout has been argued about properly.

## Related documents

- [20 — Development plan](20-development-plan.md) — the phase narrative
- [23 — Testing plan](23-testing-plan.md) — what "tests pass" means per area
- [19 — Open boundary](19-open-boundary.md) — what CI enforces
