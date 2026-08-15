<div align="center">

# uRWA Factory

**Open-source factory for compliant real-world-asset security tokens, built on ERC-7943.**

[![Licence: MIT](https://img.shields.io/badge/Licence-MIT-166B5C.svg)](LICENSE)
[![Standard: ERC-7943](https://img.shields.io/badge/Standard-ERC--7943-166B5C.svg)](https://eips.ethereum.org/EIPS/eip-7943)
[![Interface: 0x3edbb4c4](https://img.shields.io/badge/Interface-0x3edbb4c4-4A5C58.svg)](docs/15-standards.md)
[![Chain: Base](https://img.shields.io/badge/Chain-Base-4A5C58.svg)](docs/16-deployment.md)
[![Status: Specification](https://img.shields.io/badge/Status-Specification-8A5712.svg)](docs/20-development-plan.md)

**[📖 Documentation](https://stoboxtechnologies.github.io/uRWA-Factory/)** ·
**[🖥 Prototypes](https://stoboxtechnologies.github.io/uRWA-Factory/prototypes/)** ·
[Why this exists](docs/00-why-this-exists.md) ·
[Architecture](docs/02-architecture.md) ·
[Function reference](docs/07-functions.md) ·
[Author](docs/AUTHOR.md)

</div>

---

A security token has to answer one question, correctly, on every transfer, forever:

> **May this specific person hold this specific asset, right now, in this amount?**

An ordinary ERC-20 cannot answer it. This repository is a complete, free implementation that can.

Anyone can deploy their own factory and issue tokens with **no dependency on Stobox**. Stobox
Technologies operates one instance and sells an attestation service on top. **The contracts are free;
the attestation is the product.**

## The idea in three sentences

1. **The standard is open.** A token that refuses transfers to anyone who may not hold it.
2. **The factory is open.** One transaction deploys that token, its treasury and its rules.
3. **The attestation is a service.** The Asset Passport records what the asset actually is, signed by
   independent attestors.

## Architecture in one table

Three planes with different rules about what may change:

| Plane | Contains | Can it change? | Gives you |
|---|---|---|---|
| **Ledger** | Balances, supply, ERC-20 entry points | **Never** — enforced by code, not policy | Resilience |
| **Policy** | Compliance facet, policy set, rules | **Freely** — one transaction, no migration | Agility |
| **Claims** | Identity claims, namespaced keys | **Extensibly** — anyone adds new types | Customization |

**A compliance bug can stop trading. It can never corrupt supply.** That single boundary is the whole
architecture — and it is already enforced by the STV3 base this work builds on, where `LibDiamond`
refuses to replace or remove any selector registered against the diamond itself.

Every transfer passes one pipeline:

```
paused? → both trusted? → canSend(from)? → canReceive(to)? → enough unfrozen? → rules pass? → execute
```

## Documentation

Everything is in [`docs/`](docs/), rendered one page per document at the
**[documentation site](https://stoboxtechnologies.github.io/uRWA-Factory/)** — with the whole corpus
on [a single page](https://stoboxtechnologies.github.io/uRWA-Factory/all.html) for searching and printing.

<table>
<tr><td valign="top" width="50%">

**Start here**

| # | Document |
|---|---|
| 00 | [Why this exists](docs/00-why-this-exists.md) |
| 01 | [Overview](docs/01-overview.md) |
| 02 | [Architecture](docs/02-architecture.md) |
| 03 | [Contracts](docs/03-contracts.md) |
| 04 | [Storage](docs/04-storage.md) |
| 05 | [Roles](docs/05-roles.md) |
| 06 | [States](docs/06-states.md) |
| 07 | [Function reference](docs/07-functions.md) |
| 08 | [Compliance pipeline](docs/08-compliance-pipeline.md) |
| 09 | [Identity and DID](docs/09-identity-did.md) |
| 10 | [Rules](docs/10-rules.md) |
| 11 | [Asset Passport](docs/11-passport.md) |

</td><td valign="top" width="50%">

**Going deeper**

| # | Document |
|---|---|
| 12 | [Offerings](docs/12-offering.md) |
| 13 | [Treasury](docs/13-treasury.md) |
| 14 | [Events and errors](docs/14-events-errors.md) |
| 15 | [Standards](docs/15-standards.md) |
| 16 | [Deployment](docs/16-deployment.md) |
| 17 | [Security](docs/17-security.md) |
| 18 | [Glossary](docs/18-glossary.md) |
| 19 | [Open boundary](docs/19-open-boundary.md) |
| 20 | [Development plan](docs/20-development-plan.md) |
| 21 | [Interface specification](docs/21-interface-specification.md) |
| 22 | [Agents and settlement](docs/22-agents-and-settlement.md) |
| 23 | [Testing plan](docs/23-testing-plan.md) |
| 24 | [Work registry](docs/24-work-registry.md) |
| 25 | [Design system](docs/25-design-system.md) |
| 26 | [Handoff](docs/26-handoff.md) |
| 27 | [Model inventory](docs/27-model-inventory.md) |
| 28 | [Product model](docs/28-product-model.md) |
| 29 | [Data model](docs/29-data-model.md) |
| 30 | [Interaction and API model](docs/30-interaction-model.md) |
| 31 | [Verification framework](docs/31-verification.md) |
| 32 | [FAQ](docs/32-faq.md) |

</td></tr>
</table>

## Prototypes

All four surfaces at **[the prototypes index](https://stoboxtechnologies.github.io/uRWA-Factory/prototypes/)** — deploy console, token console, public verifier and investor page. Nothing connects to a chain; every value maps to a real function in the specification.

## Status

**Specification stage. No implementation yet.** The [handoff](docs/26-handoff.md) records what is delivered, what is deliberately not, and how to verify both without asking anyone. The full work breakdown — 79 items with dependencies, handoff contracts and review gates — is in the [work registry](docs/24-work-registry.md). The design is complete and reviewable; Phase 0 — the
compiling interface package — is next. See the [development plan](docs/20-development-plan.md).

| Phase | Delivers | State |
|---|---|---|
| 0 | Interface package, storage layout frozen | Next |
| 1 | Core token, factory, conformance kit | Planned |
| 2 | Policy engine, rule library, DID adapter | Planned |
| 3 | Treasury, offerings, agent authority, atomic DvP | Planned |
| 4 | Passport, proofs, verifier library | Planned |
| 5 | Interfaces and SDK | Planned |
| 6 | Audit, then mainnet | Planned |

**No mainnet issuance until an audit clears.**

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

The credibility test is a build step, not a promise: **CI deploys the whole stack to a clean chain with
no Stobox contract present and runs an end-to-end sale on every commit.** If that fails, the
open-source claim has broken and the build stops. Details in
[19 — Open boundary](docs/19-open-boundary.md).

## Build

```bash
forge build                 # once the interface package lands
forge test
python3 build-docs.py       # regenerates the documentation site
python3 verify.py           # 36 checks across structure, documents and models
python3 verify.py --self-test   # proves those 36 checks can still fail
```

The [verification framework](docs/31-verification.md) has six levels. Thirty-six checks run today;
the rest arrive with the code they test. The last level checks the checks: every one ships with a
deliberately broken fixture, and any check that passes its own broken input is reported dead rather
than counted as a pass. It found six on its first run.

## Author

### Gene Deyev

**Founder & CEO, [Stobox Technologies](https://stobox.io)** — [full profile →](docs/AUTHOR.md)

[Profile](https://stobox.io/team/gene-deyev) ·
[GitHub](https://github.com/genedeyev) ·
[Email](mailto:gd@stoboxplatform.com) ·
[Stobox](https://stobox.io)

Founded Stobox in 2018 and has led it since. Author of the Stobox Tokenization Framework and
co-author of one of the earliest practitioner guides to security token offerings, registered with the
U.S. Copyright Office in 2019. Public backer of ERC-7943.

This project is released in a **personal capacity**. Copyright is held personally; the repository is
hosted under the Stobox organisation for continuity, not ownership. Stobox Technologies is one user of
this software among others — it operates one factory instance and sells the attestation service that
sits on top, and neither is required to use anything here.

The affiliation is disclosed because you should know who wrote your compliance layer and what their
interests are.

## Contributing

Development is done by Stobox. Releases are published; **forks are welcome and expected.** Issues are
accepted with no promised response time, and there is no roadmap vote — stated plainly because the
complaint about "open source in name only" comes from unstated expectations rather than from their
absence.

Rules are the intended extension point and need no permission from anyone. See
[CONTRIBUTING.md](CONTRIBUTING.md) and [SUPPORT.md](SUPPORT.md).

## Security

Do not open a public issue for a vulnerability. See [SECURITY.md](SECURITY.md).

## Licence and name

MIT — see [LICENSE](LICENSE). The licence grants rights to the code, not to the name. A fork may state
that it *passes the uRWA conformance suite*; it may not describe itself as built or certified by
Stobox. See [NOTICE](NOTICE).

## Disclaimer

This project supplies mechanisms and templates. Which rules apply to a given asset, and the
consequences of that choice, are the issuer's decision. Nothing here is legal, financial or investment
advice.
