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
allowlist, the fee hook is zero, and no STBU check exists anywhere in the code.

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
