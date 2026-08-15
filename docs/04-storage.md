# 04 — Storage

## Discipline

Namespaced diamond storage, one struct per domain. **Append-only forever.** Never reorder a field,
never remove one, never change a type. A new field goes at the end, or into a `.v2` slot with its own
constant.

Diamonds fail in production for one reason above all others: facets sharing or reordering a storage
struct. This discipline is the whole defence.

```solidity
bytes32 constant CORE_SLOT       = keccak256("urwa.storage.core.v1");
bytes32 constant COMPLIANCE_SLOT = keccak256("urwa.storage.compliance.v1");
bytes32 constant FREEZE_SLOT     = keccak256("urwa.storage.freeze.v1");
bytes32 constant LOCKUP_SLOT     = keccak256("urwa.storage.lockup.v1");
bytes32 constant MONETARY_SLOT   = keccak256("urwa.storage.monetary.v1");
bytes32 constant ROLES_SLOT      = keccak256("urwa.storage.roles.v1");
```

## CoreStorage — ledger plane

Written only by the immutable ERC-20 core. No facet may write these fields.

```solidity
struct CoreStorage {
    mapping(address => uint256) balances;
    mapping(address => mapping(address => uint256)) allowances;
    mapping(address => uint256) nonces;      // ERC-2612
    uint256 totalSupply;
    uint256 maxSupply;                       // 0 = unlimited
    bool    capLocked;                       // set at deploy, irreversible
    string  name;
    string  symbol;
    uint8   decimals;
}
```

| Variable | Type | Set by | Mutable after deploy |
|---|---|---|---|
| `balances` | mapping | ledger core | Yes, by transfer only |
| `allowances` | mapping | ledger core | Yes |
| `nonces` | mapping | permit | Yes, monotonic |
| `totalSupply` | uint256 | issue / redeem | Yes |
| `maxSupply` | uint256 | deploy, `setMaxSupply` | Only if `capLocked == false` |
| `capLocked` | bool | deploy | **Never** |
| `name`, `symbol`, `decimals` | string, string, uint8 | deploy | **Never** |

## ComplianceStorage — policy plane

```solidity
struct ComplianceStorage {
    address policySet;
    address identityRegistry;
    mapping(address => bool)   trusted;
    mapping(address => string) trustReason;
    address[] trustList;
    bool    paused;
    uint256 holderCount;                          // addresses with balance > 0
    mapping(bytes32 => uint256) subjectBalance;   // subject => total across all wallets
    mapping(bytes32 => bool)    subjectIsHolder;
    uint256 subjectHolderCount;                   // the number caps must use
}
```

| Variable | Purpose | Updated on |
|---|---|---|
| `policySet` | Active rule engine | `setPolicySet` |
| `identityRegistry` | Active identity adapter | `setIdentityRegistry` |
| `trusted` | Rule bypass for system addresses | `trust` / `distrust` |
| `trustReason` | Mandatory justification per trusted address | `trust` |
| `trustList` | Enumerable trust list | `trust` / `distrust` |
| `paused` | Global halt | `pause` / `unpause` |
| `holderCount` | Address-level holder count | every balance change crossing zero |
| `subjectBalance` | Aggregate balance per identity subject | every transfer |
| `subjectIsHolder` | Whether a subject holds any balance | every transfer |
| `subjectHolderCount` | Subject-level holder count | when `subjectIsHolder` flips |

### Why subject-level accounting is mandatory

Holder caps must count **subjects**, not addresses. One investor with three wallets otherwise defeats
a Reg D 2000-holder limit while every dashboard reports green.

This cannot be retrofitted. Once balances exist you cannot determine retroactively which past
addresses shared an owner, so the counters would start from a wrong baseline permanently.

Addresses with no identity subject (`subjectOf` returns zero) are counted individually under a
synthetic subject derived from the address, so the count never under-reports.

## FreezeStorage

```solidity
struct FreezeStorage {
    mapping(address => uint256) adminFrozen;   // indefinite, set by compliance
}
```

`getFrozenTokens(a)` returns `adminFrozen[a] + Σ unexpired lockups`. `setFrozenTokens` writes only
`adminFrozen`. This keeps the ERC-7943 setter honest while supporting arbitrarily many schedules.

## LockupStorage

```solidity
struct Lockup {
    uint256 amount;
    uint64  unlockAt;      // unix seconds
    string  note;          // reason, for the audit trail
}

struct LockupStorage {
    mapping(address => Lockup[]) lockups;
}
```

Lockups expire by timestamp comparison. No keeper transaction is required and no state goes stale.
`releaseExpired` is a housekeeping call that prunes the array to bound gas; it never changes the
computed frozen total.

## MonetaryStorage

```solidity
struct MonetaryStorage {
    address treasury;
    address offeringRegistry;
    uint256 totalIssued;      // monotonic, never decreases
}
```

`totalIssued` is lifetime issuance and is independent of `totalSupply`, which falls on redemption.
Both are needed: supply for circulation, issued for reporting and cap enforcement across burn cycles.

## RolesStorage

```solidity
struct RolesStorage {
    mapping(bytes32 => mapping(address => bool)) roles;
    mapping(bytes32 => address[]) members;      // enumerable
}
```

## Passport storage

Held by `AssetPassport`, not by the token.

```solidity
struct Snapshot {
    bytes32 root;             // sparse Merkle root over all datapoint leaves
    bytes32 revocationRoot;   // revoked attestations
    uint32  version;
    uint64  takenAt;
    bytes32 schemaVersion;    // registry version the leaves conform to
}

struct Attestation {
    address attestor;
    bytes32 group;            // registry group code
    uint64  issuedAt;
    uint64  validUntil;
    bool    revoked;
}

struct AccessGrant {
    address   grantee;
    bytes32[] groups;         // group-level, not per datapoint
    uint64    expiresAt;      // grants always expire
    bytes32   termsHash;      // NDA or engagement letter
    bool      revoked;
}

struct TokenLink {
    address token;
    uint256 chainId;
    bool    confirmed;        // true only after the passport side confirms
}
```

## Storage invariants

Assert these in tests.

1. `totalSupply <= maxSupply` whenever `maxSupply != 0`.
2. `totalIssued` never decreases.
3. `capLocked` never transitions from `true` to `false`.
4. `Σ balances == totalSupply`.
5. `Σ subjectBalance == totalSupply`.
6. `subjectHolderCount <= holderCount`.
7. `getFrozenTokens(a)` may exceed `balanceOf(a)` — permitted by ERC-7943 and must not revert.
8. No facet writes outside its own slot.

## Related documents

- [03 — Contracts](03-contracts.md)
- [06 — States](06-states.md)
- [17 — Security](17-security.md)
