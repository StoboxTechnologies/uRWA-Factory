# 32 — Frequently asked questions

57 questions, answered from the specification rather than from marketing. Every answer links to the
document that carries the detail. Nothing here is legal, financial or investment advice.

## What this is

### What is uRWA Factory, in one sentence?

An open-source factory that deploys real-world-asset security tokens which enforce their own transfer
rules on chain, built on ERC-7943 and released under MIT. See [01 — Overview](01-overview.md).

### What problem does it actually solve?

A security token has to answer one question correctly on every transfer, forever: may this specific
person hold this specific asset, right now, in this amount? An ordinary ERC-20 cannot answer it at
all. See [00 — Why this exists](00-why-this-exists.md).

### Why is it free?

ERC-7943 is Final but has no reference issuance stack. A standard with one implementer is not a
standard, so the tooling is given away rather than sold. The commercial product is the attestation
service that sits on top, not the contracts. See [19 — The open boundary](19-open-boundary.md).

### Do I need Stobox to use it?

No. A fork deploys the whole stack with no Stobox contract in the graph, and a CI job proves it on a
fresh chain on every commit. See [19 — The open boundary](19-open-boundary.md).

### What does it cost to deploy a token?

The open distribution charges no factory fee — an invariant test asserts it is zero. Chain gas is a
diamond constructor plus a treasury clone, targeted at under one dollar on Base. See
[16 — Deployment](16-deployment.md).

### Who is this for?

Issuers deploying an asset, investors who need to know the rules before buying, and integrators who
want one interface that works across every conformant token. See [01 — Overview](01-overview.md).

### Is there any code yet?

No. The project is at specification stage: the design, the interfaces, the models and the prototypes
are complete and reviewable; the Solidity is not written. See
[20 — Development plan](20-development-plan.md).

### Who wrote it and what is their interest?

Gene Deyev, founder and CEO of Stobox Technologies, released in a personal capacity. The commercial
interest is stated openly: Stobox sells the attestation service that sits on top of this, which is
why the boundary is written down and enforced in CI. See [The author](AUTHOR.md).

## Architecture and safety

### What is the three-plane architecture?

A ledger plane that can never change, a policy plane that can change freely in one transaction, and a
claims plane anyone can extend. See [02 — Architecture](02-architecture.md).

### What is the single most important guarantee?

No key in the system can change a balance or the total supply outside the normal issue and redeem
path. A compliance failure stops trading; it never corrupts supply. See [17 — Security](17-security.md).

### How is that enforced, rather than promised?

ERC-20 core selectors are registered against the diamond itself, and `LibDiamond` reverts
`CannotReplaceImmutableFunction` and `CannotRemoveImmutableFunction` for any such selector. It is code,
not governance policy. See [02 — Architecture](02-architecture.md).

### What happens if the compliance layer has a bug?

Transfers stop. Every ambiguous failure resolves toward stopping, and every blocked state has a
one-transaction exit that needs no migration. See [17 — Security](17-security.md).

### Why a diamond instead of a plain proxy?

Modularity with a hard boundary: facets can be swapped independently while the ledger selectors stay
immutable inside the diamond. See [03 — Contracts](03-contracts.md).

### What can a compromised upgrade admin do?

Swap facets, the policy set and the identity registry — which stops transfers. It cannot touch
balances, supply or any immutable ledger selector. See [17 — Security](17-security.md).

### What can a compromised supply operator do?

Mint up to `maxSupply` and move treasury payments. `capLocked` bounds the damage absolutely, because a
locked cap never unlocks. See [17 — Security](17-security.md).

### Can an issuer seize or force-move tokens?

Only where the `EmergencyFacet` is installed, which is opt-in and visible on chain, and only by the
compliance officer, with a reason string and an event. See [07 — Function reference](07-functions.md).

### Is the system upgradeable against the holder's interest?

The upgrade right is real and it is bounded: it can stop the token, never rewrite the ledger. The
configuration that governs it is public and readable at any time. See [05 — Roles](05-roles.md).

## Compliance and rules

### What exactly happens on a transfer?

One pipeline, in order: paused, both parties trusted, `canSend`, `canReceive`, enough unfrozen
balance, rules pass, execute. See [08 — Compliance pipeline](08-compliance-pipeline.md).

### Why that order?

The cheapest and most absolute checks run first, so a blocked transfer costs as little gas as
possible and the reason returned is the first real one. See
[08 — Compliance pipeline](08-compliance-pipeline.md).

### How do I find out why a transfer would fail, before signing?

Call `whyBlocked`. It is a free read that returns the first rule that would refuse, and it is
guaranteed never to revert. See [07 — Function reference](07-functions.md).

### What is a rule?

A stateless external contract implementing `IRule`, deployed once per chain and shared by every token
that installs it. See [10 — Rules](10-rules.md).

### What rules ship with the system?

A library of twelve, including valid identity, jurisdiction allow and deny, US accredited only,
holder caps and lockups. Presets bundle them per regime. See [10 — Rules](10-rules.md).

### Can I write my own rule?

Yes, without asking anyone. `IRule` is open and third-party rules attach to a policy set like any
other. See [10 — Rules](10-rules.md).

### What stops a bad rule from bricking a token?

Every rule call is wrapped in `try/catch` with a per-rule gas ceiling, a rule that reverts or runs
long counts as a reject and emits `RuleFailed`, and the rule count is hard-capped. See
[17 — Security](17-security.md).

### What does the trusted list actually bypass?

Rules only. It never bypasses the pause check or the frozen-balance check. See
[08 — Compliance pipeline](08-compliance-pipeline.md).

## Identity

### How does the token know who someone is?

Through an identity registry adapter behind one interface, with three implementations: a plain
allowlist, an EAS adapter and a StoboxDID adapter. See [09 — Identity and DID](09-identity-did.md).

### Why an adapter instead of a whitelist?

A whitelist answers only whether an address is allowed. Rules need claims — jurisdiction, accreditation,
investor class — and the adapter exposes them under namespaced keys. See
[09 — Identity and DID](09-identity-did.md).

### Does personal data go on chain?

No. Claims are namespaced keys and hashed values; country codes are compared as hashes so no plaintext
code appears in calldata. See [09 — Identity and DID](09-identity-did.md) and
[11 — Asset Passport](11-passport.md).

### What happens when a claim is revoked?

It takes effect on the next transfer. There is no cache to go stale. See
[17 — Security](17-security.md).

### Can one person hold tokens in several wallets?

Yes, and caps still hold: holder caps count subjects, not addresses, so splitting across wallets does
not evade them. See [17 — Security](17-security.md).

## Issuance, treasury and offerings

### What does one deployment produce?

One transaction produces the token, its treasury and its rule set — after which the factory holds no
role, no key and no upgrade right over what it created. See [16 — Deployment](16-deployment.md).

### Why one treasury per token?

So that reservation accounting, payment locking, distribution and refunds are scoped to a single
asset and cannot be entangled across issuances. See [13 — Treasury](13-treasury.md).

### How are tokens sold?

Through the optional offering registry: an offering carries its own parameters, supply path, hold
periods and regime, and can add rules on top of the token-level ones. See [12 — Offerings](12-offering.md).

### Can a purchase be refunded?

Yes, by two paths, and an invariant asserts a purchase can never be refunded twice. See
[12 — Offerings](12-offering.md) and [23 — Testing plan](23-testing-plan.md).

### What is a lockup?

A time-bounded restriction on part of a balance, held in its own storage and composed with freezes
into a single frozen total. It releases itself; no transaction and no approval is needed. See
[07 — Function reference](07-functions.md).

### Can the supply cap be raised later?

Only while the cap is unlocked, and only by the issuer admin. Once locked it never unlocks — that is
an invariant, not a policy. See [05 — Roles](05-roles.md).

## The Asset Passport and the Stobox boundary

### What is the Asset Passport?

A record of what an asset actually is — attested by independent attestors, anchored on chain as a
snapshot root, and linked to a token by a bidirectional handshake. See
[11 — Asset Passport](11-passport.md).

### Can a passport block my transfers?

Not unless you choose it. The passport is descriptive, never dispositive; gating transfers on passport
state requires installing the optional `PassportValidRule`. See [11 — Asset Passport](11-passport.md).

### What happens if Stobox refuses or revokes a confirmation?

The token loses its provenance record and keeps functioning. A token without a passport is fully
functional. See [16 — Deployment](16-deployment.md).

### What is open and what is kept?

Publish the socket, keep the plug. Everything needed to issue, govern and verify a compliant token is
open; knowledge about a specific asset — the data, the scoring, the attestor relationships — is not.
See [19 — The open boundary](19-open-boundary.md).

### What exactly is kept closed?

The Stobox passport implementation, the data-point schemas and registry contents, the scoring and
weighting, the attestor network and curation rules, the ingestion pipelines, the Compass console, and
the configuration of the Stobox factory instance. See [19 — The open boundary](19-open-boundary.md).

### Is the reference passport crippled on purpose?

No. It is complete in mechanism and empty of knowledge: minting, anchoring, the handshake, access
grants, attestation records and proof verification all work. See
[19 — The open boundary](19-open-boundary.md).

### How is the boundary stopped from drifting?

CI enforces it. The build fails on a known Stobox contract address or an STBU reference in contract
source, and an invariant scans source and bytecode. See [19 — The open boundary](19-open-boundary.md).

## Standards, deployment and verification

### Which standards does it implement?

ERC-7943 as the primary compliance interface, plus ERC-20, EIP-2535, ERC-165, ERC-173, ERC-1404,
ERC-2612 and EIP-712. See [15 — Standards](15-standards.md).

### What is the ERC-7943 interface id?

`0x3edbb4c4`. `supportsInterface` returning true for it is an exit criterion for Phase 1. See
[15 — Standards](15-standards.md).

### Why is ERC-1404 still there?

For integrator compatibility: existing tooling reads restriction codes, and supporting it costs
nothing. See [15 — Standards](15-standards.md).

### Which chain does it target?

Base is primary, Base Sepolia is the testnet, Arbitrum One is secondary for continuity with existing
STV3 and StoboxDID deployments. See [16 — Deployment](16-deployment.md).

### Why Base?

The settlement currency, the fee token and the identity attestation infrastructure all live there. See
[16 — Deployment](16-deployment.md).

### Is cross-chain supported?

The seam is retained and CCT-compatible, but it is not wired in v1. See [16 — Deployment](16-deployment.md).

### Has it been audited?

No. There is no mainnet issuance until an audit clears. See
[00 — Why this exists](00-why-this-exists.md) and `SECURITY.md`.

### How will it be tested?

Eight layers — unit, fuzz, invariant, integration, fork, fresh-chain, conformance and gas — with 100%
branch coverage required on the pipeline and the rules, because every branch there is a compliance
decision. See [23 — Testing plan](23-testing-plan.md).

### What is the conformance kit?

An ERC-7943 conformance suite in a separate repository that anyone can run against any token claiming
the standard. See [15 — Standards](15-standards.md).

### How do I check that this documentation is not lying?

Run `python3 verify.py`. It checks structure, document consistency and cross-model consistency, and
`--self-test` proves each check fails on its own fixture. See
[31 — Verification framework](31-verification.md).

### How many phases are there before release?

Six, each ending in something releasable and independently useful, starting with an interface package
that a compiler checks rather than a reader. See [20 — Development plan](20-development-plan.md).

### What licence is it under, and who holds the copyright?

MIT. Copyright is held personally by the author; the repository is hosted under the Stobox
organisation for continuity, not ownership. See [The author](AUTHOR.md).

### Does this make my asset compliant?

No. It enforces the rules it is configured with. Whether those are the right rules for a given asset
is the issuer's determination with their counsel. See [00 — Why this exists](00-why-this-exists.md).

### Does this make my asset liquid?

No. Compliant transferability is a precondition for a market, not a market. See
[00 — Why this exists](00-why-this-exists.md).

## Related documents

- [00 — Why this exists](00-why-this-exists.md)
- [01 — Overview](01-overview.md)
- [18 — Glossary](18-glossary.md)
- [31 — Verification framework](31-verification.md)
