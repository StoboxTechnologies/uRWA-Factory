# 09 — Identity and DID

## One interface, three adapters

The token depends on `IIdentityRegistry` as an interface. Any implementation works. This single
indirection is what lets Stobox ship StoboxDID as its own default while the same code, forked, runs
with no Stobox contract in the dependency graph.

```
   ComplianceFacet · PolicySet
              │
              ▼
      IIdentityRegistry
              │
    ┌─────────┼─────────┐
    ▼         ▼         ▼
 Allowlist   EAS    StoboxDID
  tier 0    tier 1   tier 2
```

| Tier | Adapter | Holds | Ships in |
|---|---|---|---|
| **0** | `AllowlistRegistry` | address → permitted | Open-source default; any fork |
| **1** | `EASAdapter` | Namespaced claims with issuer, expiry, revocation | Open source; Base-native |
| **2** | `StoboxDIDAdapter` | Claims + subject binding + jurisdiction rules linked on-chain | Open source; StoboxDID itself is Stobox-operated |

## Why extended, not a plain whitelist

A plain allowlist answers exactly one question — is this address permitted. It cannot supply
jurisdiction, accreditation, professional-client status or investor type. Those facts would remain
manually maintained forever, and the rules that depend on them could not exist.

The tier therefore determines how much of the compliance configuration can ever be machine-verified.
Tier 0 exists so a fork works at all, not because it is sufficient for a regulated issuance.

## The interface

```solidity
struct Claim {
    bytes32 valueHash;    // hashed value — no personal data on chain
    uint256 numeric;      // optional bound, for thresholds and tiers
    uint64  issuedAt;
    uint64  expiresAt;    // 0 = no expiry
    address issuer;       // attesting authority
    bool    revoked;
}

interface IIdentityRegistry {
    function subjectOf(address wallet) external view returns (bytes32 subject);
    function isActive(address wallet) external view returns (bool);
    function claim(bytes32 subject, bytes32 key) external view returns (Claim memory);
    function hasValidClaim(bytes32 subject, bytes32 key) external view returns (bool);
}
```

## Claim keys

Keys are `keccak256` of a dotted namespace. Stobox owns `urwa.*`. Anyone may define their own —
`ch.finma.qualified` needs no permission from Stobox and no core upgrade. **This is the extensibility
guarantee**, and it is why the schema is a key-value registry rather than a fixed struct.

| Key | Carries | Used by |
|---|---|---|
| `urwa.identity.valid` | Existence, expiry, block status | `canSend`, `canReceive` — the base gate |
| `urwa.jurisdiction.country` | Hashed ISO 3166-1 alpha-2 | `JurisdictionAllow` / `JurisdictionDeny` |
| `urwa.investor.type` | Retail, professional, institutional | Holder caps, reporting |
| `us.regd.accredited` | US accredited-investor status + expiry | `USAccreditedOnly` |
| `eu.mifid2.professional` | MiFID II professional client + expiry | `EUProfessionalOnly` |
| `eu.prospectus.qualified` | Qualified-investor status | `EUQualifiedExemption` |
| `aml.sanctions.clear` | Screening result + timestamp | `SanctionsScreen` |
| `iso17442.lei` | Hashed Legal Entity Identifier | Institutional reporting |

### EU and US eligibility are separate keys, deliberately

EU **professional client** and US **accredited investor** are different tests with different
thresholds. Collapsing them into one `accredited` boolean makes it impossible to run a Reg S tranche
and an EU tranche off one identity set. This is the schema decision that would be most expensive to
reverse.

## StoboxDID mapping — no fork required

StoboxDID already provides everything tier 2 requires.

| `IIdentityRegistry` | StoboxDID source |
|---|---|
| `subjectOf(wallet)` | `getLinker(wallet).uDID`, hashed to `bytes32` |
| `isActive(wallet)` | `!linker.deactivated` AND `!did.blocked` AND `did.validTo > now` |
| `claim(subject, key)` | `getAttribute(wallet, keyString)` → value, validTo, lastUpdatedBy |
| `hasValidClaim` | attribute exists AND `validTo > now` AND not deactivated |

Existing structures used:

```solidity
struct Attribute {
    bytes value; string valueType;
    uint256 createdAt; uint256 updatedAt; uint256 validTo;
    address lastUpdatedBy;
}

struct Linker {
    string UDID; uint256 joinDate; uint256 updateDate;
    bool deactivated; address[] linkedAddresses;
}
```

`Linker` gives wallet → subject, which is exactly the subject binding holder caps require.

## Blocking integration defect — must be handled in the adapter

`getUserDID` and `getAttribute` carry the `hasDID` modifier and **revert** when the wallet has no DID.

ERC-7943 requires that `canSend`, `canReceive` and `canTransfer` **never revert**. An unknown wallet —
the single most common case in any transfer to a new counterparty — would therefore break conformance.

**Every StoboxDID call in the adapter must be wrapped in `try/catch`**, returning "no claim" rather
than bubbling the revert:

```solidity
function isActive(address wallet) external view returns (bool) {
    try did.getLinker(wallet) returns (string memory u, uint256, uint256, bool deactivated) {
        if (deactivated) return false;
        try did.getUserDID(wallet) returns (string memory, uint256 validTo, uint256, bool blocked, address) {
            return !blocked && validTo > block.timestamp;
        } catch { return false; }
    } catch { return false; }
}
```

Check `getLinker` first — it reverts only on a missing linker — and treat any failure as absence.
This pattern applies to every read in the adapter without exception.

## Privacy check before launch

`getUserDID`, `getAttribute` and `getLinker` are `public view` with **no role gate**. Only the
event-emitting `readAttributeList`, `readLinkedAddresses` and `readFullDID` are gated by
`ATTRIBUTE_READER_ROLE`.

Attribute values are therefore world-readable on chain today. That is correct and necessary — the
compliance pipeline must read them from a `view` context — but it means **values must be hashes, never
plaintext**.

**Action:** confirm that no deployment stores plaintext country codes, names or document numbers in
`Attribute.value`, and make hashing the documented convention for every writer.

## Wallets and subjects

| Fact | Consequence |
|---|---|
| One subject may hold many wallets | Holder caps must count subjects |
| A wallet may be deactivated without blocking the subject | Other wallets of the same subject keep working |
| A wallet with no subject | Assigned a synthetic subject derived from the address, so counts never under-report |
| Maximum wallets per DID | Enforced by StoboxDID via `MAX_DID_LINKED_ADDRESSES` |

## Revocation

| Mechanism | Scope | Effect |
|---|---|---|
| `blockDID` | Whole subject | Every wallet fails `isActive` immediately |
| `deactivateDIDAttribute` | One claim | That claim fails `hasValidClaim`; others unaffected |
| `deactivateAddressOfDID` | One wallet | That wallet fails; subject and other wallets unaffected |
| Attribute `validTo` elapses | One claim | Automatic, no transaction |

Revocation takes effect on the **next transfer**, not on the next onboarding cycle. There is no cache.

## Related documents

- [10 — Rules](10-rules.md)
- [06 — States](06-states.md#5-identity-subject-state)
- [11 — Asset Passport](11-passport.md)
