// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Every error the system raises
/// @notice Named and specific, because the error is the explanation a holder
///         gets. "Transfer failed" tells nobody what to do next.
interface IErrors {
    // ── ERC-20 ──────────────────────────────────────────────────────────────

    error ERC20InsufficientBalance(address sender, uint256 balance, uint256 needed);
    error ERC20InsufficientAllowance(address spender, uint256 allowance, uint256 needed);
    error ERC20InvalidSender(address sender);
    error ERC20InvalidReceiver(address receiver);
    error ERC20InvalidApprover(address approver);
    error ERC20InvalidSpender(address spender);

    // ── ERC-7943 ────────────────────────────────────────────────────────────

    error ERC7943CannotSend(address account);
    error ERC7943CannotReceive(address account);
    error ERC7943CannotTransfer(address from, address to, uint256 amount);
    error ERC7943InsufficientUnfrozenBalance(address account, uint256 amount, uint256 unfrozen);

    // ── pipeline ────────────────────────────────────────────────────────────

    error ProtocolPaused();
    error AddressIsPaused(address account);
    error RuleLimitExceeded(uint256 count, uint256 max);

    /// @dev Raised where a restriction is applied without a stated cause. An
    ///      unexplained restriction is indistinguishable from an attack on a
    ///      holder, so the reason is enforced rather than encouraged.
    error ReasonRequired();

    // ── supply ──────────────────────────────────────────────────────────────

    error MaxSupplyExceeded(uint256 requested, uint256 available);
    error CapIsLocked();
    error TreasuryNotSet();
    error InsufficientAvailable(uint256 requested, uint256 available);

    // ── upgrades ────────────────────────────────────────────────────────────

    /// @dev The mechanism behind the whole three-plane split. Raised by the
    ///      diamond when a cut tries to touch a selector registered against the
    ///      diamond itself.
    error CannotReplaceImmutableFunction(bytes4 selector);
    error FunctionNotFound(bytes4 selector);
    error UpgradeNotScheduled(bytes32 cutHash);
    error UpgradeNotReady(bytes32 cutHash, uint64 executableAt);

    // ── offerings ───────────────────────────────────────────────────────────

    error OfferingNotActive(uint256 id, uint8 status);
    error BelowMinimum(uint256 requested, uint256 minimum);
    error AboveMaximum(uint256 requested, uint256 maximum);
    error AllocationExceeded(uint256 requested, uint256 remaining);

    /// @dev A purchase over the remaining cap is refused whole. `remaining`
    ///      tells the caller exactly what would have been accepted.
    error HardCapExceeded(uint256 requested, uint256 remaining);
    error AlreadyRefunded(uint256 purchaseId);
    error PaymentsAreLocked(uint256 offeringId);
    /// @dev The two guard errors that keep the permissionless calls honest:
    ///      `beginRefunding` on a met soft cap, or `settle` on a missed one.
    error SoftCapMet();
    error SoftCapNotMet();
    error OnlyOfferingRegistry();

    // ── access ──────────────────────────────────────────────────────────────

    error NotAuthorized(address caller, bytes32 role);
    error ZeroAddress();

    // ── agents and settlement ───────────────────────────────────────────────

    error MandateExpired(bytes32 mandateId, uint64 expiredAt);
    error MandateIsRevoked(bytes32 mandateId);
    error EpochlessCap();
    error TokenNotInMandate(address token);
    error CounterpartyNotInMandate(address counterparty);
    error OutOfScope(bytes32 mandateId, bytes32 scope);
    error PerActionLimitExceeded(uint256 requested, uint256 limit);
    error PerEpochLimitExceeded(uint256 requested, uint256 remaining);
    error InstructionExpired(uint64 validUntil);
    error NonceAlreadySettled(bytes32 nonce);
    error BadSignature(address expected);

    // ── passport ────────────────────────────────────────────────────────────

    error PassportLocked();
    error NotConfirmedByPassport(bytes32 passportId, address token);
    error AlreadyLinked(bytes32 passportId, address token);
    error InvalidProof();
    error SnapshotStale(bytes32 passportId, uint64 takenAt);
    error GrantExpired(address grantee, uint64 expiredAt);
}
