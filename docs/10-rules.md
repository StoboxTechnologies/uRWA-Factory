# 10 — Rules

## Composition

Rules are organised into groups. **Groups AND together; rules within a group OR.**

```
( HasValidIdentity )
AND ( EUProfessionalOnly OR USAccreditedOnly )
AND ( SanctionsScreen )
AND ( MaxHolders )
```

This covers every real jurisdictional case — "professional in the EU or accredited in the US" is the
canonical one — without a general boolean engine. A full expression engine with arbitrary nesting and
negation was considered and rejected: it is the easiest place in the system to misconfigure a live
compliance policy and the hardest thing to audit, and no real requirement has needed it.

## The rule contract

```solidity
struct Context {
    address token;
    bytes32 fromSubject;
    bytes32 toSubject;
    uint256 subjectHolderCount;
}

interface IRule {
    function check(address from, address to, uint256 amount, Context calldata ctx)
        external view returns (bool ok, string memory reason);
    function bounds(address account) external view returns (uint256 min, uint256 max);
    function ruleId() external view returns (bytes32);
}
```

Rules are **pure predicates**. They never write state. Where a rule appears to need state — a holder
cap — the token maintains the counter in its transfer accounting and the rule reads it through
`Context`. This keeps every rule replaceable without a data migration.

`bounds` lets a rule report a minimum and maximum investment for an account without mutating anything;
the offering registry applies it. This is how accreditation-linked minimums work.

## Rule library

Stateless, deployed once per chain, shared by every token.

### HasValidIdentity

| | |
|---|---|
| **Reads** | `urwa.identity.valid` |
| **Passes when** | Claim exists, unexpired, not revoked, and `isActive(wallet)` |
| **Reason on failure** | `"no valid identity"` |
| **Applied to** | Both parties |

The default token-level rule. Every preset includes it.

### JurisdictionAllow / JurisdictionDeny

| | |
|---|---|
| **Reads** | `urwa.jurisdiction.country` |
| **Config** | Set of hashed ISO 3166-1 alpha-2 codes |
| **Passes when** | Allow: country ∈ set. Deny: country ∉ set. |
| **Reason** | `"jurisdiction not permitted"` / `"jurisdiction excluded"` |

Countries are compared as hashes, so no plaintext country code appears in calldata.

### USAccreditedOnly

| | |
|---|---|
| **Reads** | `us.regd.accredited` |
| **Config** | Minimum investment amount |
| **Passes when** | Claim valid and unexpired |
| **`bounds`** | Returns the configured minimum |
| **Reason** | `"not an accredited investor"` |

### EUProfessionalOnly

| | |
|---|---|
| **Reads** | `eu.mifid2.professional` |
| **Passes when** | Claim valid and unexpired |
| **Reason** | `"not a professional client"` |

### EUQualifiedExemption

| | |
|---|---|
| **Reads** | `eu.prospectus.qualified` |
| **Passes when** | Claim valid, used for the prospectus-exemption route |
| **Reason** | `"not a qualified investor"` |

### MaxHolders

| | |
|---|---|
| **Reads** | `ctx.subjectHolderCount` |
| **Config** | Cap, e.g. 2000 for Reg D |
| **Passes when** | Recipient already holds, or `subjectHolderCount < cap` |
| **Reason** | `"holder limit reached"` |

**Counts subjects, not addresses.** An address-based cap is defeated by one investor using several
wallets.

### MaxBalancePerHolder

| | |
|---|---|
| **Reads** | `subjectBalanceOf(ctx.toSubject)`, `totalSupply` |
| **Config** | Absolute amount or basis points of supply |
| **Passes when** | Post-transfer subject balance ≤ cap |
| **Reason** | `"concentration limit exceeded"` |

### HoldPeriod

| | |
|---|---|
| **Reads** | Lockups on the sender |
| **Config** | Minimum holding duration |
| **Passes when** | The amount is outside any active lockup |
| **Reason** | `"hold period not elapsed"` |

Enforced through the frozen total rather than as a separate check, so it composes correctly with
admin freezes.

### TransferWindow

| | |
|---|---|
| **Reads** | `block.timestamp` |
| **Config** | Blackout intervals |
| **Passes when** | Now is outside every blackout |
| **Reason** | `"transfers closed during this window"` |

For record dates, distributions and corporate actions.

### SanctionsScreen

| | |
|---|---|
| **Reads** | `aml.sanctions.clear` |
| **Config** | Freshness window, e.g. 30 days |
| **Passes when** | Claim exists, is clear, and `issuedAt` is within the window |
| **Reason** | `"sanctions screening stale or failed"` |

Freshness is enforced by the rule, not the registry — so different tokens can demand different
cadences from the same claim.

### TravelRuleThreshold

| | |
|---|---|
| **Reads** | Amount, counterparty claim presence |
| **Config** | Threshold amount |
| **Passes when** | Below threshold, or counterparty data present |
| **Reason** | `"counterparty data required above threshold"` |

## Presets

Named, audited compositions selected at deployment and extendable afterwards. Configurability without
defaults is a trap: issuers misconfigure compliance and blame the tool.

| Preset | Composition |
|---|---|
| `RegD506c` | identity AND us.accredited AND sanctions AND MaxHolders(2000) AND HoldPeriod |
| `RegS` | identity AND JurisdictionDeny(US) AND sanctions AND HoldPeriod |
| `MiFID2-Professional` | identity AND eu.mifid2.professional AND sanctions |
| `MiFID2-Retail` | identity AND JurisdictionAllow(EEA) AND sanctions |
| `Dual-EU-US` | identity AND (eu.professional OR us.accredited) AND sanctions AND MaxHolders |
| `MiCA-ART` | identity AND sanctions AND reserve-attestation-fresh |
| `MiCA-EMT` | identity AND sanctions AND redemption-at-par-attested |
| `Open` | identity AND sanctions |

MiCA presets exist because commodity-backed tokens and stablecoins fall under MiCA rather than under
securities law. See [15 — Standards](15-standards.md#regulatory-regimes).

## Failure handling

Each rule runs inside `try/catch` under a gas ceiling.

| Condition | Result |
|---|---|
| Rule returns `ok = true` | Group satisfied |
| Rule returns `ok = false` | Try the next rule in the group |
| Rule reverts | Counts as **reject**; `RuleFailed` emitted |
| Rule exceeds the gas ceiling | Counts as **reject**; `RuleFailed` emitted |
| No rule in a group passes | Whole evaluation fails with that group's first reason |

`ruleCount` is hard-capped at `maxRules` so an admin cannot gas-grief the token into unusability. If
the entire policy set is broken, the compliance officer swaps it in one transaction — fail-closed
without a recovery path would itself be a bug.

## Writing a third-party rule

1. Implement `IRule`. Keep `check` pure and cheap — it runs on every transfer.
2. Read only from `IIdentityRegistry`, token view functions and `Context`.
3. Return a short, specific `reason`. It surfaces directly in `whyBlocked`.
4. Never revert for an ordinary "no" — return `(false, reason)`. Reverting works, but produces a worse
   diagnostic and consumes the gas ceiling.
5. Deploy once; the rule is stateless and shareable across tokens.

No permission from Stobox is required at any step. A new claim key and a new rule together add a new
jurisdiction to the system without touching any core contract.

## Related documents

- [08 — Compliance pipeline](08-compliance-pipeline.md)
- [09 — Identity and DID](09-identity-did.md)
- [12 — Offerings](12-offering.md)
