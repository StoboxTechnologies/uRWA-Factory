# 20 — Development plan

Six phases. Each ends with something releasable and independently useful. Effort figures are planning
estimates for a team of two Solidity engineers plus one front-end engineer, and should be re-estimated
once the interface package compiles.

## Phase 0 — Interface package

**Goal:** the design is checked by a compiler rather than by reading.

| Task | Output |
|---|---|
| Write every interface from [07](07-functions.md) as Solidity with NatSpec, no bodies | `src/interfaces/*.sol` |
| Declare every storage struct from [04](04-storage.md) | `src/storage/*.sol` |
| Fix the diamond storage slot constants | `src/storage/Slots.sol` |
| Define every event and error from [14](14-events-errors.md) | `src/interfaces/IEvents.sol`, `IErrors.sol` |
| Foundry project skeleton, CI, linting | `foundry.toml`, `.github/workflows` |

**Exit criteria:** `forge build` succeeds. Storage layout is frozen. An external reviewer can read the
whole surface in one sitting.

**Why first:** the storage layout is the one decision that cannot be revised once facets exist, and
this is what an auditor or outside contributor asks for before anything else.

*Estimate: 1–2 weeks.*

---

## Phase 1 — Core token and factory

**Goal:** a conformant ERC-7943 token anyone can deploy.

| Task | Output |
|---|---|
| Diamond core with immutable ERC-20 and ERC-2612 | `uRWAToken.sol` |
| `DiamondCutFacet`, `DiamondLoupeFacet` | facets |
| `ComplianceFacet` — pipeline, ERC-7943 views, `whyBlocked`, trust list, pause | facet |
| `FreezeFacet`, `LockupFacet` — composed frozen total | facets |
| `MonetaryFacet`, `RolesFacet` | facets |
| `AllowlistRegistry`, `EASAdapter` | identity adapters |
| `uRWAFactory` with packages and presets | factory |
| `Treasury` clone | treasury |
| **Conformance kit** — separate repository | test suite |

**Exit criteria:**

- `supportsInterface(0x3edbb4c4)` returns true
- Conformance kit passes, including the must-not-revert guarantee for unknown wallets
- Deployed and verified on Base Sepolia
- A fork deploys the whole stack to a fresh anvil chain and completes a transfer — as a CI job

*Estimate: 5–7 weeks.*

---

## Phase 2 — Policy engine and rules

**Goal:** real compliance regimes, configurable without a migration.

| Task | Output |
|---|---|
| `PolicySet` — AND groups of OR alternatives, gas ceiling, rule cap | contract |
| Twelve rules from [10](10-rules.md) | `src/rules/*.sol` |
| Seven presets registered in the factory | migration script |
| `StoboxDIDAdapter` with mandatory `try/catch` on every call | adapter |
| Subject-level holder accounting wired through the pipeline | facet change |

**Exit criteria:**

- Every preset has a passing and a failing test per rule
- The DID adapter returns rather than reverts for unknown, zero and contract addresses
- Holder caps demonstrably count subjects: a test where one investor with three wallets cannot exceed
  a two-holder cap
- A deliberately reverting rule does not brick the token

*Estimate: 4–5 weeks.*

---

## Phase 3 — Custody and offerings

**Goal:** run a real primary sale end to end.

| Task | Output |
|---|---|
| Treasury reservation and payment locking | contract |
| `OfferingRegistry` facets: governance, storage, purchase, refund, rules | diamond |
| Tiered pricing, multi payment token, allocations | facets |
| Dual-path refunds with idempotency | facet |
| `PurchaseFacet` on the token side | facet |

**Exit criteria:**

- Full lifecycle test: create → activate → purchase → close → settle
- Full failure test: create → activate → purchase → close → soft cap missed → refund, via both paths
- Double-refund attempt fails
- Payments provably not withdrawable before soft cap
- **Audit contest opens here**, against a frozen interface

*Estimate: 5–6 weeks.*

---

## Phase 4 — Passport and proofs

**Goal:** verifiable asset provenance without disclosing the record.

| Task | Output |
|---|---|
| `IAssetPassport`, `PassportLink` handshake | interfaces and contract |
| `ReferencePassport` — mechanism only, no schema | contract |
| Sparse Merkle tree, salted leaves, revocation tree | library |
| **Verifier library** — dependency-free, published separately | library |
| `AttestorRegistry` with key validity windows | contract |
| Access grants: group-scoped, expiring | contract |
| `PassportValidRule` | rule |

**Exit criteria:**

- A third party verifies a proof using only the published spec and the verifier library
- Absence proofs work — "no legal opinion" is provable
- Handshake cannot be forged from the token side alone
- No datapoint schema appears anywhere in the repository

*Estimate: 4–5 weeks.*

---

## Phase 5 — Interfaces

**Goal:** the system is usable by people, not only by contracts.

See [21 — Interface specification](21-interface-specification.md) for the full screen inventory.

| Task | Output |
|---|---|
| Wallet connection and identity resolution | shared module |
| Issuer console | app |
| Investor page | app |
| Compliance console | app |
| Public verifier | app |
| TypeScript SDK and published ABIs | npm package |

**Exit criteria:**

- An issuer deploys a token and runs an offering without touching a block explorer
- An investor sees why a transfer would fail *before* signing
- A verifier checks a passport proof with no account

*Estimate: 6–8 weeks, overlapping phases 2–4.*

---

## Phase 6 — Audit and mainnet

| Task | Output |
|---|---|
| Public audit contest | report |
| Remediation | fixes and re-review |
| Signed release, deployment manifest | tag |
| Base mainnet deployment | addresses |
| STBU fee enabled on the Stobox instance only | configuration |

**Exit criteria:** findings resolved or explicitly accepted in writing; mainnet issuance open.

---

## Critical path

```
Phase 0 ──▶ Phase 1 ──▶ Phase 2 ──▶ Phase 3 ──▶ Phase 6
                 │           │
                 └──▶ Phase 4 ┘
                 └──▶ Phase 5 (overlaps 2–4)
```

Phase 4 depends only on Phase 1. Phase 5 can start once Phase 1 interfaces are stable. The audit gates
mainnet, not publication — code and testnets are public from the end of Phase 1.

## Team

| Role | Phases | Load |
|---|---|---|
| Solidity engineer × 2 | 0–4, 6 | Full |
| Front-end engineer | 5 | Full from Phase 2 |
| Designer | 5 | Part-time |
| Technical writer | All | Part-time — docs ship with each phase |
| Security reviewer | 3, 6 | External |

## Definition of done, every phase

1. Tests pass; coverage meets the targets in [23 — Testing plan](23-testing-plan.md)
2. Documentation updated in the same pull request as the code
3. `build-docs.py` regenerated and committed
4. Deployment manifest updated
5. All invariants from [17](17-security.md) still assert
6. The fresh-chain fork test passes

## Risks

| Risk | Mitigation |
|---|---|
| Storage layout wrong, discovered late | Phase 0 exists precisely to prevent this |
| Diamond complexity slows the audit | Verification tooling and a loupe report shipped in Phase 1 |
| Scope grows through phases 3 and 5 | Each phase is independently releasable; a phase can be deferred without stranding the previous one |
| Gas cost of the pipeline exceeds expectations | Measured from Phase 1; the order in [08](08-compliance-pipeline.md) is designed for the cheap path first |
| DID adapter revert behaviour discovered in production | Explicit exit criterion in Phase 2 |

## Related documents

- [21 — Interface specification](21-interface-specification.md)
- [23 — Testing plan](23-testing-plan.md)
- [16 — Deployment](16-deployment.md)
