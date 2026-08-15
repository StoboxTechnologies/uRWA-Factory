# 30 — Interaction and API model

Who calls whom, in what order, what each side may read and write, and what happens when any step
fails. Every call named here exists in [07 — Function reference](07-functions.md); the verifier
checks that.

## Call graph

Arrows point from caller to callee. `→` is an external call, `⇢` is `delegatecall` within the diamond.

```
                                    ┌──────────────┐
   Issuer ──────────────────────────│  uRWAFactory │
                                    └───────┬──────┘
                        creates and wires   │
              ┌─────────────────────────────┼──────────────────┐
              ▼                             ▼                  ▼
        ┌──────────┐                 ┌────────────┐      ┌───────────┐
        │ Treasury │◀────────────────│  uRWAToken │      │ PolicySet │
        └────┬─────┘   custody       │  (diamond) │──────▶└─────┬─────┘
             │                       └──┬───┬──┬──┘  evaluate   │ check
             │                     ⇢    │   │  │                ▼
             │        ┌────────────────┘   │  └───────┐   ┌──────────┐
             │        ▼                    ▼          ▼   │   Rule   │ × 12
             │  ComplianceFacet    Freeze/Lockup   Monetary└────┬─────┘
             │        │                                          │ claims
             │        │ claims                                   │
             │        ▼                                          ▼
             │  ┌──────────────────┐                    ┌──────────────────┐
             │  │ IIdentityRegistry│◀───────────────────│ IIdentityRegistry│
             │  └────────┬─────────┘                    └──────────────────┘
             │           │ try/catch
             │     ┌─────┴─────┬──────────┐
             │     ▼           ▼          ▼
             │ Allowlist     EAS      StoboxDID
             │
             ▼
      ┌──────────────────┐        ┌──────────────┐        ┌───────────────┐
      │ OfferingRegistry │        │ AtomicDvP    │        │ AgentAuthority│
      └──────────────────┘        └──────┬───────┘        └───────┬───────┘
                                         │ canTransfer            │ check
                                         └────────────────────────┘
                                                    │
                                    ┌───────────────▼───────────────┐
                                    │  AssetPassport  (handshake)   │
                                    └───────────────────────────────┘
```

**Closure rule:** the token calls out to exactly three things — policy set, identity registry,
treasury. Nothing else. `AtomicDvP`, `AgentAuthority`, `OfferingRegistry` and `AssetPassport` are all
callers *into* the token, never dependencies of it. That is why the token functions with all four
absent.

## Read and write matrix

| Entity | Read by | Written by |
|---|---|---|
| Balance | anyone | ledger core only |
| Admin freeze | anyone | `COMPLIANCE_OFFICER` |
| Lockups | anyone | `COMPLIANCE_OFFICER`; expiry is time |
| Policy set pointer | anyone | `UPGRADE_ADMIN` |
| Identity registry pointer | anyone | `UPGRADE_ADMIN` |
| Trust list | anyone | `ISSUER_ADMIN` |
| Roles | anyone | role admin |
| Claims | token, rules, anyone | identity writer, externally |
| Treasury reservations | anyone | offering registry only |
| Offering state | anyone | operator, or anyone once terminal conditions hold |
| Passport snapshot root | anyone | `PASSPORT_ISSUER` |
| Datapoint values | grantee, off chain | issuer, off chain |
| Mandate | principal, agent, anyone | principal |

**Everything is publicly readable except datapoint values.** A compliance system nobody can inspect
is a compliance system nobody should trust.

## Sequences

### S-01 · Token deployment

```
Issuer → Factory.createToken(params)
           ├─▶ deploy diamond, cut facets from the package
           ├─▶ clone Treasury
           ├─▶ token.setTreasury, setOfferingRegistry
           ├─▶ token.setIdentityRegistry(adapter)
           ├─▶ deploy PolicySet from preset, token.setPolicySet
           ├─▶ token.trust(treasury, "treasury")
           ├─▶ grant 4 roles
           └─▶ register deployment, emit TokenCreated
        ◀── (token, treasury)
```

Factory retains **no control** over the token afterwards. This is the deliberate departure from
designs where the factory keeps admin rights.

### S-02 · Transfer — the central sequence

```
Holder → token.transfer(to, amount)
           │
           ⇢ ComplianceFacet.beforeUpdate(from, to, amount)
               1  paused?                        → revert ProtocolPaused
               2  both trusted?                  → skip to 7
               3  canSend(from)
                    → IIdentityRegistry.isActive(from)          try/catch
                    → claim(subject, urwa.identity.valid)       try/catch
                                                  → revert ERC7943CannotSend
               4  canReceive(to)                  → revert ERC7943CannotReceive
               5  amount ≤ balance − getFrozenTokens(from)
                                                  → revert ERC7943InsufficientUnfrozenBalance
               6  PolicySet.evaluate(from, to, amount)
                    for each group: for each rule:
                      try Rule.check{gas: CEILING}(…)
                      catch → emit RuleFailed, count as reject
                                                  → revert ERC7943CannotTransfer
               7  execute
                    ├─ update balances
                    ├─ update holderCount, subjectBalance, subjectHolderCount
                    └─ emit Transfer
```

**Order is a cost decision.** Cheap storage reads first, the one unbounded external call last. A
paused token or an unverified wallet costs almost nothing to reject.

### S-03 · Pre-flight — why agents and interfaces work

```
Anyone → token.canTransfer(from, to, amount)      view, free, never reverts
       ◀── bool

Anyone → token.whyBlocked(from, to, amount)       view, free, never reverts
       ◀── (stage, rule, reason)
```

Same code path as S-02, in view mode. Enforcement and explanation cannot drift because there is one
implementation.

### S-04 · Primary purchase

```
Investor → OfferingRegistry.purchase(offeringId, amount)
             ├─▶ status == Active, window open
             ├─▶ IIdentityRegistry.claim(subject, key) per offering rule
             ├─▶ offering rules evaluate
             ├─▶ min/max/allocation/hardCap
             ├─▶ paymentToken.transferFrom(investor → treasury)
             ├─▶ Treasury.lockPayments(offeringId)
             ├─▶ token.distributeFromTreasury(investor, tokens, unlockAt)
             │      └─▶ full S-02 pipeline on this leg
             └─▶ emit PurchaseRecorded
```

Offering rules and token rules are **independent**. Passing the offering never implies the right to
hold.

### S-05 · Atomic delivery versus payment

```
A, B → sign Instruction off chain (EIP-712)
Either party or their agent → AtomicDvP.settle(i, sigA, sigB)
             ├─▶ not expired, nonce unused
             ├─▶ both signatures valid
             ├─▶ token.canTransfer(seller, buyer, amount)   → revert with the rule's reason
             ├─▶ paymentToken: buyer → seller
             ├─▶ securityToken: seller → buyer             → full S-02 pipeline
             └─▶ mark nonce settled, emit Settled
```

Any failure reverts the whole transaction. **There is no interval in which one leg has moved and the
other has not** — which is why settlement risk cannot occur rather than being managed.

### S-06 · Agent action

```
Agent → AgentAuthority.check(mandate, scope, token, counterparty, amount)   view, free
      ◀── (bool, reason)
Agent → token.<scoped function>(…)
             └─▶ AgentAuthority.consume(mandate, amount)  → revert if over limit
             └─▶ emit AgentActed(mandate, agent, principal, selector, token, amount)
```

The agent is not trusted to respect its mandate. It is **unable to exceed it**.

### S-07 · Passport handshake

```
Issuer → token.declareToken(passportId, chainId)      anyone may declare
Operator → passport.confirmToken(passportId, token, chainId)   only the passport confirms
Anyone → passport.isConfirmed(passportId, token)      → bool
```

Declared-but-unconfirmed is exactly what a forgery looks like. Only **Confirmed** is provenance.

### S-08 · Proof of a disclosed datapoint

```
Grantee ← issuer, off chain: (value, salt, merkle path)
Grantee → passport.verify(passportId, code, value, salt, proof)   → bool
Grantee → passport.verifyAbsence(passportId, code, proof)         → bool
```

Verification needs no permission and no cooperation from us. A proof only we could verify would be
worth nothing.

## Failure propagation

| Where it fails | Propagates as | Recovery |
|---|---|---|
| Identity registry reverts | Caught by `try/catch`, treated as no claim | Swap the adapter |
| Identity registry unavailable | Claims absent → transfer blocked | Swap the adapter |
| One rule reverts or exceeds gas | Counts as reject, `RuleFailed` emitted | Remove or replace that rule |
| Policy set entirely broken | All transfers blocked | `setPolicySet` — one transaction |
| Compliance facet missing | `FunctionNotFound` on every transfer | Reinstall the facet |
| Treasury payment leg fails | Whole purchase reverts | Retry |
| Security leg fails after payment in DvP | **Whole transaction reverts** | Nothing moved |
| Passport unavailable | Token unaffected | Passport is descriptive, never dispositive |
| Agent exceeds mandate | Reverts before any state change | Adjust or revoke the mandate |

**Every ambiguous failure resolves toward stopping.** For a regulated instrument, blocking a legal
transfer is recoverable; permitting an illegal one may not be.

## API surface by consumer

| Consumer | Reads | Writes | Needs |
|---|---|---|---|
| Wallet | ERC-20 metadata, balance | `transfer`, `approve` | Nothing |
| Exchange or custodian | `canTransfer`, `whyBlocked`, `getFrozenTokens`, rules | — | Nothing |
| Agent | Everything above, plus `check`, `previewSettle` | Scoped actions, `settle` | A mandate |
| Investor interface | Balance split, claims, offering terms | `purchase`, `transfer`, `claimRefund` | A wallet |
| Issuer console | All token state | Roles, trust, supply, config | A role |
| Regulator | Events, register, rules, provenance | — | Nothing |
| Indexer | Events | — | Nothing |

**Nothing in the read column requires an account, a key or our cooperation.** That property is what
makes the system usable by parties who do not trust us, which is the whole point.

## Related

- [07 — Function reference](07-functions.md) — every signature named here
- [08 — Compliance pipeline](08-compliance-pipeline.md) — S-02 in detail
- [29 — Data model](29-data-model.md) — the entities being read and written
- [22 — Agents and settlement](22-agents-and-settlement.md) — S-05 and S-06 in detail
