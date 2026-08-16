# 14 — Events and errors

## Design rule

Events are the reporting layer. A complete cap table, transfer history and compliance audit trail must
be reconstructible **from logs alone**, with no indexer and no Stobox API. Every privileged action
carries a mandatory reason string and emits a distinct event.

---

## ERC-7943 canonical

Emitted exactly as the standard defines. Integrators decode these without token-specific knowledge.

```solidity
event ForcedTransfer(address indexed from, address indexed to, uint256 amount);
event Frozen(address indexed account, uint256 amount);
```

`Frozen` carries the **composed** total — admin freeze plus unexpired lockups — not just the admin
component, so an integrator reading it sees the same number `getFrozenTokens` returns.

## ERC-20 canonical

```solidity
event Transfer(address indexed from, address indexed to, uint256 value);
event Approval(address indexed owner, address indexed spender, uint256 value);
```

Forced transfers emit the ordinary `Transfer` **and** `ForcedTransfer`, in that order, as ERC-7943
requires. Where a forced transfer unfreezes first, `Frozen` precedes both.

---

## Compliance

```solidity
event Trusted(address indexed account, string reason);
event Distrusted(address indexed account, string reason);
event PolicySetChanged(address indexed previous, address indexed current);
event IdentityRegistryChanged(address indexed previous, address indexed current);
event RuleFailed(address indexed rule, address from, address to, string reason);
event Paused(address indexed by, string reason);
event Unpaused(address indexed by);
event AddressPaused(address indexed account, address indexed by, string reason);
event AddressUnpaused(address indexed account, address indexed by);
event SubjectHolderCountChanged(uint256 newCount);
```

`AddressPaused` halts one address in **both** directions and is distinct from `Frozen`, which
restricts sending only and takes an amount. The reason is mandatory on the same principle as the
trust list: an unexplained restriction is indistinguishable from an attack on a holder.

`Paused` carries a reason for the same reason. A global halt is the most disruptive action available
to a compliance officer, and a log entry that does not say why is of no use to the holder reading it.

`RuleFailed` is emitted when a rule reverts or exceeds its gas ceiling — even if the group ultimately
passes via another rule. It is the operational signal that a third-party rule is misbehaving.

Together with the refusal errors, `RuleFailed` gives **blocked compliance transfers per period** as a
countable log rather than a manually entered figure.

## Freeze and lockup

```solidity
event LockupAdded(address indexed account, uint256 amount, uint64 unlockAt, string note);
event LockupsCleared(address indexed account, string reason);
event ExpiredReleased(address indexed account, uint256 count);
```

Lockup expiry emits nothing — it happens by timestamp comparison with no transaction. Consumers
compute the current frozen total from `LockupAdded` events plus the current time, or simply call
`getFrozenTokens`.

## Monetary

```solidity
event Issued(address indexed to, uint256 amount, uint256 totalIssued);
event Redeemed(uint256 amount, uint256 totalIssued);
event MaxSupplyChanged(uint256 previous, uint256 current);
event CapLocked();
event TreasuryChanged(address indexed previous, address indexed current);
event OfferingRegistryChanged(address indexed previous, address indexed current);
```

## Roles

```solidity
event RoleGranted(bytes32 indexed role, address indexed account, address indexed by);
event RoleRevoked(bytes32 indexed role, address indexed account, address indexed by);
```

## Emergency

```solidity
event ForcedOperation(
    string  kind,        // "Transfer" | "Mint" | "Burn"
    address from,        // address(0) for mint
    address to,          // address(0) for burn
    uint256 amount,
    string  reason,      // mandatory audit trail
    address indexed by
);
```

Emitted in addition to the canonical ERC-7943 and ERC-20 events, never instead of them.

---

## Upgrades

```solidity
event UpgradeDelaySet(uint64 delay);
event UpgradeScheduled(bytes32 indexed cutHash, uint64 executableAt);
event UpgradeExecuted(bytes32 indexed cutHash);
event UpgradeCancelled(bytes32 indexed cutHash);
```

Where the issuer configured a delay, a cut is scheduled before it lands and the schedule is public.
That is the point of the delay: a holder who disagrees with a pending change has the window to act on
it. With `delay == 0` no scheduling event is emitted, because nothing was scheduled.

## Agents and settlement

```solidity
event MandateGranted(bytes32 indexed mandateId, address indexed principal, address indexed agent);
event MandateRevoked(bytes32 indexed mandateId);
event AgentActed(
    bytes32 indexed mandateId, address indexed agent, address indexed principal, bytes4 selector, uint256 amount
);
```

```solidity
event Settled(bytes32 indexed settlementId, address indexed seller, address indexed buyer, bytes32 tradeRef);
```

`AgentActed` names the **principal** as well as the agent, because the accountable party for an
automated action is the person who granted the mandate, not the software that executed it.

`Settled` carries `tradeRef` unchanged from the signed instruction. The contract never interprets it;
it exists so a trade on chain can be matched to the same trade in a reporting system that knows
nothing about blockchains.

## Factory

```solidity
event TokenCreated(
    address indexed token,
    address indexed treasury,
    address indexed issuer,
    bytes32 packageId,
    bytes32 preset
);
event PackageRegistered(bytes32 indexed id);
event PresetRegistered(bytes32 indexed id);
event FeeChanged(address token, uint256 amount);
```

## Passport

```solidity
event PassportMinted(bytes32 indexed passportId, address indexed issuer);
event SnapshotAnchored(bytes32 indexed passportId, bytes32 root, uint32 version, uint64 takenAt);
event TokenDeclared(address indexed token, bytes32 indexed passportId, uint256 chainId);
event TokenLinkConfirmed(bytes32 indexed passportId, address indexed token, uint256 chainId);
event TokenLinkRevoked(bytes32 indexed passportId, address indexed token);
event AccessGranted(bytes32 indexed passportId, address indexed grantee, uint64 expiresAt, bytes32 termsHash);
event AccessRevoked(bytes32 indexed passportId, address indexed grantee);
event AttestationRecorded(bytes32 indexed passportId, address indexed attestor, bytes32 group, uint64 validUntil);
event AttestationRevoked(bytes32 indexed passportId, address indexed attestor, bytes32 group);
```

## Offering

```solidity
event OfferingCreated(uint256 indexed id, address indexed token, bytes32 regime);
event OfferingStatusChanged(uint256 indexed id, uint8 previous, uint8 current);
event PurchaseRecorded(uint256 indexed id, uint256 indexed purchaseId, address indexed investor,
                       uint256 paid, uint256 tokens);
event PurchaseRefunded(uint256 indexed purchaseId, address indexed investor, uint256 amount);
event OfferingSettled(uint256 indexed id, uint256 raised);
event OfferingRefundingBegan(uint256 indexed id, uint256 raised, uint256 softCap);
```

## Treasury

```solidity
event Reserved(uint256 indexed offeringId, uint256 amount);
event Released(uint256 indexed offeringId, uint256 amount);
event PaymentsLocked(uint256 indexed offeringId);
event PaymentsUnlocked(uint256 indexed offeringId);
event Withdrawn(address indexed asset, address indexed to, uint256 amount);
```

---

## Errors

### ERC-7943 canonical

```solidity
error ERC7943CannotSend(address account);
error ERC7943CannotReceive(address account);
error ERC7943CannotTransfer(address from, address to, uint256 amount);
error ERC7943InsufficientUnfrozenBalance(address account, uint256 amount, uint256 unfrozen);
```

Using the canonical errors rather than custom ones is most of the practical interop value of ERC-7943:
an integrator decodes a failure without knowing anything about this particular token.

### ERC-20 canonical

```solidity
error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
error ERC20InvalidSender(address sender);
error ERC20InvalidReceiver(address receiver);
error ERC20InvalidApprover(address approver);
error ERC20InvalidSpender(address spender);
```

### uRWA

```solidity
error ProtocolPaused();
error RuleLimitExceeded(uint256 count, uint256 max);
error CapIsLocked();
error MaxSupplyExceeded(uint256 supplyAfterMint, uint256 maxSupply);
error ZeroAddress();
error CloneFailed();            // the treasury proxy could not be deployed
error NotAuthorized(address caller, bytes32 role);
error ReasonRequired();
error TreasuryNotSet();
```

### Passport

```solidity
error NotConfirmedByPassport(address token);
error AlreadyLinked(bytes32 passportId, address token);
error GrantExpired(address grantee);
error SnapshotStale(uint64 takenAt, uint64 maxAge);
error InvalidProof();
error PassportLocked();          // ERC-5192, transfer attempted
```

### Offering

```solidity
error OfferingNotActive(uint256 id, uint8 status);
error BelowMinimum(uint256 amount, uint256 minimum);
error AboveMaximum(uint256 amount, uint256 maximum);
error HardCapExceeded(uint256 raised, uint256 hardCap);
error AllocationExceeded(bytes32 subject, uint256 allocated, uint256 requested);
error AlreadyRefunded(uint256 purchaseId);
error PaymentTokenNotAccepted(address paymentToken); // purchase: paid in a currency the offering does not list
error AddressIsPaused(address account);

error CannotReplaceImmutableFunction(bytes4 selector);
error FunctionNotFound(bytes4 selector);
error UpgradeNotScheduled(bytes32 cutHash);
error UpgradeNotReady(bytes32 cutHash, uint64 executableAt);

error MandateExpired(bytes32 mandateId, uint64 expiredAt);
error MandateIsRevoked(bytes32 mandateId);   // named apart from the event, as CapIsLocked is
error EpochlessCap();                         // a per-epoch cap with a zero-length epoch never binds
error TokenNotInMandate(address token);       // consume: token outside the mandate's list
error CounterpartyNotInMandate(address counterparty); // consume: counterparty outside the list
error PresetLengthMismatch(uint256 rules, uint256 groups); // registerPreset: parallel arrays differ
error OutOfScope(bytes32 mandateId, bytes32 scope);
error PerActionLimitExceeded(uint256 requested, uint256 limit);
error PerEpochLimitExceeded(uint256 requested, uint256 remaining);
error InstructionExpired(uint64 validUntil);
error NonceAlreadySettled(bytes32 nonce);
error BadSignature(address expected);

error SoftCapMet();              // beginRefunding called when it should settle
error SoftCapNotMet();           // settle called when it should refund
```

### Treasury

```solidity
error InsufficientAvailable(uint256 available, uint256 requested);
error PaymentsAreLocked(uint256 offeringId);
error OnlyOfferingRegistry();
```

---

## Reconstruction guarantees

From logs alone, without any off-chain service, a consumer can rebuild:

| Artifact | From |
|---|---|
| Full cap table at any block | `Transfer` |
| Holder count over time | `Transfer` crossing zero balances |
| Subject-level holdings | `Transfer` + `SubjectHolderCountChanged` |
| Frozen balances | `Frozen` + `LockupAdded` + current time |
| Every compliance refusal | Revert errors + `RuleFailed` |
| Every privileged action with justification | `ForcedOperation`, `Trusted`, `Distrusted`, role events |
| Complete offering history | `OfferingCreated` → `OfferingStatusChanged` → `PurchaseRecorded` |
| Passport provenance chain | `SnapshotAnchored` + `TokenLinkConfirmed` |

## Related documents

- [07 — Function reference](07-functions.md)
- [08 — Compliance pipeline](08-compliance-pipeline.md)
