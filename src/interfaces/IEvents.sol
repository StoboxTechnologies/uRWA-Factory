// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Every event the system emits
/// @notice Coverage is the requirement, not a nicety: the complete holder
///         register and compliance history must be reconstructible from logs
///         alone, with no indexer, no API and no cooperation from us.
/// @dev **Additive only.** Changing a signature breaks every consumer that
///      already indexed it, which is why `L3.5` and the release policy both
///      forbid it.
interface IEvents {
    // ── ledger ──────────────────────────────────────────────────────────────

    event Transfer(address indexed from, address indexed to, uint256 value);
    event Approval(address indexed owner, address indexed spender, uint256 value);

    // ── supply ──────────────────────────────────────────────────────────────

    event Issued(address indexed to, uint256 amount, uint256 totalIssued);
    event Redeemed(uint256 amount, uint256 totalIssued);
    event MaxSupplyChanged(uint256 previous, uint256 current);
    event CapLocked();

    // ── restrictions ────────────────────────────────────────────────────────

    /// @param amount The **composed** frozen total — admin freeze plus every
    ///        unexpired lockup — not the delta. An integrator reading one event
    ///        must not have to sum history to learn the current figure, and it
    ///        must match what `getFrozenTokens` returns.
    event Frozen(address indexed account, uint256 amount);
    event LockupAdded(address indexed account, uint256 amount, uint64 unlockAt, string note);
    event LockupsCleared(address indexed account, string reason);
    event ExpiredReleased(address indexed account, uint256 count);

    // ── pause ───────────────────────────────────────────────────────────────

    event Paused(address indexed by, string reason);
    event Unpaused(address indexed by);

    /// @notice One address halted in both directions
    event AddressPaused(address indexed account, address indexed by, string reason);
    event AddressUnpaused(address indexed account, address indexed by);

    // ── compliance configuration ────────────────────────────────────────────

    event Trusted(address indexed account, string reason);
    event Distrusted(address indexed account, string reason);
    event PolicySetChanged(address indexed previous, address indexed current);
    event IdentityRegistryChanged(address indexed previous, address indexed current);

    /// @notice A rule reverted or exceeded its gas ceiling
    /// @dev Emitted so the failure is visible; the transfer still stops.
    event RuleFailed(address indexed rule, address from, address to, string reason);

    event SubjectHolderCountChanged(uint256 newCount);

    // ── upgrades ────────────────────────────────────────────────────────────

    event UpgradeDelaySet(uint64 delay);

    /// @notice A cut is scheduled and now publicly inspectable before it lands
    event UpgradeScheduled(bytes32 indexed cutHash, uint64 executableAt);
    event UpgradeExecuted(bytes32 indexed cutHash);
    event UpgradeCancelled(bytes32 indexed cutHash);

    // ── roles ───────────────────────────────────────────────────────────────

    event RoleGranted(bytes32 indexed role, address indexed account, address indexed by);
    event RoleRevoked(bytes32 indexed role, address indexed account, address indexed by);

    // ── forced operations ───────────────────────────────────────────────────

    /// @dev Separate from `Transfer` on purpose: a seizure and a voluntary
    ///      transfer must never be indistinguishable in the log.
    event ForcedTransfer(address indexed from, address indexed to, uint256 amount);
    event ForcedOperation(string kind, address from, address to, uint256 amount, string reason, address indexed by);

    // ── treasury ────────────────────────────────────────────────────────────

    event Reserved(uint256 indexed offeringId, uint256 amount);
    event Released(uint256 indexed offeringId, uint256 amount);
    event PaymentsLocked(uint256 indexed offeringId);
    event PaymentsUnlocked(uint256 indexed offeringId);
    event Withdrawn(address indexed asset, address indexed to, uint256 amount);
    event TreasuryChanged(address indexed previous, address indexed current);
    event OfferingRegistryChanged(address indexed previous, address indexed current);

    // ── offerings ───────────────────────────────────────────────────────────

    event OfferingCreated(uint256 indexed id, address indexed token, bytes32 regime);
    event OfferingStatusChanged(uint256 indexed id, uint8 previous, uint8 current);
    event PurchaseRecorded(
        uint256 indexed id, uint256 indexed purchaseId, address indexed investor, uint256 paid, uint256 tokens
    );
    event PurchaseRefunded(uint256 indexed purchaseId, address indexed investor, uint256 amount);
    event OfferingSettled(uint256 indexed id, uint256 raised);
    event OfferingRefundingBegan(uint256 indexed id, uint256 raised, uint256 softCap);

    // ── factory ─────────────────────────────────────────────────────────────

    event TokenCreated(
        address indexed token, address indexed treasury, address indexed issuer, bytes32 packageId, bytes32 preset
    );
    event PackageRegistered(bytes32 indexed id);
    event PresetRegistered(bytes32 indexed id);
    event FeeChanged(address token, uint256 amount);

    // ── agents and settlement ───────────────────────────────────────────────

    event MandateGranted(bytes32 indexed mandateId, address indexed principal, address indexed agent);
    event MandateRevoked(bytes32 indexed mandateId);
    event AgentActed(
        bytes32 indexed mandateId, address indexed agent, address indexed principal, bytes4 selector, uint256 amount
    );
    event Settled(bytes32 indexed settlementId, address indexed seller, address indexed buyer, bytes32 tradeRef);

    // ── passport ────────────────────────────────────────────────────────────

    event PassportMinted(bytes32 indexed passportId, address indexed issuer);
    event SnapshotAnchored(bytes32 indexed passportId, bytes32 root, uint32 version, uint64 takenAt);
    event TokenDeclared(address indexed token, bytes32 indexed passportId, uint256 chainId);
    event TokenLinkConfirmed(bytes32 indexed passportId, address indexed token, uint256 chainId);
    event TokenLinkRevoked(bytes32 indexed passportId, address indexed token);
    event AttestationRecorded(bytes32 indexed passportId, address indexed attestor, bytes32 group, uint64 validUntil);
    event AttestationRevoked(bytes32 indexed passportId, address indexed attestor, bytes32 group);
    event AccessGranted(bytes32 indexed passportId, address indexed grantee, uint64 expiresAt, bytes32 termsHash);
    event AccessRevoked(bytes32 indexed passportId, address indexed grantee);
}
