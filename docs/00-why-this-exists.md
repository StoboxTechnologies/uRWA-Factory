# 00 — Why this exists

## The short version

Private markets run on paper, spreadsheets and trust in intermediaries. Tokenization was supposed to
fix that, and largely has not — because putting an asset on a blockchain is the easy part, and making
it *behave like a regulated instrument* is the hard part.

This project is the hard part, given away.

---

## The problem

A public equity settles in a system built over decades: a central depository, a transfer agent, a
registrar, a clearing house. A private asset — a building, a fund, a private company, a commodity
inventory — has none of that. Its ownership record is a document. Its transfer is an email, a lawyer
and a wire.

That has three consequences.

| Consequence | What it costs |
|---|---|
| **Transfers are slow and manual** | Weeks per transaction, legal fees on both sides |
| **Compliance is retrospective** | A non-compliant transfer is discovered *after* it settled |
| **Ownership is opaque** | Nobody outside the issuer can verify the holder register |

Tokenization promised to fix all three. The first wave mostly did not, for a specific reason: an
ordinary ERC-20 token can be sent by anyone to anyone. A security cannot. Issuers were therefore left
with a token that moved freely and a legal wrapper that said it must not, and the gap between them
went back to being filled by lawyers and spreadsheets.

## What actually needed solving

A security token has to answer one question, correctly, on every transfer, forever:

> **May this specific person hold this specific asset, right now, in this amount?**

Answering it requires four things at once, and every attempt that lacks one of them fails:

1. **Identity** — who is this wallet, and what is verified about them?
2. **Rules** — what does this asset's regulatory regime permit?
3. **Enforcement** — the transfer must be *impossible*, not merely discouraged
4. **Legibility** — a third party must be able to check all of the above without asking the issuer

Existing approaches solve one or two. ERC-1400 defined restrictions but not identity. ERC-3643 (T-REX)
solves all four and is the proven incumbent — but arrives as one vendor's complete framework, which
means adopting it is adopting them.

## What changed in 2026

**ERC-7943 reached Final status.** It standardises the *interface* for a real-world-asset token — how
to ask whether a transfer is allowed, how to freeze, how to force a transfer under legal compulsion —
while deliberately leaving identity and compliance logic to the implementer.

That is a genuinely different design choice. ERC-3643 is a complete system. ERC-7943 is a shared
socket that many systems can implement. It makes portability possible: an exchange, a custodian or a
lending protocol integrates once and reads every conformant token.

But a standard is only real when there is tooling. In 2026 there is a reference *token* for ERC-7943.
There is no reference *issuance stack* — no open factory, no policy engine, no rule library, no
conformance suite. **That gap is what this repository fills.**

---

## What Stobox is

| | |
|---|---|
| **Founded** | 2018 — eight years in this market as of 2026 |
| **Positioning** | Intelligence and Tokenization of Real-World Assets |
| **Standards** | Backer of ERC-7943; author of the STV3 protocol |
| **Industry body** | Founding Member, Corporate tier, of the STO Foundation |
| **Published methodology** | The AXIS asset-evaluation methodology is public under CC BY 4.0 |

Stobox has spent those eight years on the unglamorous parts: what a compliant issuance actually
requires, which jurisdictions demand what, what an institutional buyer asks for in diligence, and
where tokenization projects fail. This repository is that experience turned into contracts.

### What Stobox provides

| Product | What it does |
|---|---|
| **Stobox Intelligence** | The verified record of a company and its assets — organised, sourced, and readable by counterparties and AI agents |
| **Stobox Compass** | The console: readiness assessment, structuring, document generation, issuance and investor lifecycle |
| **StoboxDID** | On-chain decentralised identity — who may hold, from where, under which category |
| **STV3** | The protocol behind deployed Stobox tokens — compliance enforced at the transfer layer |
| **STBU** | The utility and access token of the ecosystem, live on Base |
| **uRWA Factory** | *This repository.* The open issuance stack, free to anyone |

---

## Why give the factory away

This is the question every reader asks, so it gets a direct answer.

### 1. The primitive is commoditised either way

A compliant token contract is going to exist as open source in 2026 whether or not Stobox publishes
one. Charging for a contract that someone else will give away for free is not a business model — it is
a delay.

### 2. A standard with one implementer is not a standard

ERC-7943's value to everyone, including Stobox, depends on many issuers using it and many platforms
reading it. A closed implementation would slow the very adoption that makes the standard useful. The
fastest way to make the socket universal is to hand out the tooling.

### 3. Value does not live in the contract

What is genuinely hard to reproduce is not the code. It is knowing *what is true about an asset* and
being able to prove it: the data model, the attestor relationships, the verification pipeline, the
judgement encoded in eight years of doing this. A fork gets the token. It does not get the record.

**The token says who may hold it. The passport says what it actually is.** The first is a public good.
The second is a service.

### 4. Trust is earned by publishing, not by claiming

A compliance system nobody can inspect is a compliance system nobody should trust. Institutions
increasingly ask to see the enforcement logic, not a description of it. Publishing removes that
objection permanently.

### 5. It is verifiable, not rhetorical

The honest version of "open source" is testable, so it is a build step. On every commit, CI deploys
the entire stack to a clean chain with **no Stobox contract present** and runs an end-to-end token
sale. If that fails, the claim has broken and the build stops. The default identity adapter is a plain
allowlist, the fee hook is zero, and no reference to STBU or to any Stobox address exists anywhere in
the code. See [19 — Open boundary](19-open-boundary.md).

---

## What this gives each audience

### For issuers

| Benefit | Concretely |
|---|---|
| **Compliance that cannot be bypassed** | A prohibited transfer does not fail an audit later — it does not execute |
| **Rules change without a migration** | New regulation means swapping one contract. Holders do not move; nothing is re-minted |
| **No vendor lock-in** | The contracts are MIT. Leaving Stobox does not mean leaving your token |
| **Cheap enough to be default** | Minimal proxies on Base — a compliant deployment targets under a dollar |
| **Auditable by your counterparties** | Rules are public and machine-readable; an investor checks eligibility before buying |
| **Fewer support cycles** | `whyBlocked` tells an investor exactly why a transfer failed, in plain language |
| **Institutional-grade separation of duties** | Four separated roles ship as the default, not as an option |

### For the market and the developer community

| Benefit | Concretely |
|---|---|
| **One integration, every token** | An exchange or custodian implements ERC-7943 once |
| **A conformance suite anyone can run** | Published separately, so competitors can adopt it without adopting us |
| **A rule library that is extensible without permission** | A Swiss issuer adds `ch.finma.qualified` and a rule; no core change, no approval |
| **A reference for the standard** | Worked examples of how to implement ERC-7943 correctly, including the traps we hit |
| **Agent-ready by construction** | Free, non-reverting pre-flight checks mean an autonomous agent can ask before acting |

### For investors and partners in Stobox

| Benefit | Concretely |
|---|---|
| **Distribution** | Every fork and every third-party deployment widens the standard Stobox is positioned in |
| **The moat is where it is defensible** | Data, attestor relationships and curation — none of which a fork obtains |
| **Reduced competitive risk** | Being the reference implementation is more durable than being one closed vendor among several |
| **Credibility with institutions** | Published, inspectable enforcement logic answers the question institutions actually ask |
| **A clear commercial boundary** | Contracts free; attestation, hosted issuance and support commercial. Stated in writing, [enforced in CI](19-open-boundary.md) |

---

## How it works, in one page

Three layers with different rules about what may change:

| Layer | Contains | Can it change? |
|---|---|---|
| **Ledger** | Balances, supply, transfers | **Never.** Enforced by code, not policy |
| **Policy** | Which transfers are permitted | **Freely.** One transaction, no migration |
| **Claims** | What is verified about a wallet | **Extensibly.** Anyone adds new claim types |

Every transfer passes one pipeline: paused? → trusted system address? → may the sender send? → may the
recipient receive? → are enough tokens unfrozen? → do the rules pass? Only then does value move.

The consequence that matters: **a compliance bug can stop trading. It can never corrupt supply.** The
worst outcome of any failure in the policy layer is that transfers halt — never that balances are
wrong. For a regulated instrument that is the correct failure direction, and it is guaranteed
structurally rather than promised.

Details in [02 — Architecture](02-architecture.md) and [08 — Compliance pipeline](08-compliance-pipeline.md).

---

## What we are not claiming

Stated plainly, because a document like this is usually where overstatement creeps in.

- **This is not a regulatory approval.** The system enforces the rules it is configured with. Whether
  those rules are the right ones for a given asset is the issuer's determination with their counsel.
- **This is not audited yet.** The project is at specification stage. No mainnet issuance until an
  audit clears. See [SECURITY.md](../SECURITY.md).
- **This does not make an asset liquid.** Compliant transferability is a precondition for a market,
  not a market.
- **This does not custody anything.** The contracts move tokens. The underlying asset sits wherever
  its legal structure puts it.
- **Stobox is a software and infrastructure provider,** not an adviser. We supply mechanisms and
  templates. Nothing here is legal, financial or investment advice.

Market-size and client-count figures are deliberately absent from this document. Where such figures
appear in Stobox materials they carry their own sources and dates; a technical repository is the wrong
place to restate them.

---

## Where to go next

| You are | Start at |
|---|---|
| Evaluating whether to use this | [01 — Overview](01-overview.md) |
| An engineer | [02 — Architecture](02-architecture.md), then [07 — Function reference](07-functions.md) |
| A compliance officer | [10 — Rules](10-rules.md), [05 — Roles](05-roles.md) |
| An integrator | [15 — Standards](15-standards.md), [07 — Function reference](07-functions.md) |
| Assessing the open-source claim | [19 — Open boundary](19-open-boundary.md) |
| Planning the work | [20 — Development plan](20-development-plan.md) |
