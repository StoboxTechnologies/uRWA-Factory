# 26 — Handoff: specification to build

**Date:** 15 August 2026
**From:** specification (SP-01…07, UI-00, UI-08, OP-01)
**To:** the interface package (IF-01…04) and everything gated behind it
**Registry:** [24 — Work registry](24-work-registry.md)

This follows the six-part handoff protocol defined in
[24 — Handoff protocol](24-work-registry.md#handoff-protocol). Part 6 is the one usually skipped and
is the only one that makes a handoff checkable rather than believed.

---

## Part 1 · Scope

### Covered — delivered and merged

| Registry | Delivered |
|---|---|
| SP-01 | Architecture, contracts, storage, roles, all thirteen state machines |
| SP-02 | Function reference — every signature with what it does, who calls it, why it exists |
| SP-03 | Compliance pipeline, rule engine, identity model |
| SP-04 | Asset passport, disclosure model, the open/proprietary boundary |
| SP-05 | Agent mandates and atomic delivery-versus-payment |
| SP-06 | Development plan, testing plan, interface specification, work registry |
| SP-07 | Documentation site, build pipeline, design system |
| UI-00, UI-08 | Four interactive prototypes |
| OP-01 | CI: documentation sync, anchor integrity, open-boundary enforcement |

**26 documents · 4 prototypes · 79 registry items · repository and documentation site live.**

### Not covered — explicitly

- **No Solidity exists.** Not one contract, not one interface, not one test.
- No deployment on any chain, testnet included.
- No audit, and no mainnet issuance until one clears.
- No conformance kit yet — it is `TO-01`, and it depends on `CO-03`.
- Effort figures are planning estimates, not commitments. Re-estimate at the `IF` gate.

---

## Part 2 · Interfaces

Every signature the next stage will implement is specified in
[07 — Function reference](07-functions.md), across eighteen contracts. Treat that document as the
contract for `IF-01`.

**Frozen by this handoff:**

- The ERC-7943 surface, exactly as the standard defines it, plus two additive extensions —
  `forcedTransfer` with a reason string, and `whyBlocked`.
- `IRule` and its `Context` struct.
- `IIdentityRegistry` and the `Claim` struct.
- `IPolicySet` composition semantics: groups AND together, rules within a group OR.
- `IAssetPassport`, including the bidirectional handshake.
- `IAgentAuthority` and `IAtomicDvP`.

**Deliberately not frozen:** internal helper functions, event parameter ordering beyond the canonical
ERC-7943 events, and gas-optimisation choices. Those belong to implementation.

---

## Part 3 · Storage

[04 — Storage](04-storage.md) defines six namespaced slots and their structs.

```
urwa.storage.core.v1        CoreStorage        ledger plane, never replaceable
urwa.storage.compliance.v1  ComplianceStorage  policy, trust list, subject accounting
urwa.storage.freeze.v1      FreezeStorage      admin freeze
urwa.storage.lockup.v1      LockupStorage      dated lockups
urwa.storage.monetary.v1    MonetaryStorage    treasury, registry, totalIssued
urwa.storage.roles.v1       RolesStorage       role assignments
```

**From the moment `IF-02` merges, every struct is append-only forever.** New field at the end, or a
new `.v2` slot with its own constant. Never reorder, never remove, never change a type.

This is the single decision that cannot be revised once facets exist, which is why `IF-02` gates all
of CO, PO and PA.

**`subjectBalance` and `subjectHolderCount` must be in `ComplianceStorage` from the first commit.**
Holder caps count identities, not addresses. This cannot be retrofitted — you cannot determine
retroactively which past addresses shared an owner, so the counters would start from a permanently
wrong baseline.

---

## Part 4 · Invariants the next stage may assume

Fifteen are listed in [17 — Security](17-security.md#invariants--assert-in-tests). The five that
shape implementation decisions:

1. **ERC-20 selectors are registered against the diamond itself and cannot be replaced or removed.**
   Verified in the STV3 base: `LibDiamond.replaceFunctions` reverts `CannotReplaceImmutableFunction`,
   and the deploy script registers the core selectors against the diamond's own address.
2. **`canSend`, `canReceive`, `canTransfer` and `whyBlocked` never revert and never write** — for any
   input, including unknown, zero and contract addresses.
3. **Removing the compliance facet halts transfers.** The diamond fallback reverts `FunctionNotFound`,
   so the system fails closed by construction rather than by our code.
4. **Trust bypasses rules only** — never the pause check, never the frozen-balance check.
5. **The fee is zero in the default deployment, any non-zero fee is publicly readable, and no STBU
   reference exists anywhere in the open-source code.**
   Enforced by CI, not by review.

---

## Part 5 · Known gaps

Everything deliberately left undone, with the reason.

### Carried into implementation

| Gap | Why it matters | Where it lands |
|---|---|---|
| **StoboxDID reverts on unknown wallets** | `getUserDID` and `getAttribute` carry a `hasDID` modifier. Unwrapped, this breaks ERC-7943 conformance on the most common case in existence: a transfer to a new address. | `ID-04`. Its definition of done is a test proving all four interface functions return rather than revert. |
| **`getAttribute` is an ungated public view** | Attribute values are world-readable on chain. This is necessary — the pipeline must read from a `view` context — but it means values must be hashes. | Confirm no deployment stores plaintext country codes, names or document numbers. Make hashing the documented convention for every writer. |
| **Claim schema not finally signed off** | Rules, attestations and every KYC integration encode its shape. Cheapest thing to argue about now, most expensive later. | Settle at the `IF` gate, before `PO-02`. |
| **Role topology default** | Roles are configurable, so whatever ships as the default becomes the de-facto standard. | Four separated roles is the documented default; confirm before `CO-08`. |

### Outside this repository

| Gap | Action |
|---|---|
| **The public STV3 documentation claims ERC-7943 support that the deployed tokens do not have** | Verified on Arbitrum One: every ERC-7943 selector resolves to the zero address and `supportsInterface(0x3edbb4c4)` returns false. **Correction deferred by the issuer, 15 August 2026.** Recorded here so the finding survives the decision. |
| **AIDesigner not used** | Dropped 15 August 2026. The design system is settled by hand and documented in [25](25-design-system.md). |
| **Grant programme names unverified** | Base and Optimism programme names, eligibility and windows were not checked. Confirm before any of it reaches a plan or a deck. See `PUBLICATION-PLAN.md`. |

### Parked with reasons

- **Fiat investment flow** — out of scope for v1; significant surface area and a trusted-recorder dependency.
- **Cross-chain** — the mint/burn seam is retained, nothing is wired.
- **Subgraph / indexer** — `TO-05`. Performance optimisation, never a correctness dependency.
- **Dark mode** — removed deliberately. See [25 — Design system](25-design-system.md).

---

## Part 6 · Verification

**How to confirm this handoff is real without asking anyone.** Each row is a command or a URL.

| Claim | Check |
|---|---|
| The specification is complete and published | `https://stoboxtechnologies.github.io/uRWA-Factory/` returns 200 with 28 sections |
| Documentation cannot drift from source | Edit any `docs/*.md`, push, and watch CI fail until `python3 build-docs.py` is run and committed |
| The open boundary is enforced | Add a Stobox address to any file under `src/` and watch the `open-boundary` job fail |
| The prototypes work | `https://stoboxtechnologies.github.io/uRWA-Factory/prototypes/` — four surfaces, all clickable |
| ERC-7943 is genuinely absent from STV3 | `cast call --rpc-url https://arb1.arbitrum.io/rpc 0x998a0beaf37ca4ba61b5cfac59fdee0da2211a46 "facetAddress(bytes4)(address)" $(cast sig "canTransfer(address,address,uint256)")` returns the zero address |
| The ledger boundary already exists in the base | Read `LibDiamond.replaceFunctions` in `Stobox_STV3_Protocol` — it reverts `CannotReplaceImmutableFunction` when the facet is the diamond |
| Nothing has been built yet | `src/`, `test/` and `script/` contain README files and no `.sol` |

---

## Roadmap

```
  NOW                                                              AUDIT      LIVE
   │                                                                 │          │
   ├─ IF ──▶ CO ──────────▶ PO ────────▶ CU ─────────────────────────┼──▶ OP ──▶│
   │  2.5w   10.75w          4.5w         6w                         │   audit  │
   │                │                                                │
   │                ├──▶ PA  5.25w      (parallel from CO-01)         │
   │                ├──▶ TO  2.75w      conformance kit first         │
   │                └──▶ UI  9w         (overlaps CO through PA)      │
   │
   └─ ST-02  parked to the end of Phase 1, when the conformance kit backs it
```

Standards outreach is stood down for this cycle. The critical path is unaffected: it never ran
through `ST-*`.

| Phase | Registry | Delivers | Effort | Gate |
|---|---|---|---|---|
| **0 · Interfaces** | IF-01…04 | Compiling interfaces, storage frozen | 2.5w | Two-engineer interface freeze |
| **1 · Core** | CO, ID, TO-01 | Token, factory, adapters, conformance kit | ~14w | Pipeline review by an external reviewer |
| **2 · Policy** | PO | Rule engine, 12 rules, 7 presets | 4.5w | Rule review per rule |
| **3 · Custody** | CU, AG | Treasury, offerings, agents, atomic DvP | 10w | **Pre-audit freeze** |
| **4 · Passport** | PA | Snapshots, proofs, verifier library | 5.25w | Third party verifies a proof unaided |
| **5 · Interfaces** | UI | Four surfaces plus SDK | 9w | Issuer deploys without an explorer |
| **6 · Release** | OP-05…08 | Audit contest, remediation, mainnet | — | Release sign-off |

Roughly **54 engineer-weeks to audit** at two Solidity engineers and one front-end engineer with UI
overlapping — five to six months, plus the audit and remediation window.

---

## Immediate next actions

### This week, no dependencies

**Decisions of 15 August 2026 — four of the five original items are stood down.**

| # | Action | Status | Note |
|---|---|---|---|
| 1 | Correct the ERC-7943 claim in the STV3 documentation | **Not now** | Deferred by the issuer. The finding stays recorded in part 5 and in [09 — Identity](09-identity-did.md); nothing is lost by waiting, and the exposure is theirs to weigh. |
| 2 | `ST-01` — Ethereum Magicians thread | **Dropped** | No standards outreach in this cycle. |
| 3 | `ST-02` — ERC-7943 errata | **Parked to Phase 1** | See below. |
| 4 | **Confirm the claim schema** | **Active — the only open item** | Gates `PO-02`. Cheapest hour in the project. |
| 5 | AIDesigner sign-in | **Dropped** | Not used. The design system is settled and documented in [25](25-design-system.md). |

#### Why `ST-02` is parked rather than dropped

Filing errata now would cost attention and deliver nothing, because the argument lands far harder with
a runnable test behind it. Once `TO-01` — the conformance kit — exists, the same contribution arrives
as *"here is a failure mode, here is the test that catches it, here is the wording that prevents it"*.
That is a different class of contribution from a prose observation.

The finding itself is already written down in [09 — Identity](09-identity-did.md) and part 5 of this
handoff, so it cannot be lost. Revisit at the end of Phase 1.

### Then, in order

| # | Action | Blocks |
|---|---|---|
| 6 | `IF-04` — Foundry skeleton and CI | Everything |
| 7 | `IF-01`, `IF-03` — interfaces, events, errors | CO, PO, PA |
| 8 | **`IF-02` — storage structs and slot constants** | **The gate. Nothing in CO, PO or PA starts before this merges.** |
| 9 | Interface freeze review, two engineers | Phase 1 |

Everything after step 9 follows the registry.

---

## What changed in the source material

Findings from reading the existing estate, recorded so they are not rediscovered later.

1. **Deployed STV3 tokens do not implement ERC-7943**, despite the documentation's compliance table.
   Verified on-chain. The docs also list `canTransact`, a name from a superseded draft.
2. **The ledger boundary already exists in the STV3 base.** `LibDiamond` refuses to replace or remove
   selectors registered against the diamond, and `_update` already calls out to a replaceable
   validation facet. The three-plane architecture is not imposed on STV3 — it is what STV3 was built
   for, with the policy side left empty.
3. **StoboxDID needs no fork** for tier 2, but every call must be wrapped in `try/catch`.
4. **The Compass registry is a strong data model** — 899 datapoints, five tiers, 109 groups — but 81%
   of rows are typed or document-extracted, and around 30 rows describing the token and its compliance
   configuration are machine-provable from a factory-issued token.
5. **In the EU a tokenized security is a MiFID II instrument, not a MiCA crypto-asset.** MiCA still
   matters for commodity-backed tokens and stablecoins, which is why both are in the preset list.

## Related

- [24 — Work registry](24-work-registry.md) — the item-level plan
- [20 — Development plan](20-development-plan.md) — the phase narrative
- [23 — Testing plan](23-testing-plan.md) — what "done" means per area
