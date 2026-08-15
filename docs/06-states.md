# 06 — States

Every state machine in the system, with transitions and who may trigger them.

## 1. Token state

| State | Transfers | Issue / redeem | Entered by | Left by |
|---|:-:|:-:|---|---|
| **Active** | ✅ subject to rules | ✅ | Deployment | `pause` |
| **Paused** | ❌ all blocked | ❌ | `pause` | `unpause` |

Pause overrides everything, including the trusted-address bypass. There is one pause flag; both the
compliance officer and — where installed — the emergency facet reach the same flag, so there is no
possibility of two pause states disagreeing.

```
  Active ──pause()──▶ Paused ──unpause()──▶ Active
    ▲                                          │
    └──────────────────────────────────────────┘
```

## 2. Transfer outcome state

A transfer occupies exactly one of these terminal states. The stage index is returned by `whyBlocked`.

| Stage | Check | Failure error |
|:-:|---|---|
| 0 | Entered pipeline | — |
| 1 | Protocol paused? | `ProtocolPaused` |
| 2 | Both parties trusted? | *bypass to stage 6* |
| 3 | `canSend(from)` | `ERC7943CannotSend` |
| 4 | `canReceive(to)` | `ERC7943CannotReceive` |
| 5 | Unfrozen balance sufficient? | `ERC7943InsufficientUnfrozenBalance` |
| 6 | Policy set evaluates | `ERC7943CannotTransfer` |
| 7 | Executed | — |

## 3. Balance state

A holder's balance is partitioned at all times. The partition is computed, never stored as a total.

| Partition | Source | Expires |
|---|---|---|
| **Admin-frozen** | `setFrozenTokens` | Never — released only by another call |
| **Lockup-frozen** | `addLockup` | Automatically, by timestamp |
| **Transferable** | remainder | — |

```
balanceOf(a)          = 1000
adminFrozen[a]        =  200   ← indefinite
lockups: 300 → Jun            ← expires by itself
         200 → Dec
getFrozenTokens(a)    =  700
unfrozenBalanceOf(a)  =  300

after June, with no transaction:
getFrozenTokens(a)    =  400
unfrozenBalanceOf(a)  =  600
```

`getFrozenTokens` may exceed `balanceOf` — permitted by ERC-7943 — and must never revert.

## 4. Lockup state

| State | Meaning | Counted in frozen total |
|---|---|:-:|
| **Active** | `unlockAt > block.timestamp` | ✅ |
| **Expired** | `unlockAt <= block.timestamp` | ❌ |
| **Cleared** | Removed by the compliance officer | ❌ |

Expiry requires no transaction. `releaseExpired` only prunes the array to bound gas; it cannot change
the computed total.

## 5. Identity subject state

| State | `isActive` | Can send | Can receive | Cause |
|---|:-:|:-:|:-:|---|
| **None** | ❌ | ❌ | ❌ | No DID linked to this wallet |
| **Active** | ✅ | ✅ | ✅ | DID valid, unblocked, wallet linked and not deactivated |
| **Expired** | ❌ | ❌ | ❌ | `did.validTo <= now` |
| **Blocked** | ❌ | ❌ | ❌ | `did.blocked == true` |
| **Wallet deactivated** | ❌ | ❌ | ❌ | `linker.deactivated == true` — DID itself may still be active |

A subject may have several wallets in different states. Deactivating one wallet does not affect the
others or the subject's aggregate balance accounting.

## 6. Claim state

| State | `hasValidClaim` | Cause |
|---|:-:|---|
| **Absent** | ❌ | Key was never set for this subject |
| **Valid** | ✅ | Set, `expiresAt > now`, not revoked |
| **Expired** | ❌ | `expiresAt <= now` |
| **Revoked** | ❌ | Attribute deactivated, or attestation in the revocation tree |

Absence and expiry are different facts and must be distinguishable — a rule may treat "never
verified" differently from "verification lapsed".

## 7. Offering state

| State | Purchases | Payments | Entered by | Next |
|---|:-:|---|---|---|
| **Draft** | ❌ | — | `createOffering` | Active, Cancelled |
| **Active** | ✅ | locked in treasury | `activate` | Paused, Closed, Cancelled |
| **Paused** | ❌ | held | `pause` | Active, Cancelled |
| **Closed** | ❌ | held | `close`, or end date reached | Settled, Refunding |
| **Settled** | ❌ | released to issuer | soft cap met | Archived |
| **Refunding** | ❌ | returning to investors | soft cap missed | Archived |
| **Cancelled** | ❌ | returning to investors | `cancel` | Archived |
| **Archived** | ❌ | — | terminal | — |

```
  Draft ──▶ Active ⇄ Paused
              │  │
              │  └──▶ Cancelled ──▶ Archived
              ▼
           Closed ──soft cap met──▶ Settled ──▶ Archived
              └────soft cap missed──▶ Refunding ──▶ Archived
```

`Closed → Refunding` is reachable automatically from a missed soft cap, not only by operator action.
An absent operator cannot strand investor funds.

## 8. Purchase state

| State | Meaning |
|---|---|
| **Recorded** | Payment taken, tokens reserved or delivered |
| **Settled** | Offering settled; payment released to issuer |
| **Refunded** | Payment returned, tokens returned to treasury |
| **Refund pending** | Marked for refund, not yet executed |

Refunds are idempotent: a purchase already in `Refunded` cannot be refunded again by either the push
or the pull path. This is the invariant that makes dual-path refunds safe.

## 9. Passport state

| State | Meaning | Token link |
|---|---|---|
| **Draft** | Minted, no snapshot anchored | — |
| **Active** | At least one snapshot anchored | Optional |
| **Linked** | Handshake confirmed with at least one token | ✅ confirmed |
| **Stale** | Latest snapshot older than the freshness window | Unchanged |
| **Suspended** | Issuer suspended by the passport operator | Reads continue; no new snapshots |

Staleness is returned as a value from `snapshotOf`, never rendered only in a user interface. A machine
consumer cannot use a stale snapshot without explicitly ignoring a field.

## 10. Token link (handshake) state

| State | `passportOf(token)` | `tokensOf(passport)` | Meaning |
|---|:-:|:-:|---|
| **Unlinked** | 0 | — | No claim either way |
| **Declared** | set | not listed | Token claims a passport; unconfirmed and therefore not evidence |
| **Confirmed** | set | listed | Both sides agree — this is the only state that proves provenance |
| **Revoked** | set | removed | Passport withdrew confirmation |

Only the **Confirmed** state may be presented as provenance. A declared-but-unconfirmed link is
exactly what a forgery looks like, and integrators must treat it as such.

## 11. Attestation state

| State | Usable as evidence |
|---|:-:|
| **Valid** | ✅ `validUntil > now`, not in the revocation tree |
| **Expired** | ❌ |
| **Revoked** | ❌ present in `revocationRoot` |

An attestation signature is verified against the attestor key that was valid **at signing time**, so a
later key rotation does not invalidate history.

## 12. Access grant state

| State | Access |
|---|:-:|
| **Active** | ✅ `expiresAt > now`, not revoked |
| **Expired** | ❌ automatic |
| **Revoked** | ❌ by the passport owner |

Every grant expires. There is no permanent grant in the type — the field is not optional.

## 13. Rule state within a policy set

| State | Effect on evaluation |
|---|---|
| **Linked** | Evaluated normally |
| **Failing** | Reverted or exceeded its gas ceiling — counts as **reject**, emits `RuleFailed` |
| **Unlinked** | Not evaluated |

A failing third-party rule cannot brick the token, and cannot silently pass either.

## Related documents

- [08 — Compliance pipeline](08-compliance-pipeline.md)
- [11 — Asset Passport](11-passport.md)
- [12 — Offerings](12-offering.md)
