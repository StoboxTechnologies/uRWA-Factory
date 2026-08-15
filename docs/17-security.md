# 17 — Security

## Threat model

| Adversary | Capability | Worst outcome | Bounded by |
|---|---|---|---|
| **External attacker** | Send transactions, deploy contracts | None beyond ordinary ERC-20 exposure | No privileged path is publicly reachable |
| **Malicious rule author** | Deploy a rule an issuer installs | Transfers blocked for that token | `try/catch`, gas ceiling, rule cap |
| **Compromised `UPGRADE_ADMIN`** | Swap facets, policy set, identity registry | **Transfers stop** | Ledger selectors are immutable — cannot touch balances or supply |
| **Compromised `COMPLIANCE_OFFICER`** | Freeze, pause, seize where installed | Assets frozen or moved with a logged reason | Cannot mint; every action evented |
| **Compromised `SUPPLY_OPERATOR`** | Mint to cap, drain treasury payments | Supply inflated to `maxSupply` | `capLocked` bounds it absolutely |
| **Malicious issuer** | Configure permissive rules | Their own token is non-compliant | Configuration is public and readable |
| **Compromised identity writer** | Grant false claims | Ineligible holders admitted | Claims carry issuer; revocation is immediate |
| **Passport operator** | Refuse or revoke confirmation | Token loses provenance, keeps functioning | Passport is descriptive, never dispositive |

## The core guarantee

**No key in the system can change a balance or the total supply outside the normal issue/redeem path.**

ERC-20 core selectors are registered against the diamond itself, and `LibDiamond` reverts
`CannotReplaceImmutableFunction` / `CannotRemoveImmutableFunction` for any such selector. This is
enforced by code, not by governance policy.

The consequence is that the blast radius of every compliance failure — bug, exploit, bad upgrade,
stolen key — is **"transfers stop"**, never **"supply is wrong"**.

## Failure direction

Every ambiguous failure resolves toward stopping.

| Failure | Result | Recovery |
|---|---|---|
| Policy set reverts | Transfers blocked | `COMPLIANCE_OFFICER` swaps the policy set |
| Identity registry unavailable | Transfers blocked | Swap the adapter |
| Compliance facet removed | `FunctionNotFound` on every transfer | Reinstall the facet |
| Single rule reverts or runs long | Counts as reject; `RuleFailed` emitted | Remove or replace that rule |
| Rule count grows unbounded | Prevented — hard cap | — |
| Snapshot never anchored | Passport shows stale; token unaffected | Anchor |

Fail-closed without a recovery path is itself a bug, so every blocked state has a one-transaction exit
that requires no migration.

## Designed-out failure modes

### Compliance

| Failure | Response |
|---|---|
| Address-based holder caps evaded by splitting across wallets | Caps count **subjects**; `subjectBalance` and `subjectHolderCount` exist from the first commit |
| Identity adapter reverts on unknown wallets, breaking ERC-7943 | Every external call in the adapter wrapped in `try/catch`; absence returned, never bubbled |
| Trusted address drains locked supply | Trust bypasses **rules only** — never the pause or frozen-balance checks |
| Revoked claim honoured until re-onboarding | No cache; revocation takes effect on the next transfer |
| Rule gas griefing | Per-rule gas ceiling plus a hard cap on rule count |

### Passport and disclosure

| Failure | Response |
|---|---|
| Low-entropy commitments brute-forced | 32 random bytes of salt per datapoint per version |
| Absence unprovable, so inconvenient facts are simply omitted | Sparse Merkle tree; non-membership is provable |
| Stale data read as current | `validUntil` per leaf, `snapshotAt` on the root; staleness returned as a value |
| Revoked attestation still verifies | Separate `revocationRoot`, updated every snapshot |
| Attestor key compromise invalidates history | Key registry with validity windows; signature checked against the key valid at signing time |
| Personal data anchored, erasure impossible | **No personal data in the passport tree, hashed or otherwise** |
| Forged passport link | Bidirectional handshake; only the passport confirms |
| Nobody verifies proofs | Small dependency-free verifier library shipped with the conformance kit |
| Grant sprawl | Every grant expires; the field is not optional |

### Offering

| Failure | Response |
|---|---|
| Absent operator strands investor funds | `settle` and `beginRefunding` are permissionless once conditions are met; investor-pull refunds always available |
| Double refund via both paths | Purchase state is checked and idempotent — assert in tests |
| Issuer withdraws payments before soft cap | Treasury enforces the lock, not operator discipline |
| Refund blocked because the investor became ineligible | Token return leg runs through the trusted path as a system operation |

## Known accepted risks

Stated rather than hidden.

| Risk | Why accepted |
|---|---|
| **Cross-snapshot correlation.** Unchanged leaves keep the same commitment, revealing which fields changed and when. | Change cadence is itself useful signal. Where it must be hidden, re-salt the whole tree at that snapshot. |
| **Diamond complexity.** Diamonds are harder to audit and do not verify cleanly on explorers. | Inherited from the STV3 base; mitigated by verification tooling and a loupe report. |
| **Configurable roles.** The permissive setting becomes the default in practice. | Mitigated by shipping the separated configuration as the default and using it in every example. |
| **Attribute values are world-readable in StoboxDID.** `getAttribute` is ungated `view`. | Necessary — the pipeline must read from a `view` context. Mitigated by requiring hashed values, never plaintext. |
| **Issuer can configure permissive rules.** | The configuration is public and machine-readable, so a counterparty can see exactly what was configured. |

## Invariants — assert in tests

1. ERC-20 core selectors are registered against the diamond and cannot be replaced or removed.
2. `canSend`, `canReceive`, `canTransfer`, `whyBlocked` never revert and never write — including for
   unknown, zero and contract addresses.
3. Removing the compliance facet halts transfers.
4. No path mints or moves value without passing the pipeline, except `forcedTransfer`,
   `forcedMint` and `forcedBurn`.
5. Holder caps count subjects, not addresses.
6. `totalIssued` is monotonic.
7. `totalSupply <= maxSupply` whenever `maxSupply != 0`.
8. `capLocked` never transitions from `true` to `false`.
9. `Σ balances == totalSupply` and `Σ subjectBalance == totalSupply`.
10. A compromised `UPGRADE_ADMIN` cannot change any balance or the supply.
11. Trust never bypasses the pause or frozen-balance checks.
12. A refunded purchase cannot be refunded again by either path.
13. `getFrozenTokens` may exceed balance and does not revert.
14. **The fee is zero in the default deployment, any non-zero fee is publicly readable before a
    transaction, and no STBU reference exists anywhere in the open-source code.**
15. No open-source contract references any Stobox address.

## Audit strategy

| Stage | Action |
|---|---|
| Publication | Code and testnet deployments public immediately for community review |
| Before mainnet issuance | Public audit contest against a frozen interface |
| Per release | Signed tag and published report, so "audited version" is checkable |
| Ongoing | Bug bounty; published incident-response runbook |

Mainnet issuance is gated on the audit clearing. Commercial pressure to open earlier will arrive; the
decision to gate is worth more written down now than argued later.

## Incident response

1. `COMPLIANCE_OFFICER` pauses the affected token — immediate, no timelock.
2. Publish the facts within an hour using a prepared statement template.
3. Determine whether the affected deployment is factory-issued, using `isFactoryIssued` and the
   passport handshake. **A fork misconfigured by a third party is verifiably distinguishable from a
   Stobox issuance**, and this must be demonstrable in seconds, not argued afterwards.
4. Swap the policy set or facet; unpause.
5. Post-mortem published with the release that fixes it.

## Related documents

- [02 — Architecture](02-architecture.md)
- [06 — States](06-states.md)
- [11 — Asset Passport](11-passport.md)
