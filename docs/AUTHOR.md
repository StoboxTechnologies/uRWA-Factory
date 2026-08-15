# The author

## Gene Deyev

**Founder & CEO, [Stobox Technologies](https://stobox.io)**

- Profile — [stobox.io/team/gene-deyev](https://stobox.io/team/gene-deyev)
- GitHub — [@genedeyev](https://github.com/genedeyev)
- Email — [gd@stoboxplatform.com](mailto:gd@stoboxplatform.com)

---

## Background

Gene founded Stobox in 2018, in the first wave of the security-token industry, and has led it since —
eight years as of 2026. The company moved from STO technology and consulting to a platform covering
readiness, raising and tokenization, and his thesis has not changed across that span: **the barrier to
tokenization was never the technology — it is whether the business is ready.**

Before Stobox he built and exited two companies outside crypto: an Audi and Volkswagen dealership,
where he grew national market share from 8% to 42% before selling it, and Dolphin Online Trading.

That order matters for reading this repository. The design decisions here — immutable ledger,
replaceable policy, mandatory reasons on privileged actions, refusing to gate the primitive — come
from operating regulated businesses and from watching tokenization projects fail for operational
reasons rather than technical ones.

## Published work

| Work | Detail |
|---|---|
| **Stobox Tokenization Framework** | Author. The eight-phase methodology behind Stobox client engagements |
| **How to Attract Investments with STO: A Practical Guide** | Co-author with Borys Pikalov, completed 2019 — one of the earliest practitioner-authored guides to security token offerings |
| **AXIS methodology** | Published by Stobox under CC BY 4.0 |
| **uRWA Factory** | This repository — released personally |

The 2019 book is registered with the U.S. Copyright Office, effective **28 October 2019**,
registration **TXu 2-176-719** —
[public record](https://publicrecords.copyright.gov/detailed-record/31312513). It is dated,
government-verified evidence of documented STO and tokenization work predating the current RWA wave.

## Standards

Public backer of **ERC-7943 (uRWA)**, the standard this project implements. Backer rather than author:
the EIP was written by others, and the contribution here is tooling and adoption rather than
authorship of the specification.

## Speaking

| Year | Event |
|---|---|
| 2022 | AIBC Malta — Startup Village and a tokenization masterclass |
| 2024 | Web Summit Lisbon — GROWTH startup programme, Growth Stage talk |
| 2024 | 6th Annual Blockchain for Europe Summit, Brussels — panel, *Tokenization: Smart Assets vs. Dumb Liabilities* |
| 2025 | ETH Bratislava — RWA panel and solo talk |
| 2026 | Chain of Blocks Summit, Valletta — keynote, *Tokenization as a New Financial Primitive* |

---

## On this project specifically

> I have spent eight years watching this market almost work.
>
> The technology has not been the obstacle for a long time. Every serious attempt runs into the same
> wall: a token that moves freely and a legal wrapper that says it must not. The gap between them gets
> filled with lawyers, spreadsheets and hope — which is exactly what tokenization was supposed to
> remove.
>
> Solving that properly requires a piece of infrastructure that behaves the same way for everyone. Not
> a product with my name on it that each issuer licenses separately, but a shared primitive that an
> exchange, a custodian, a regulator and a competitor can all read the same way. Infrastructure of
> that kind does not emerge from a vendor's roadmap. Somebody has to put it in the open and accept
> that others will use it without paying.
>
> So this is my contribution to that. The token, the factory, the rule engine, the identity adapters
> and the conformance tests are free, MIT, and carry no dependency on my company. Anyone can deploy
> the whole system on a chain where Stobox does not exist — and a build step proves it on every
> commit, because a claim like that is worth nothing unless it is tested.
>
> I am not being altruistic about it. A compliant token contract is going to be commoditised in 2026
> whether or not I publish one; charging for it would be a delay, not a business model. And a standard
> with a single implementer is not a standard — ERC-7943 becomes useful to me only when many issuers
> use it and many platforms read it. What is genuinely hard to reproduce was never the contract. It is
> knowing what is true about an asset and being able to prove it.
>
> There is also a reason that has nothing to do with strategy. A compliance system nobody can inspect
> is a compliance system nobody should trust. If code decides who may own a regulated asset, that code
> should be readable by the people it decides about. I would not want to hold a security whose
> transfer rules I was not allowed to see, and I do not think I should ask anyone else to.
>
> — **Gene Deyev**, 15 August 2026

---

## Disclosure

This project is released by Gene Deyev in a **personal capacity**. Copyright is held personally and
the licence you receive comes from the author, not from Stobox Technologies.

The repository is hosted under the `StoboxTechnologies` GitHub organisation for continuity and
discoverability. **Hosting is not ownership.**

Stobox Technologies has a commercial interest in this ecosystem, stated openly rather than hidden in
the contracts: it operates one factory instance, and it sells the Asset Passport attestation service
that sits on top of the open primitive. Neither is required to use anything in this repository, and
the boundary between the two is written down in [19 — Open boundary](19-open-boundary.md) and
enforced in CI.

The affiliation is disclosed because you should know who wrote your compliance layer and what their
interests are.

## Related

- [00 — Why this exists](00-why-this-exists.md)
- [19 — Open boundary](19-open-boundary.md)
- [AUTHORS](../AUTHORS) · [NOTICE](../NOTICE) · [LICENSE](../LICENSE)
