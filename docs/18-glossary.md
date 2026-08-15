# 18 — Glossary

| Term | Meaning |
|---|---|
| **Attestation** | A signed statement by a named party that a datapoint has a given value, with an issue date and an expiry. Distinct from the value itself. |
| **Attestor** | A party permitted to record attestations — an auditor, valuer, oracle or Stobox. |
| **Claim** | A fact about an identity subject: `urwa.jurisdiction.country`, `us.regd.accredited`. Stored hashed. |
| **Claim key** | `keccak256` of a dotted namespace, e.g. `eu.mifid2.professional`. Anyone may define keys outside `urwa.*`. |
| **Claims plane** | The layer holding identity claims. Extensible without any core upgrade. |
| **Commitment** | A salted hash of a datapoint. What goes on chain in place of the value. |
| **Granted** | Disclosure tier: commitment on chain, value disclosed off chain under a named, expiring access grant. |
| **Diamond** | EIP-2535 proxy pattern. Routes calls to facets by `delegatecall`. |
| **Facet** | A contract providing a set of functions to a diamond, sharing its storage. |
| **Fail closed** | On any ambiguity or failure the system blocks rather than permits. |
| **Frozen total** | `getFrozenTokens` — admin freeze plus unexpired lockups. May exceed balance. |
| **Handshake** | The bidirectional passport-token link. The token declares; the passport confirms. Only the confirmed state is provenance. |
| **Immutable selector** | A function registered against the diamond itself, which `LibDiamond` will not replace or remove. |
| **Ledger plane** | Balances, supply and ERC-20 entry points. Immutable. |
| **Lockup** | A dated restriction on part of a balance. Expires by timestamp, no transaction needed. |
| **Package** | A named, versioned set of facet cuts the factory can deploy. |
| **Passport** | The Asset Passport — the record of what an asset actually is, anchored by snapshot. Proprietary to Stobox. |
| **Policy plane** | The compliance facet, policy set and rules. Replaceable in one transaction. |
| **Policy set** | The contract composing rules into AND-groups of OR-alternatives. |
| **Preset** | A named, audited policy composition, e.g. `RegD506c`. |
| **Regulator tier** | Disclosure tier: commitment on chain, value disclosed only to a supervisor under legal basis, and logged. |
| **Freshness window** | Per-group age limit after which a datapoint is provably stale rather than merely old. |
| **Red flag** | One of four binary structural checks: audit, legal opinion, custody, redemption defined. |
| **Regime** | The applicable legal framework — MiFID II, Reg D, Reg S, MiCA ART, MiCA EMT. Orthogonal to asset class. |
| **Rule** | A pure predicate contract answering whether a transfer may proceed. Never writes state. |
| **Snapshot** | A Merkle root over every datapoint commitment, anchored on chain. Sometimes called the digest. |
| **Sparse Merkle tree** | A tree over the full key space, allowing proof that a datapoint is **absent**, not only present. |
| **Subject** | An identity, as distinct from a wallet. One subject may hold many wallets. Holder caps count subjects. |
| **Trust list** | Addresses that bypass **rules** — never the pause or frozen-balance checks. |
| **uRWA** | Universal Real World Asset — the informal name of ERC-7943. |
| **Disclosure tier** | Granted or regulator. Determines the disclosure path, never whether the datapoint is committed — every datapoint is. |
| **`whyBlocked`** | Diagnostic returning the first failing stage, the rejecting rule and a reason. Same code path as enforcement. |

## Role names

| Role | Short description |
|---|---|
| `UPGRADE_ADMIN` | Facets and module swaps. Cannot move value. |
| `ISSUER_ADMIN` | Operational configuration and granting operational roles. |
| `SUPPLY_OPERATOR` | Issue, redeem, distribute. |
| `COMPLIANCE_OFFICER` | Freeze, lockups, pause, forced operations. |
| `FACTORY_ADMIN` | Factory configuration only. Never controls a deployed token. |
| `OFFERING_OPERATOR` | Offering lifecycle and refunds. |
| `PASSPORT_ISSUER` | Mint passports, anchor snapshots, confirm links. |
| `ATTESTOR` | Record attestations within an engagement scope. |

## Interface ids

| Interface | Id |
|---|---|
| `IERC7943Fungible` | `0x3edbb4c4` |
| `IERC20` | `0x36372b07` |
| `IERC165` | `0x01ffc9a7` |

## Related documents

- [01 — Overview](01-overview.md)
- [05 — Roles](05-roles.md)
- [15 — Standards](15-standards.md)
