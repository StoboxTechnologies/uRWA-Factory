# 01 — Overview

## What this is

A factory that deploys ERC-20 security tokens which enforce their own compliance. Every transfer is
checked against a configurable rule set before it executes. A transfer that would break the rules does
not fail an audit later — it does not happen.

## Who uses it

| Actor | Uses it to |
|---|---|
| **Issuer** | Deploy a token for an asset, configure rules, run an offering, manage holders |
| **Investor** | Be verified once, then hold and transfer within the rules |
| **Integrator** | Read one standard interface and get a truthful answer about whether a transfer will succeed |
| **Attestor** | Sign evidence about an asset — valuations, audits, reserves |
| **Regulator** | Reconstruct the complete holder register and compliance history from chain data alone |

## The problem

A regular ERC-20 can be sent by anyone to anyone. A security cannot. The gap between those two facts
is normally filled by a transfer agent, a spreadsheet and a lawyer — slow, expensive and, in practice,
retrospective. By the time a non-compliant transfer is noticed it has already settled.

Existing answers have two shapes:

- **ERC-3643 (T-REX)** — a complete framework with its own identity system. Proven, widely deployed,
  but it arrives as one vendor's full stack and is heavy to audit.
- **Bespoke tokens** — every issuer reinvents transfer restrictions, and every integrator has to learn
  a new interface per token.

## The approach

ERC-7943 reached Final status in 2026. It standardises *that* a token can gate transfers, freeze
balances and force a transfer — but deliberately not *how* eligibility is decided. It is an interface,
not a framework.

That leaves a gap: there is a reference token for ERC-7943 (CMTAT v3.2.0) but no reference *issuance
stack* — no open factory, no policy engine, no rule library, no conformance suite. This project is
that stack.

## The whole system, component by component

Twelve contracts and two off-chain services. Nothing here is optional to understand; everything except
the last three is optional to install.

| Component | Does | Installed |
|---|---|---|
| **`uRWAToken`** | The asset itself — an ERC-20 diamond whose transfers run a compliance pipeline | Always |
| **`ComplianceFacet`** | The pipeline: pause, trust, `canSend`, `canReceive`, unfrozen balance, rules | Always |
| **`FreezeFacet`, `LockupFacet`** | Restrict part of a balance, by decision or by date | Always |
| **`MonetaryFacet`** | Issue, redeem, distribute, supply caps | Always |
| **`RolesFacet`** | Four separated roles, none able to do another's work | Always |
| **`EmergencyFacet`** | Forced transfer, mint, burn — seizure under legal compulsion | **Chosen at deployment** |
| **`PolicySet` + rules** | Sixteen stateless rules composed into a regime; swapped in one transaction | Always, contents vary |
| **`IIdentityRegistry`** | Who someone is — one interface, three interchangeable sources | Always |
| **`Treasury`** | Holds issued supply and investor payments; one per token | Always |
| **`OfferingRegistry`** | Primary sales: subscription, allocation, settlement, refunds | Per chain |
| **`uRWAFactory`** | Deploys and wires all of the above in one transaction, then lets go | Per chain |
| **`AgentAuthority`, `AtomicDvP`** | Bounded automation and delivery-versus-payment | Optional |
| **`AssetPassport`** | Committed, attested evidence about the underlying asset | Optional, proprietary |
| **Attestor network** | The people who sign that evidence | Off chain, proprietary |

The split that matters: **the first eleven are MIT and run with no dependency on us.** The last two
are the business.

## An asset from nothing to a traded token

The end-to-end path, with the document that specifies each step.

| # | What happens | Where |
|---|---|---|
| 1 | Issuer picks a regime — Reg D, Reg S, MiCA or their own composition | [10](10-rules.md) |
| 2 | Issuer calls `createToken`; the factory deploys the token, its treasury and its rule set, grants four roles and registers the deployment | [16](16-deployment.md) |
| 3 | Investors are verified once by an identity source and become **subjects**, not addresses | [09](09-identity-did.md) |
| 4 | Supply is issued to the treasury, or minted as it sells | [12](12-offering.md) |
| 5 | An offering opens; investors subscribe; payment is locked until the soft cap is met | [12](12-offering.md) |
| 6 | Soft cap met → settle. Missed → **anyone** can start refunds; no operator can strand the money | [13](13-treasury.md) |
| 7 | Tokens transfer, each one checked against the live rule set before it executes | [08](08-compliance-pipeline.md) |
| 8 | Anyone can ask `canTransfer` and `whyBlocked` for free, before signing anything | [07](07-functions.md) |
| 9 | Compliance freezes, locks, pauses or seizes when it must — every action evented with a reason | [05](05-roles.md) |
| 10 | Trades settle atomically against payment, both legs or neither | [22](22-agents-and-settlement.md) |
| 11 | Evidence about the asset is committed and provable without being disclosed | [11](11-passport.md) |
| 12 | A regulator reconstructs the whole register from events alone | [14](14-events-errors.md) |

Every step above is specified. **None of it is built yet** — see the status section below.

## Where the project actually stands

| | |
|---|---|
| **Specification** | Complete — 34 documents, five models, 50 artefacts registered |
| **Diagrams** | 17, generated from source and checked in CI |
| **Prototypes** | Four surfaces, clickable, wired to nothing |
| **Verification** | 37 automated checks, each proven to fail on its own broken input |
| **Solidity** | Phase 0 done; Phase 1 in progress — ledger plane, compliance pipeline and subject accounting, 36 tests |
| **Audit** | Booked after the core, before any real issuance |
| **Mainnet** | Not until the audit clears |

The order is deliberate: the specification was finished before any implementation began. The storage layout of a diamond cannot be revised once facets hold live balances,
and the compliance semantics cannot be revised once someone's transfer has been refused on them.

## What is open and what is not

| Open — MIT | Stobox proprietary |
|---|---|
| Token contract and all facets | Asset Passport implementation |
| Factory and treasury | Data-point pipeline and intelligence |
| Policy engine and rule library | The recognised attestor set and curation |
| Three identity adapters | Compass console |
| Offering registry | The Stobox factory instance and its STBU fee |
| Passport interface, handshake contract, reference passport | |
| Snapshot and proof format, verifier library | |
| ERC-7943 conformance kit | |

**The credibility test:** a stranger can deploy the entire system on a fresh chain with no Stobox
contract in the dependency graph. In the open distribution the default identity adapter is a plain
allowlist, no fee is charged, and no STBU check exists anywhere in the code. Any fee ever set on
any instance is readable through `fee()` before a transaction.

## What the token guarantees

| Guarantee | Mechanism |
|---|---|
| Balances cannot be rewritten by anyone | ERC-20 core selectors are immutable in the diamond |
| Non-compliant transfers cannot execute | Every value movement passes one pipeline |
| Rules can change without a migration | Policy is an external, swappable contract |
| Compliance failure stops trading, never corrupts supply | Fail-closed by construction |
| Every privileged action leaves a reason on chain | Mandatory reason strings and distinct events |
| Cap table is reconstructible without an indexer | Complete event coverage |

## What the token does *not* do

- It does not decide whether an asset is a security. That is the issuer's determination with their counsel.
- It does not guarantee regulatory compliance. It enforces the rules it was configured with.
- It does not custody the underlying asset.
- It does not price the asset or make markets.

## Related documents

- [02 — Architecture](02-architecture.md)
- [03 — Contracts](03-contracts.md)
- [15 — Standards](15-standards.md)
