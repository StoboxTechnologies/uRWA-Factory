# 07 — Function reference

Complete API. Every function, its signature, mutability and access control.

Access column: `any` = no restriction · role names as defined in [05 — Roles](05-roles.md).

---

## uRWAToken — ERC-20 core

Defined directly on the diamond. **Immutable** — these selectors cannot be replaced or removed,
enforced by `LibDiamond`.

| Signature | Mutability | Access |
|---|---|---|
| `name() → string` | view | any |
| `symbol() → string` | view | any |
| `decimals() → uint8` | view | any |
| `totalSupply() → uint256` | view | any |
| `balanceOf(address) → uint256` | view | any |
| `maxSupply() → uint256` | view | any |
| `allowance(address owner, address spender) → uint256` | view | any |
| `transfer(address to, uint256 value) → bool` | write | any |
| `approve(address spender, uint256 value) → bool` | write | any |
| `transferFrom(address from, address to, uint256 value) → bool` | write | any |
| `permit(address,address,uint256,uint256,uint8,bytes32,bytes32)` | write | any · ERC-2612 |
| `nonces(address) → uint256` | view | any |
| `DOMAIN_SEPARATOR() → bytes32` | view | any |
| `owner() → address` | view | any · ERC-173 |
| `deployer() → address` | view | any |

`transfer`, `transferFrom` and all mint/burn paths enter the compliance pipeline. `approve` does not —
compliance is enforced at movement, not at approval, per ERC-7943.

---

## ComplianceFacet

### ERC-7943 views

These **must not revert** and **must not write**. Enforced by test invariant.

| Signature | Mutability | Access |
|---|---|---|
| `canSend(address account) → bool` | view | any |
| `canReceive(address account) → bool` | view | any |
| `canTransfer(address from, address to, uint256 amount) → bool` | view | any |

- `canSend` — identity valid, unexpired, unblocked; account not globally frozen; token not paused.
  Trusted addresses return `true`. No amount logic.
- `canReceive` — the same test on the destination, plus receive-side restrictions such as a closed
  holder register.
- `canTransfer` — `canSend` and `canReceive`, plus unfrozen-balance sufficiency, plus the full policy
  set. Excludes plain balance and allowance checks, per the standard.

### Diagnostics

| Signature | Mutability | Access |
|---|---|---|
| `whyBlocked(address from, address to, uint256 amount) → (uint8 stage, address rule, string reason)` | view | any |
| `detectTransferRestriction(address,address,uint256) → uint8` | view | any · ERC-1404 |
| `messageForTransferRestriction(uint8) → string` | view | any · ERC-1404 |

`whyBlocked` runs the identical code path as enforcement, in view mode. Enforcement and explanation
cannot drift apart. `stage` values are listed in [06 — States](06-states.md#2-transfer-outcome-state).

### Configuration

| Signature | Mutability | Access |
|---|---|---|
| `policySet() → address` | view | any |
| `identityRegistry() → address` | view | any |
| `setPolicySet(address newPolicySet)` | write | UPGRADE_ADMIN |
| `setIdentityRegistry(address newRegistry)` | write | UPGRADE_ADMIN |

### Trust list

| Signature | Mutability | Access |
|---|---|---|
| `trust(address account, string reason)` | write | ISSUER_ADMIN |
| `distrust(address account, string reason)` | write | ISSUER_ADMIN |
| `isTrusted(address) → bool` | view | any |
| `trustList() → address[]` | view | any |
| `trustReasonOf(address) → string` | view | any |

Reason is mandatory. Trust bypasses **rules only** — never the pause check or the frozen-balance check.

### Pause

| Signature | Mutability | Access |
|---|---|---|
| `pause()` | write | COMPLIANCE_OFFICER |
| `unpause()` | write | COMPLIANCE_OFFICER |
| `paused() → bool` | view | any |

### Holder accounting

| Signature | Mutability | Access |
|---|---|---|
| `holderCount() → uint256` | view | any |
| `subjectHolderCount() → uint256` | view | any |
| `subjectBalanceOf(bytes32 subject) → uint256` | view | any |
| `subjectOf(address wallet) → bytes32` | view | any |

Holder caps use `subjectHolderCount`, never `holderCount`.

---

## FreezeFacet

| Signature | Mutability | Access |
|---|---|---|
| `getFrozenTokens(address account) → uint256` | view | any · ERC-7943 |
| `setFrozenTokens(address account, uint256 amount) → bool` | write | COMPLIANCE_OFFICER · ERC-7943 |
| `unfrozenBalanceOf(address account) → uint256` | view | any |
| `adminFrozenOf(address account) → uint256` | view | any |

`getFrozenTokens` = `adminFrozen` + Σ unexpired lockups. May exceed balance; never reverts.
`setFrozenTokens` writes only the admin component and emits `Frozen` with the composed total.

---

## LockupFacet

| Signature | Mutability | Access |
|---|---|---|
| `addLockup(address account, uint256 amount, uint64 unlockAt, string note)` | write | COMPLIANCE_OFFICER |
| `clearLockups(address account, string reason)` | write | COMPLIANCE_OFFICER |
| `releaseExpired(address account)` | write | any |
| `lockupsOf(address account) → Lockup[]` | view | any |
| `lockedAmountOf(address account) → uint256` | view | any |
| `lockupCount(address account) → uint256` | view | any |

`releaseExpired` is permissionless housekeeping — it prunes expired entries to bound gas and cannot
change the computed frozen total.

---

## MonetaryFacet

| Signature | Mutability | Access |
|---|---|---|
| `issue(address to, uint256 amount)` | write | SUPPLY_OPERATOR |
| `redeem(uint256 amount)` | write | SUPPLY_OPERATOR |
| `distributeFromTreasury(address to, uint256 amount, uint64 unlockAt)` | write | SUPPLY_OPERATOR |
| `totalIssued() → uint256` | view | any |
| `setMaxSupply(uint256 newMax)` | write | ISSUER_ADMIN |
| `capLocked() → bool` | view | any |
| `treasury() → address` | view | any |
| `setTreasury(address)` | write | ISSUER_ADMIN |
| `offeringRegistry() → address` | view | any |
| `setOfferingRegistry(address)` | write | ISSUER_ADMIN |

`issue` mints to the treasury by default; minting directly to a holder is the same function with a
non-treasury destination and is subject to the full pipeline. `setMaxSupply` reverts with `CapLocked`
when the cap was locked at deployment. `distributeFromTreasury` with `unlockAt = 0` applies no lockup.

---

## RolesFacet

| Signature | Mutability | Access |
|---|---|---|
| `grantRole(bytes32 role, address account)` | write | role admin |
| `revokeRole(bytes32 role, address account)` | write | role admin |
| `renounceRole(bytes32 role)` | write | self |
| `hasRole(bytes32 role, address account) → bool` | view | any |
| `getRoleMember(bytes32 role, uint256 index) → address` | view | any |
| `getRoleMemberCount(bytes32 role) → uint256` | view | any |
| `roleAdmin(bytes32 role) → bytes32` | view | any |

`UPGRADE_ADMIN` administers itself. `ISSUER_ADMIN` administers `SUPPLY_OPERATOR` and
`COMPLIANCE_OFFICER`.

---

## EmergencyFacet — opt-in, not installed by default

| Signature | Mutability | Access |
|---|---|---|
| `forcedTransfer(address from, address to, uint256 amount) → bool` | write | COMPLIANCE_OFFICER · ERC-7943 |
| `forcedTransfer(address from, address to, uint256 amount, string reason) → bool` | write | COMPLIANCE_OFFICER |
| `forcedMint(address to, uint256 amount, string reason)` | write | COMPLIANCE_OFFICER |
| `forcedBurn(address from, uint256 amount, string reason)` | write | COMPLIANCE_OFFICER |

`forcedTransfer` behaviour, in order:

1. If the amount exceeds the unfrozen balance, unfreeze what is required and emit `Frozen` with the
   new total — **before** the transfer event, as ERC-7943 requires.
2. Enforce `canReceive` on the destination. A seizure to an ineligible address is rejected.
3. Move the balance directly, bypassing the policy set.
4. Emit the canonical ERC-20 `Transfer`, then `ForcedTransfer`, then `ForcedOperation` with the reason.

---

## PurchaseFacet

| Signature | Mutability | Access |
|---|---|---|
| `purchase(uint256 offeringId, uint256 amount)` | write | any |
| `previewPurchase(uint256 offeringId, uint256 amount) → (uint256 cost, uint256 tokens, uint64 unlockAt)` | view | any |
| `refundPurchase(uint256 purchaseId)` | write | any (own purchase) |

---

## IPolicySet

| Signature | Mutability | Access |
|---|---|---|
| `evaluate(address from, address to, uint256 amount) → (bool ok, address failingRule, string reason)` | view | any |
| `addGroup(bytes32 group)` | write | UPGRADE_ADMIN |
| `removeGroup(bytes32 group)` | write | UPGRADE_ADMIN |
| `addRule(bytes32 group, address rule)` | write | UPGRADE_ADMIN |
| `removeRule(bytes32 group, address rule)` | write | UPGRADE_ADMIN |
| `groups() → bytes32[]` | view | any |
| `rulesOf(bytes32 group) → address[]` | view | any |
| `ruleCount() → uint256` | view | any |
| `maxRules() → uint256` | view | any |

Groups AND together; rules within a group OR. `ruleCount` is hard-capped at `maxRules` so an admin
cannot gas-grief the token into unusability.

---

## IRule

```solidity
struct Context {
    address token;
    bytes32 fromSubject;
    bytes32 toSubject;
    uint256 subjectHolderCount;
}
```

| Signature | Mutability | Access |
|---|---|---|
| `check(address from, address to, uint256 amount, Context ctx) → (bool ok, string reason)` | view | any |
| `bounds(address account) → (uint256 min, uint256 max)` | view | any |
| `ruleId() → bytes32` | view | any |

Rules are pure predicates. They never write state. Where a rule appears to need state — a holder cap —
the token maintains the counter and the rule reads it.

---

## IIdentityRegistry

```solidity
struct Claim {
    bytes32 valueHash;
    uint256 numeric;
    uint64  issuedAt;
    uint64  expiresAt;    // 0 = no expiry
    address issuer;
    bool    revoked;
}
```

| Signature | Mutability | Access |
|---|---|---|
| `subjectOf(address wallet) → bytes32` | view | any |
| `isActive(address wallet) → bool` | view | any |
| `claim(bytes32 subject, bytes32 key) → Claim` | view | any |
| `hasValidClaim(bytes32 subject, bytes32 key) → bool` | view | any |

**All four must return rather than revert for unknown wallets.** See
[09 — Identity](09-identity-did.md) for the `try/catch` requirement in the StoboxDID adapter.

---

## Treasury

| Signature | Mutability | Access |
|---|---|---|
| `token() → address` | view | any |
| `deposit(address asset, uint256 amount)` | write | any |
| `withdrawERC20(address asset, address to, uint256 amount)` | write | SUPPLY_OPERATOR |
| `reserve(uint256 amount, uint256 offeringId)` | write | offering registry |
| `release(uint256 amount, uint256 offeringId)` | write | offering registry |
| `lockPayments(uint256 offeringId)` | write | offering registry |
| `unlockPayments(uint256 offeringId)` | write | offering registry |
| `reservedOf(uint256 offeringId) → uint256` | view | any |
| `availableBalance() → uint256` | view | any |
| `paymentBalance(address asset) → uint256` | view | any |

`withdrawERC20` reverts while any offering holding that asset is in `Active` or `Closed` state with
its soft cap unmet.

---

## uRWAFactory

```solidity
struct TokenParams {
    string  name;
    string  symbol;
    uint8   decimals;
    uint256 maxSupply;
    bool    capLocked;
    address issuerAdmin;
    address upgradeAdmin;
    address identityRegistry;
    bytes32 preset;
    bytes32 packageId;
    bytes32 passportId;      // optional; zero is valid
}
```

| Signature | Mutability | Access |
|---|---|---|
| `createToken(TokenParams p) → (address token, address treasury)` | write | **any** |
| `createTokenWithOffering(TokenParams p, OfferingParams o) → (address,address,uint256)` | write | any |
| `registerPackage(bytes32 id, FacetCut[] cuts)` | write | FACTORY_ADMIN |
| `packages(bytes32 id) → FacetCut[]` | view | any |
| `registerPreset(bytes32 id, address[] rules, bytes32[] groups)` | write | FACTORY_ADMIN |
| `presets(bytes32 id) → (address[], bytes32[])` | view | any |
| `setFeeToken(address)` | write | FACTORY_ADMIN |
| `setFee(uint256)` | write | FACTORY_ADMIN |
| `feeToken() → address` | view | any |
| `fee() → uint256` | view | any |
| `deploymentsOf(address issuer) → address[]` | view | any |
| `allDeployments() → address[]` | view | any |
| `isFactoryIssued(address token) → bool` | view | any |

In the open distribution `fee()` returns zero and `feeToken()` returns the zero address. **No STBU
check exists anywhere in the open-source code** — this is a test invariant.

---

## AssetPassport

| Signature | Mutability | Access |
|---|---|---|
| `mint(bytes32 passportId, address issuer)` | write | PASSPORT_ISSUER |
| `anchorSnapshot(bytes32 passportId, Snapshot s)` | write | PASSPORT_ISSUER |
| `declareToken(address token, uint256 chainId)` | write | token's ISSUER_ADMIN |
| `confirmToken(bytes32 passportId, address token, uint256 chainId)` | write | PASSPORT_ISSUER |
| `revokeToken(bytes32 passportId, address token)` | write | PASSPORT_ISSUER |
| `grantAccess(bytes32 passportId, AccessGrant g)` | write | passport owner |
| `revokeAccess(bytes32 passportId, address grantee)` | write | passport owner |
| `recordAttestation(bytes32 passportId, Attestation a)` | write | ATTESTOR |
| `snapshotOf(bytes32 passportId) → (Snapshot, bool stale)` | view | any |
| `tokensOf(bytes32 passportId) → address[]` | view | any |
| `passportOf(address token) → bytes32` | view | any |
| `isConfirmed(bytes32 passportId, address token) → bool` | view | any |
| `attestationsOf(bytes32 passportId) → Attestation[]` | view | any |
| `publicLeaf(bytes32 passportId, bytes32 code) → bytes` | view | any |
| `verify(bytes32 passportId, bytes32 code, bytes value, bytes32 salt, bytes32[] proof) → bool` | view | any |
| `verifyAbsence(bytes32 passportId, bytes32 code, bytes32[] proof) → bool` | view | any |
| `accessOf(bytes32 passportId, address grantee) → AccessGrant` | view | any |

`snapshotOf` returns staleness as a value. `locked(uint256 tokenId) → bool` returns `true` always —
ERC-5192, the passport is non-transferable.

---

## AttestorRegistry

| Signature | Mutability | Access |
|---|---|---|
| `registerKey(address attestor, uint64 validFrom, uint64 validTo)` | write | PASSPORT_ADMIN |
| `revokeKey(address attestor)` | write | PASSPORT_ADMIN |
| `isValidAt(address attestor, uint64 timestamp) → bool` | view | any |
| `attestors() → address[]` | view | any |

Signature validity is checked against the key valid **at signing time**, so a rotation does not
invalidate historical attestations.

---

## OfferingRegistry

| Signature | Mutability | Access |
|---|---|---|
| `createOffering(OfferingParams p) → uint256 id` | write | OFFERING_OPERATOR |
| `activate(uint256 id)` | write | OFFERING_OPERATOR |
| `pause(uint256 id)` / `unpause(uint256 id)` | write | OFFERING_OPERATOR |
| `close(uint256 id)` | write | OFFERING_OPERATOR |
| `cancel(uint256 id, string reason)` | write | OFFERING_OPERATOR |
| `settle(uint256 id)` | write | any — permissionless once soft cap met |
| `beginRefunding(uint256 id)` | write | any — permissionless once soft cap missed and closed |
| `refundBatch(uint256 id, uint256 limit)` | write | OFFERING_OPERATOR |
| `claimRefund(uint256 purchaseId)` | write | purchaser |
| `addRule(uint256 id, address rule)` / `removeRule(uint256 id, address rule)` | write | OFFERING_OPERATOR |
| `offeringOf(uint256 id) → Offering` | view | any |
| `statusOf(uint256 id) → uint8` | view | any |
| `purchaseOf(uint256 purchaseId) → Purchase` | view | any |
| `purchasesOf(address investor) → uint256[]` | view | any |
| `raisedOf(uint256 id) → uint256` | view | any |
| `previewPurchase(uint256 id, uint256 amount) → (uint256 cost, uint256 tokens, uint64 unlockAt)` | view | any |

`settle` and `beginRefunding` are **permissionless** once their conditions are met. An inactive
operator cannot strand investor funds.

---

## Related documents

- [06 — States](06-states.md)
- [14 — Events and errors](14-events-errors.md)
- [16 — Deployment](16-deployment.md)
