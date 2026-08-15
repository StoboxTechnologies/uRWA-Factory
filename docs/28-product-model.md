# 28 — Product model

Who uses this, what they are trying to get done, what moves as a result, and where each job is
carried out. Every actor must have at least one job; every job must reach a surface. The verifier
checks both.

## Actors

| ID | Actor | Is | Holds | Trusts us for |
|---|---|---|---|---|
| P-01 | **Issuer** | The company tokenizing an asset | `ISSUER_ADMIN`, `UPGRADE_ADMIN` | That configured rules are actually enforced |
| P-02 | **Supply operator** | Treasury or finance function | `SUPPLY_OPERATOR` | That issuance cannot exceed the cap |
| P-03 | **Compliance officer** | Legal or compliance | `COMPLIANCE_OFFICER` | That freeze and seizure work, and are logged |
| P-04 | **Upgrade admin** | Board or technical trustee | `UPGRADE_ADMIN` | That upgrades cannot touch balances |
| P-05 | **Investor** | Holder or prospective holder | Tokens | That eligibility is knowable before buying |
| P-06 | **Integrator** | Exchange, custodian, lender | Nothing | One interface across every conformant token |
| P-07 | **Attestor** | Auditor, valuer, oracle | `ATTESTOR` | That their signature is theirs and revocable |
| P-08 | **Regulator** | Supervisory authority | Nothing | A reconstructible register and audit trail |
| P-09 | **Agent** | Automated operator | A bounded mandate | That it cannot exceed its mandate |
| P-10 | **Forker** | Anyone deploying their own instance | Their own everything | That nothing depends on Stobox |

## Jobs

Each job names its actor, the surface where it happens, the contract path it takes, and what
completion looks like.

### Issuance

| ID | Job | Actor | Surface | Path | Done when |
|---|---|---|---|---|---|
| J-01 | Deploy a compliant token | P-01 | Deploy console | `factory.createToken` | Token and treasury exist, roles granted, registered |
| J-02 | Choose a regulatory regime | P-01 | Deploy console | preset → `PolicySet` | Rules readable by anyone |
| J-03 | Choose an identity source | P-01 | Deploy console | `setIdentityRegistry` | Adapter installed, tier recorded |
| J-04 | Issue supply | P-02 | Token console | `issue` | Treasury holds it; `totalIssued` up |
| J-05 | Distribute to a holder | P-02 | Token console | `distributeFromTreasury` | Holder credited, lockup applied if set |
| J-06 | Redeem supply | P-02 | Token console | `redeem` | Supply down, `totalIssued` unchanged |

### Compliance

| ID | Job | Actor | Surface | Path | Done when |
|---|---|---|---|---|---|
| J-07 | Change the rule set without a migration | P-04 | Token console | `setPolicySet` | New rules live; no balance moved |
| J-08 | Trust a system address | P-01 | Token console | `trust` | Address listed with its reason |
| J-09 | Freeze part of a balance | P-03 | Compliance console | `setFrozenTokens` | `Frozen` emitted with composed total |
| J-10 | Apply a lockup | P-03 | Compliance console | `addLockup` | Visible in the holder's position with its date |
| J-11 | Halt all transfers | P-03 | Compliance console | `pause` | Every transfer reverts, trusted included |
| J-12 | Seize under legal compulsion | P-03 | Compliance console | `forcedTransfer` | Moved, reason on chain, `canReceive` enforced |
| J-13 | See why a transfer was refused | P-01, P-03 | Any surface | `whyBlocked` | Stage, rule and reason returned |

### Investment

| ID | Job | Actor | Surface | Path | Done when |
|---|---|---|---|---|---|
| J-14 | Find out if I may hold this | P-05 | Investor page, verifier | `canReceive`, claims | Answered before any signature |
| J-15 | Buy in an offering | P-05 | Investor page | `purchase` | Tokens received, payment locked to soft cap |
| J-16 | See what I can actually move | P-05 | Investor page | `unfrozenBalanceOf`, `lockupsOf` | Split shown with unlock dates |
| J-17 | Transfer to someone | P-05 | Investor page | `canTransfer` → `transfer` | Checked free first; no signature if it would fail |
| J-18 | Get my money back | P-05 | Investor page | `claimRefund` | Refunded without anyone's approval |

### Verification

| ID | Job | Actor | Surface | Path | Done when |
|---|---|---|---|---|---|
| J-19 | Confirm a token is what it claims | P-06, P-08 | Public verifier | `supportsInterface`, `isFactoryIssued` | Answered with no account |
| J-20 | Predict a transfer's outcome | P-06, P-09 | Public verifier, SDK | `canTransfer`, `whyBlocked` | Free, deterministic, never reverts |
| J-21 | Read the live rule set | P-06, P-05 | Public verifier | `groups`, `rulesOf` | Plain-language list |
| J-22 | Verify an asset claim | P-06, P-08 | Passport surface | `verify`, `verifyAbsence` | Proven against the anchored root |
| J-23 | Reconstruct the register | P-08 | Logs | Events only | No indexer, no API, no cooperation needed |

### Attestation and automation

| ID | Job | Actor | Surface | Path | Done when |
|---|---|---|---|---|---|
| J-24 | Sign a fact about an asset | P-07 | Compass | `recordAttestation` | Metadata public, value not |
| J-25 | Revoke an attestation | P-07 | Compass | revocation tree | No longer provable |
| J-26 | Automate operations within limits | P-09 | SDK | `AgentAuthority.check` | Action inside mandate or reverts |
| J-27 | Settle a trade atomically | P-09, P-06 | SDK | `AtomicDvP.settle` | Both legs or neither |
| J-28 | Kill an agent immediately | P-01 | Token console | `revoke` | Next action reverts, no timelock |

### Forking

| ID | Job | Actor | Surface | Path | Done when |
|---|---|---|---|---|---|
| J-29 | Run the whole stack independently | P-10 | Repository | Allowlist adapter, zero fee | Clean-chain CI job passes |

**29 jobs across 10 actors.** Every actor appears in at least one job. Every job names a surface and
a contract path.

## Value flows

What actually moves, and where it rests.

```
  Investor ──payment──▶ Treasury ──held until soft cap──▶ Issuer
                           │                                 ▲
                           │ security tokens                 │ settle
                           ▼                                 │
                       Investor ◀───────── refund ───────────┘
                                          (soft cap missed)

  Issuer ──issue──▶ Treasury ──distribute──▶ Investor ──transfer──▶ Investor
                                                  │
                                                  └──atomic DvP──▶ Counterparty
                                                     both legs or neither
```

| Flow | Moves | Guard |
|---|---|---|
| Issuance | Nothing external | Cap, `totalIssued` monotonic |
| Distribution | Security token | Full compliance pipeline |
| Primary purchase | Payment in, token out | Offering rules, then token pipeline |
| Refund | Payment back, token back | Idempotent; both paths |
| Secondary transfer | Security token | Full pipeline |
| Atomic settlement | Both legs, one transaction | Pipeline inside the settlement |
| Seizure | Security token | Reason mandatory, `canReceive` enforced |

**No value flow bypasses the compliance pipeline except the two forced operations**, which are
separately access-controlled and separately evented.

## Surfaces

| Surface | Actors | Auth | Public | Jobs |
|---|---|---|---|---|
| Public verifier | P-05, P-06, P-08 | None | ✅ | J-19…J-23 |
| Investor page | P-05 | Wallet | ✅ per token | J-14…J-18 |
| Deploy console | P-01 | Wallet + role | ❌ | J-01…J-03 |
| Token console | P-01, P-02, P-04 | Wallet + role | ❌ | J-04…J-08, J-28 |
| Compliance console | P-03 | Wallet + role | ❌ | J-09…J-13 |
| SDK | P-06, P-09 | None to read | ✅ | J-20, J-26, J-27 |
| Repository | P-10 | None | ✅ | J-29 |

## What the product is not

Stated because a product model that only lists capabilities implies the rest.

- Not a custodian. Contracts move tokens; the underlying asset sits where its legal structure puts it.
- Not a market. Compliant transferability is a precondition for one, not one.
- Not a determination that any asset is or is not a security.
- Not a guarantee of compliance. It enforces the rules it was configured with.
- Not a KYC provider. It reads claims; someone else issues them.

## Related

- [21 — Interface specification](21-interface-specification.md) — the surfaces in detail
- [29 — Data model](29-data-model.md) — what the jobs read and write
- [30 — Interaction model](30-interaction-model.md) — the call paths named above
