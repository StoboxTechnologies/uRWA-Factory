# 27 — Model inventory and artifact register

Every model and every artifact this project produces, what each is for, who owns it, and how it is
verified. If something is not in this table it either does not exist or it is undocumented — both are
defects, and the verifier in [31](31-verification.md) treats them as such.

## The five models

A model is a coherent description of one aspect of the system. Each answers a different question and
each is checkable against the others.

| # | Model | Answers | Document | Verified by |
|---|---|---|---|---|
| 1 | **Product** | Who uses this, to do what, and what value moves | [28](28-product-model.md) | Every actor has at least one job; every job reaches a surface |
| 2 | **Data** | What exists, what it holds, what may never be untrue | [29](29-data-model.md) | Every entity has an owner, a lifecycle and at least one invariant |
| 3 | **Interaction** | Who calls whom, in what order, and what happens on failure | [30](30-interaction-model.md) | Every call in the graph exists in the function reference |
| 4 | **Domain** | The compliance rules themselves | [10](10-rules.md) | Every rule reads a declared claim key |
| 5 | **Design** | How any of it is presented | [25](25-design-system.md) | Every surface uses the token set |

### How the models constrain each other

```
  Product ──── every job ────▶ Interaction ──── every call ────▶ Function reference
     │                              │                                   │
     │ every actor                  │ every read/write                  │ every signature
     ▼                              ▼                                   ▼
   Roles (05) ◀──── enforced by ── Data model (29) ────▶ Storage (04) ──▶ Events (14)
     │                              │
     └──── every state ────▶ States (06) ◀──── every lifecycle ─────────┘
```

A change to any one of these is wrong if the others do not move with it. That is not a style
preference — it is what the verifier checks.

## Artifact register

Everything the project produces. Status is the same vocabulary as [24](24-work-registry.md).

### A — Specification artifacts

| ID | Artifact | Kind | Status | Owner | Check |
|---|---|---|---|---|---|
| A-01 | Architecture and three-plane model | Document | Done | Architecture | Referenced by every other doc |
| A-02 | Contract inventory | Document | Done | Architecture | Every contract has a storage owner |
| A-03 | Storage layout and slot constants | Document | Done | Architecture | Append-only rule stated; slots unique |
| A-04 | Role and permission matrix | Document | Done | Compliance | Every role appears in the function reference |
| A-05 | State machines — thirteen | Document | Done | Architecture | Every state reachable and exitable |
| A-06 | Function reference | Document | Done | Architecture | Every function has contract, access and intent |
| A-07 | Event and error catalogue | Document | Done | Architecture | Every event emitted by a named function |
| A-08 | Standards conformance matrix | Document | Done | Architecture | Every claimed standard has a named surface |
| A-09 | Product model | Document | **New** | Product | Actors → jobs → surfaces complete |
| A-10 | Data model | Document | **New** | Architecture | Entities → invariants complete |
| A-11 | Interaction and API model | Document | **New** | Architecture | Call graph closed |
| A-12 | Verification framework | Document | **New** | Engineering | Every check has a failing fixture |
| A-13 | Architecture and flow diagrams — sixteen | SVG | **New** | Design | `L0.11` — resolves, parses, nothing off-canvas |

### B — Code artifacts

| ID | Artifact | Kind | Status | Owner | Check |
|---|---|---|---|---|---|
| B-01 | Interface package | Solidity | Ready | Engineering | `L3.1` signatures match doc 07 |
| B-02 | Storage structs and slots | Solidity | Ready | Architecture | `L3.3`, `L3.4` fields and slots match doc 04 |
| B-03 | Event and error definitions | Solidity | Ready | Architecture | `L3.5` every catalogue entry exists |
| B-04 | Token diamond and facets | Solidity | Planned | Engineering | `L4.1`, `L4.3` core immutable, fail-closed |
| B-05 | Identity adapters — three | Solidity | Planned | Compliance | `L4.2` no view reverts, over fuzzed input |
| B-06 | Policy engine and rule library | Solidity | Planned | Compliance | `L4.4` no value moves outside the pipeline |
| B-07 | Treasury and offering registry | Solidity | Planned | Engineering | `L4.10` a refund cannot happen twice |
| B-08 | Agent authority and atomic DvP | Solidity | Planned | Engineering | `L4.14`, `L4.15` both legs or neither; mandate bound |
| B-09 | Passport, proofs, verifier library | Solidity | Planned | Architecture | Absence provable; proof binds to one root |
| B-10 | Factory | Solidity | Planned | Engineering | `L4.13` deploys on a chain with no Stobox contract |

### C — Test artifacts

| ID | Artifact | Kind | Status | Owner | Check |
|---|---|---|---|---|---|
| C-01 | Unit suites, per contract | Foundry | Planned | Engineering | Coverage floor per contract, enforced in CI |
| C-02 | Invariant suites — sixteen | Foundry | **Done** | Engineering | All sixteen of `L4.1`…`L4.16` present, and `L3.6` fails the build when one loses its owner |
| C-03 | Fork tests against live StoboxDID, EAS, USDC | Foundry | Planned | Engineering | Runs against a pinned block, not `latest` |
| C-04 | Fresh-chain deploy test | CI + anvil | Planned | Engineering | `L4.13` — no Stobox address in the trace |
| C-05 | ERC-7943 conformance kit | Separate repo | Planned | Architecture | Passes against a token this factory issued |
| C-06 | Gas snapshot | Foundry | Planned | Engineering | Committed; a regression fails the build |
| C-07 | **Documentation and model verifier** | Python | **Done** | Engineering | `L5.1`, `L5.2` — every check fails its fixture |

### D — Interface artifacts

| ID | Artifact | Kind | Status | Owner | Check |
|---|---|---|---|---|---|
| D-01 | Deploy console | Prototype | Done | Design | `L2.9` — the surface appears in doc 21 |
| D-02 | Token console | Prototype | Done | Design | `L2.9` — the surface appears in doc 21 |
| D-03 | Public verifier | Prototype | Done | Design | `L2.9` — the surface appears in doc 21 |
| D-04 | Investor page | Prototype | Done | Design | `L2.9` — the surface appears in doc 21 |
| D-05 | Design system and tokens | CSS + doc | Done | Design | One token file; no literal colour in any surface |
| D-06 | Production surfaces | App | Planned | Design | Every job in doc 28 reachable from a surface |
| D-07 | TypeScript SDK and ABIs | Package | Planned | Engineering | ABIs generated from the built artifacts, never hand-written |

### E — Operational artifacts

| ID | Artifact | Kind | Status | Owner | Check |
|---|---|---|---|---|---|
| E-01 | Documentation site and build | Python + Pages | Done | Engineering | `L0.5`…`L0.8` — anchors resolve, no Markdown leaks |
| E-02 | CI: docs sync, anchors, open boundary | Actions | Done | Engineering | `verify.py` and `--self-test` both gate the merge |
| E-03 | CI: build, test, invariants, coverage, gas | Actions | Planned | Engineering | Red on any failing invariant or gas regression |
| E-04 | Deployment manifest | JSON | Planned | Engineering | Every deployed address matches its loupe report |
| E-05 | Facet verification and loupe report | Script | Planned | Engineering | Every selector maps to a verified source file |
| E-06 | Incident-response runbook | Document | Planned | Compliance | Each of the sixteen invariants names a response |
| E-07 | Signed releases with audit reports | Tags | Planned | Engineering | Tag signed; audit report attached to the release |

### F — Governance artifacts

| ID | Artifact | Kind | Status | Owner | Check |
|---|---|---|---|---|---|
| F-01 | LICENSE, NOTICE, AUTHORS, CITATION | Files | Done | Author | Present at the root; author named identically in each |
| F-02 | CONTRIBUTING, SUPPORT, SECURITY | Files | Done | Author | Each names a route and a response time |
| F-03 | Issue and pull-request templates | Files | Done | Engineering | A pull request cannot merge without the checklist |
| F-04 | Work registry | Document | Done | Author | `L1.4`, `L1.5` — IDs unique and resolvable |
| F-05 | Handoff record | Document | Done | Author | Names the next action and its owner |
| F-06 | Decision record — internal | Document | Done | Author | Every open decision names what it blocks |

**Totals: 13 specification · 10 code · 7 test · 7 interface · 7 operational · 6 governance = 50
artifacts.** Twenty-seven exist; twenty-three are planned.

## Ownership

| Owner | Accountable for |
|---|---|
| **Architecture** | Models 2 and 3, contracts, storage, events, standards |
| **Product** | Model 1, surfaces, regime presets |
| **Compliance** | Model 4, roles, rule semantics, claim schema |
| **Engineering** | Code, tests, CI, the verifier |
| **Design** | Model 5 |

One name per artifact. Shared ownership means nobody notices when it rots.

## The rule that makes this hold

**An artifact that is not verified does not count as existing.**

Every row above names a check. Where the check is a document consistency rule it runs in
[`verify.py`](../verify.py) on every commit. Where it is a code invariant it runs in the test suite.
Where it is neither, the artifact is a claim rather than a deliverable — and the register says so.

## Related

- [28 — Product model](28-product-model.md)
- [29 — Data model](29-data-model.md)
- [30 — Interaction model](30-interaction-model.md)
- [31 — Verification](31-verification.md)
- [24 — Work registry](24-work-registry.md)
