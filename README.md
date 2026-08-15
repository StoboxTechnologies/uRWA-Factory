# uRWA Factory

Open-source factory for compliant real-world-asset security tokens, built on
[ERC-7943 (uRWA)](https://eips.ethereum.org/EIPS/eip-7943).

Anyone can deploy their own factory and issue tokens with no dependency on Stobox. Stobox operates one
instance, charges an STBU fee on it, and offers a proprietary attestation service — the Asset Passport
— on top. **The contracts are free; the attestation is the product.**

| | |
|---|---|
| **Licence** | MIT |
| **Chain** | Base (primary) · Arbitrum One (secondary) |
| **Language** | Solidity 0.8.28 |
| **Toolchain** | Foundry |
| **Token standard** | ERC-20 + ERC-7943 fungible (`0x3edbb4c4`) |
| **Architecture** | Diamond, EIP-2535 |
| **Status** | **Specification — no implementation yet** |

## The idea in three sentences

1. **The standard is open.** A token that refuses transfers to anyone who may not hold it.
2. **The factory is open.** One transaction deploys that token, its treasury and its rules.
3. **The attestation is ours.** The Asset Passport records what the asset actually is, signed by
   independent attestors. That is the paid service.

## Why it is built this way

Three planes with different mutability rules:

| Plane | Contains | Mutability | Delivers |
|---|---|---|---|
| **Ledger** | Balances, supply, ERC-20 entry points | Immutable — enforced by code | Resilience |
| **Policy** | Compliance facet, policy set, rules | Replaceable in one transaction | Agility |
| **Claims** | Identity claims, namespaced keys | Extensible without upgrade | Customization |

A policy bug can stop transfers. It can never corrupt supply. That single boundary is the whole
architecture, and it is already enforced by the STV3 base this work builds on.

## Documentation

| # | Document | Covers |
|---|---|---|
| 01 | [Overview](docs/01-overview.md) | What this is, who it is for, what it does not do |
| 02 | [Architecture](docs/02-architecture.md) | The three planes and why the boundaries fall there |
| 03 | [Contracts](docs/03-contracts.md) | Every contract and sub-contract |
| 04 | [Storage](docs/04-storage.md) | Every struct and variable |
| 05 | [Roles](docs/05-roles.md) | Every role and the full permission matrix |
| 06 | [States](docs/06-states.md) | All thirteen state machines |
| 07 | [Function reference](docs/07-functions.md) | Every signature, mutability and access rule |
| 08 | [Compliance pipeline](docs/08-compliance-pipeline.md) | How a transfer is validated |
| 09 | [Identity and DID](docs/09-identity-did.md) | Adapters, claim schema, the revert trap |
| 10 | [Rules](docs/10-rules.md) | Rule engine, library and presets |
| 11 | [Asset Passport](docs/11-passport.md) | Snapshots, disclosure, the handshake |
| 12 | [Offerings](docs/12-offering.md) | Primary sales, refunds, allocations |
| 13 | [Treasury](docs/13-treasury.md) | Custody of supply and payments |
| 14 | [Events and errors](docs/14-events-errors.md) | Complete catalogue |
| 15 | [Standards](docs/15-standards.md) | Every standard and conformance detail |
| 16 | [Deployment](docs/16-deployment.md) | Sequence, parameters, checklist |
| 17 | [Security](docs/17-security.md) | Threat model, failure modes, invariants |
| 18 | [Glossary](docs/18-glossary.md) | Terms |
| 19 | [Open boundary](docs/19-open-boundary.md) | Exactly what is published and what is not |
| 20 | [Development plan](docs/20-development-plan.md) | Six phases with exit criteria |
| 21 | [Interface specification](docs/21-interface-specification.md) | Wallet connection and all four surfaces |
| 22 | [Agents and settlement](docs/22-agents-and-settlement.md) | Agent mandates and atomic DvP |
| 23 | [Testing plan](docs/23-testing-plan.md) | Layers, invariants, coverage, CI |

A single-page HTML build of everything is at
[`urwa-documentation.html`](urwa-documentation.html), generated from the Markdown so the two cannot
diverge.

## Build

```bash
forge build
forge test
python3 build-docs.py     # regenerates urwa-documentation.html from README.md + docs/*.md
```

## What is open, and what is not

| Open — MIT, in this repository | Stobox proprietary |
|---|---|
| Token, all facets, factory, treasury | Asset Passport implementation |
| Policy engine and rule library | Data-point schemas and intelligence |
| Three identity adapters | Attestor network and curation |
| Offering registry | Compass console |
| Passport interface, handshake, reference implementation | The Stobox factory instance and its fee |
| Snapshot format, proof format, verifier library | |
| Agent authority and atomic DvP | |
| ERC-7943 conformance kit | |

The credibility test is a build step, not a promise: CI deploys the whole stack to a clean chain with
no Stobox contract present and runs an end-to-end sale on every commit. See
[19 — Open boundary](docs/19-open-boundary.md).

## Contributing

Development is done by Stobox. Releases are published; forks are welcome. Issues are accepted with no
promised response time, and there is no roadmap vote. See [SUPPORT.md](SUPPORT.md) and
[CONTRIBUTING.md](CONTRIBUTING.md).

## Security

Do not open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).

## Licence and name

MIT — see [LICENSE](LICENSE). The licence grants rights to the code, not to the name. A fork may state
that it *passes the uRWA conformance suite*; it may not describe itself as built or certified by
Stobox. See [NOTICE](NOTICE).

## Disclaimer

Stobox is a software and infrastructure provider. This project supplies mechanisms and templates.
Which rules apply to a given asset, and the consequences of that choice, are the issuer's decision.
Nothing here is legal, financial or investment advice.
