# 19 — The open boundary

This document defines exactly what lives in this repository and what does not. It exists because the
line is easy to blur by accident, and once something is published it cannot be unpublished.

## The rule

**Publish the socket. Keep the plug.**

Everything needed to issue, govern and verify a compliant token is open. Everything that constitutes
knowledge *about a specific asset* — the data, the scoring, the attestor relationships — is not.

## What is in this repository

| Component | Why it must be open |
|---|---|
| `uRWAToken` and all facets | The token is the standard. A closed token is not a reference implementation. |
| `PolicySet`, `IRule`, the rule library | Third parties must be able to write and attach rules without permission. |
| Three identity adapters | A fork must run with no Stobox contract in the graph. |
| `Treasury`, `uRWAFactory`, `OfferingRegistry` | Issuance machinery is the product being given away. |
| `IAssetPassport` interface | Integrators must be able to read a passport without our SDK. |
| `PassportLink` — the handshake contract | Provenance must be verifiable by anyone. |
| `ReferencePassport` | A fork needs a working passport or the system is crippled. |
| Snapshot format, proof format, verifier library | A proof only we can verify is worth nothing. |
| `PassportValidRule` | Optional; lets an issuer gate transfers on passport state if they choose. |
| Conformance kit | The reputational centrepiece. |

## What is not in this repository

| Component | Why it stays closed |
|---|---|
| Stobox Passport implementation | The curated attestor set, schema bindings and operational logic |
| Data-point schemas and the registry contents | The 899-row model is the accumulated product work |
| Scoring and weighting | Judgement encoded over years |
| Attestor network and curation rules | Relationships, not code |
| Ingestion, verification and enrichment pipelines | Off-chain infrastructure |
| Compass console | The commercial front end |
| The Stobox factory instance configuration | Including its STBU fee |

## The reference passport — where exactly the line falls

This is the piece most at risk of accidentally giving away the product. The reference implementation
must be **complete in mechanism and empty of knowledge**.

### It contains

- Minting a passport as a locked ERC-721
- Anchoring a snapshot: root, revocation root, version, timestamp, schema version
- The bidirectional handshake: `declareToken`, `confirmToken`, `revokeToken`
- Access grants: group-scoped, always-expiring, revocable
- Attestation records: attestor, group, issued, valid-until, revoked
- Proof verification: `verify` and `verifyAbsence` against the anchored root
- Public-leaf storage and reads

### It does not contain

- **Any datapoint schema.** No codes, no groups, no field definitions. `bytes32 code` is an opaque
  key to the reference implementation.
- **Any scoring.** No weights, no dimensions, no derived numbers.
- **Any attestor list.** `AttestorRegistry` is open, but it ships empty. Who is worth trusting is the
  product.
- **Any ingestion.** Nothing that fetches, parses, normalises or enriches.
- **Any visibility policy.** The three tiers are documented; which datapoint sits in which tier is not.

A fork therefore gets a working commitment ledger with no idea what to put in it. That is the correct
outcome: the mechanism is a public good, the knowledge is the business.

### The test

> Could a competent engineer, with this repository and no Stobox contact, run a compliant token sale?
> **Yes.**
>
> Could they produce an asset record an institutional allocator would rely on?
> **No — they would have to build the schema, recruit the attestors and earn the trust themselves.**

If the first answer is ever "no", the open-source claim is false. If the second is ever "yes", the
business has been given away. Both must hold on every release.

## Guardrails in the repository

These are enforced, not merely intended.

| Guardrail | Enforcement |
|---|---|
| No Stobox address in any contract | Test invariant scanning bytecode and source for known addresses |
| No STBU reference | Test invariant; `fee()` returns zero and `feeToken()` returns `address(0)` |
| No datapoint schema in the reference passport | Code review checklist; `bytes32 code` must remain opaque |
| The default identity adapter is the allowlist | Deployment default; StoboxDID is opt-in configuration |
| A fork deploys with no external dependency | CI job deploys the full stack to a fresh anvil chain and runs an end-to-end sale |

The last one is the important one. It runs on every commit, so the credibility test is not a promise —
it is a build step that fails.

## Naming and trademark

MIT grants rights to the code, not to the name. The repository name, the Stobox name and the Compass
name are trademarks and are not licensed by the code licence.

The claim a fork may make is **"passes the uRWA conformance suite"**. The claim it may not make is
"built by Stobox" or "Stobox-certified". This is normal open-source practice and needs stating once,
in `NOTICE`.

## Distinguishing a Stobox issuance from a fork

This matters most on the day something goes wrong with someone else's deployment.

| Signal | How to check |
|---|---|
| Issued by the Stobox factory | `factory.isFactoryIssued(token)` on the canonical factory address |
| Passport confirmed | `passport.isConfirmed(passportId, token)` — only the Stobox passport can confirm |
| Audited release | Deployment manifest matches a signed release tag |

All three are public reads. A misconfigured fork is verifiably distinguishable from a Stobox issuance
in seconds, without argument and without our cooperation.

## Related documents

- [11 — Asset Passport](11-passport.md)
- [17 — Security](17-security.md)
- [20 — Development plan](20-development-plan.md)
