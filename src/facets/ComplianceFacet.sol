// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "../interfaces/IErrors.sol";
import {IEvents} from "../interfaces/IEvents.sol";
import {IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IPolicySet} from "../interfaces/IPolicy.sol";
import {ClaimKeys, Roles} from "../interfaces/Roles.sol";
import {Restrictions} from "./RestrictionFacets.sol";
import {Layout} from "../storage/Layout.sol";

/// @title The part that decides whether value may move
/// @notice Seven gates in a fixed order, and the same code path answers
///         `canTransfer` and `whyBlocked`. Enforcement and explanation cannot
///         drift because there is one implementation of each question.
/// @dev **Order is a cost decision.** Cheap storage reads first, the one
///      unbounded external call last: refusing a paused token or an unverified
///      wallet costs almost nothing.
contract ComplianceFacet is IErrors {
    /// @dev Gate indices, returned by `whyBlocked`. Mirrors docs/06-states.md.
    uint8 internal constant GATE_PAUSED = 1;
    uint8 internal constant GATE_ADDRESS_PAUSED = 2;
    uint8 internal constant GATE_SEND = 3;
    uint8 internal constant GATE_RECEIVE = 4;
    uint8 internal constant GATE_UNFROZEN = 5;
    uint8 internal constant GATE_RULES = 6;
    uint8 internal constant GATE_OK = 0;

    /// @dev A rule may consume at most this much gas. A constant, identical for
    ///      every token: a configurable ceiling turns a working rule into a
    ///      silent refusal that reads as a compliance decision.
    uint256 internal constant RULE_GAS_CEILING = 100_000;

    // ── the pipeline ────────────────────────────────────────────────────────

    /// @notice Called by the ledger before every movement of value
    /// @dev Reverts with the specific reason. The token re-raises it unchanged,
    ///      so the holder learns which gate refused.
    function beforeUpdate(address from, address to, uint256 amount) external view {
        (uint8 stage,,) = _evaluate(from, to, amount);
        if (stage == GATE_OK) return;

        if (stage == GATE_PAUSED) revert ProtocolPaused();
        if (stage == GATE_ADDRESS_PAUSED) {
            revert AddressIsPaused(Layout.compliance().addressPaused[from] ? from : to);
        }
        if (stage == GATE_SEND) revert ERC7943CannotSend(from);
        if (stage == GATE_RECEIVE) revert ERC7943CannotReceive(to);
        if (stage == GATE_UNFROZEN) {
            revert ERC7943InsufficientUnfrozenBalance(from, amount, _unfrozen(from));
        }
        // The failing rule's address is not in the error: ERC-7943 fixes this
        // signature, and widening it would break every integrator decoding it.
        // `whyBlocked` returns the rule, which is what a diagnostic is for.
        revert ERC7943CannotTransfer(from, to, amount);
    }

    /// @notice Called by the ledger after balances have moved
    /// @dev Holder accounting lives here rather than in the ledger because it
    ///      needs the identity registry, and the ledger plane must not depend
    ///      on the claims plane. It runs after the fact, so it can never refuse
    ///      a transfer the pipeline already allowed.
    function afterUpdate(address from, address to, uint256 amount) external {
        // The ledger calls this on itself, so the only legitimate caller is the
        // diamond. Without the check, anyone could move the subject counters
        // that `MaxHolders` and `MaxBalancePerHolder` are decided on — no
        // balance would change, and every holder cap would be wrong.
        if (msg.sender != address(this)) revert NotAuthorized(msg.sender, bytes32(0));

        Layout.ComplianceStorage storage s = Layout.compliance();
        Layout.CoreStorage storage core = Layout.core();

        if (from != address(0)) {
            _decrease(s, from, core.balances[from], amount);
        }
        if (to != address(0)) {
            _increase(s, to, core.balances[to], amount);
        }
    }

    /// @dev `balanceAfter` is read after the move, so the address-level count
    ///      is derived from the balance rather than tracked separately — one
    ///      source of truth, no drift.
    function _increase(Layout.ComplianceStorage storage s, address who, uint256 balanceAfter, uint256 amount) private {
        if (balanceAfter == amount && amount > 0) s.holderCount += 1;

        bytes32 subject = _subjectOf(s.identityRegistry, who);
        uint256 before = s.subjectBalance[subject];
        s.subjectBalance[subject] = before + amount;

        if (before == 0 && amount > 0 && !s.subjectIsHolder[subject]) {
            s.subjectIsHolder[subject] = true;
            s.subjectHolderCount += 1;
            emit IEvents.SubjectHolderCountChanged(s.subjectHolderCount);
        }
    }

    function _decrease(Layout.ComplianceStorage storage s, address who, uint256 balanceAfter, uint256 amount) private {
        if (balanceAfter == 0 && amount > 0 && s.holderCount > 0) s.holderCount -= 1;

        bytes32 subject = _subjectOf(s.identityRegistry, who);
        uint256 remaining = s.subjectBalance[subject];
        remaining = remaining > amount ? remaining - amount : 0;
        s.subjectBalance[subject] = remaining;

        if (remaining == 0 && s.subjectIsHolder[subject]) {
            s.subjectIsHolder[subject] = false;
            if (s.subjectHolderCount > 0) s.subjectHolderCount -= 1;
            emit IEvents.SubjectHolderCountChanged(s.subjectHolderCount);
        }
    }

    /// @notice Which identity owns this wallet
    /// @dev A wallet the registry does not know gets a **synthetic** subject
    ///      derived from its address, so the count never under-reports. The
    ///      alternative — skipping unknown wallets — would let a cap be evaded
    ///      by holding through addresses the registry has not seen.
    function _subjectOf(address registry, address wallet) internal view returns (bytes32) {
        if (registry != address(0)) {
            try IIdentityRegistry(registry).subjectOf(wallet) returns (bytes32 subject) {
                if (subject != bytes32(0)) return subject;
            } catch {}
        }
        return keccak256(abi.encodePacked(wallet));
    }

    function subjectOf(address wallet) external view returns (bytes32) {
        return _subjectOf(Layout.compliance().identityRegistry, wallet);
    }

    /// @notice The one evaluation. Everything else is a view over it.
    /// @dev `view` and total: it answers for any input, including garbage, and
    ///      never reverts. That is what makes pre-flight possible.
    function _evaluate(address from, address to, uint256 amount)
        internal
        view
        returns (uint8 stage, address rule, string memory reason)
    {
        Layout.ComplianceStorage storage s = Layout.compliance();

        // 1 · global pause, which nothing escapes
        if (s.paused) return (GATE_PAUSED, address(0), "protocol paused");

        // 2 · either party halted individually, in both directions
        if (s.addressPaused[from]) return (GATE_ADDRESS_PAUSED, address(0), "sender is paused");
        if (s.addressPaused[to]) return (GATE_ADDRESS_PAUSED, address(0), "recipient is paused");

        // 3 · minting and burning are accounted elsewhere; the pipeline governs
        //     movement between holders
        // Trust exempts **that party**, not the pair. A trusted treasury must
        // be able to distribute to a verified investor without itself being in
        // the identity registry — which is the whole reason it is trusted.
        if (!s.trusted[from] && !_eligible(s.identityRegistry, from)) {
            return (GATE_SEND, address(0), "sender is not verified");
        }
        if (!s.trusted[to] && !_eligible(s.identityRegistry, to)) {
            return (GATE_RECEIVE, address(0), "recipient is not verified");
        }

        // Rules are skipped only when **both** sides are trusted: a rule about
        // holder counts or concentration is about the untrusted party, and
        // skipping it because their counterparty is a treasury would be wrong.
        bool bothTrusted = s.trusted[from] && s.trusted[to];

        // 5 · restrictions apply to trusted addresses too
        if (amount > _unfrozen(from)) {
            return (GATE_UNFROZEN, address(0), "amount exceeds unfrozen balance");
        }

        if (!bothTrusted && s.policySet != address(0)) {
            (bool ok, address failing, string memory why) = _rules(s.policySet, from, to, amount);
            if (!ok) return (GATE_RULES, failing, why);
        }

        return (GATE_OK, address(0), "");
    }

    /// @dev Every registry call is wrapped: the deployed StoboxDID reverts for
    ///      unknown wallets — the most common input — and a revert here would
    ///      break the standard's must-not-revert guarantee on the ordinary case.
    function _eligible(address registry, address wallet) internal view returns (bool) {
        if (registry == address(0)) return false;

        try IIdentityRegistry(registry).isActive(wallet) returns (bool active) {
            if (!active) return false;
        } catch {
            return false;
        }

        try IIdentityRegistry(registry).subjectOf(wallet) returns (bytes32 subject) {
            try IIdentityRegistry(registry).hasValidClaim(subject, ClaimKeys.IDENTITY_VALID) returns (bool ok) {
                return ok;
            } catch {
                return false;
            }
        } catch {
            return false;
        }
    }

    /// @dev A rule that reverts or exhausts its ceiling counts as a refusal. A
    ///      broken rule never opens the gate.
    function _rules(address policies, address from, address to, uint256 amount)
        internal
        view
        returns (bool ok, address failing, string memory reason)
    {
        try IPolicySet(policies).evaluate{gas: RULE_GAS_CEILING}(from, to, amount) returns (
            bool passed, address failingRule, string memory why
        ) {
            return (passed, failingRule, why);
        } catch {
            return (false, policies, "policy set failed to evaluate");
        }
    }

    function _unfrozen(address account) internal view returns (uint256) {
        uint256 balance = Layout.core().balances[account];
        uint256 frozen = _frozen(account);
        unchecked {
            return frozen >= balance ? 0 : balance - frozen;
        }
    }

    /// @dev Admin freeze plus every unexpired lockup. May exceed the balance,
    ///      which is legal and must not revert. Shared with the restriction
    ///      facets so the enforced number and the reported one are the same
    ///      code, not two implementations that agree today.
    function _frozen(address account) internal view returns (uint256) {
        return Restrictions.frozenOf(account);
    }

    // ── ERC-7943, and the diagnostic that shares its code path ──────────────

    function canSend(address account) external view returns (bool) {
        Layout.ComplianceStorage storage s = Layout.compliance();
        if (s.paused || s.addressPaused[account]) return false;
        return s.trusted[account] || _eligible(s.identityRegistry, account);
    }

    function canReceive(address account) external view returns (bool) {
        Layout.ComplianceStorage storage s = Layout.compliance();
        if (s.paused || s.addressPaused[account]) return false;
        return s.trusted[account] || _eligible(s.identityRegistry, account);
    }

    function canTransfer(address from, address to, uint256 amount) external view returns (bool) {
        (uint8 stage,,) = _evaluate(from, to, amount);
        return stage == GATE_OK;
    }

    function getFrozenTokens(address account) external view returns (uint256) {
        return _frozen(account);
    }

    function unfrozenBalanceOf(address account) external view returns (uint256) {
        return _unfrozen(account);
    }

    /// @notice Why a transfer would fail — stage, rule and reason
    /// @dev Free, never reverts, and shares `_evaluate` with enforcement. An
    ///      interface can refuse before asking anyone to sign.
    function whyBlocked(address from, address to, uint256 amount)
        external
        view
        returns (uint8 stage, address rule, string memory reason)
    {
        return _evaluate(from, to, amount);
    }

    // ── configuration ───────────────────────────────────────────────────────

    function policySet() external view returns (address) {
        return Layout.compliance().policySet;
    }

    function identityRegistry() external view returns (address) {
        return Layout.compliance().identityRegistry;
    }

    function setPolicySet(address newPolicySet) external {
        _only(Roles.UPGRADE_ADMIN);
        Layout.ComplianceStorage storage s = Layout.compliance();
        emit IEvents.PolicySetChanged(s.policySet, newPolicySet);
        s.policySet = newPolicySet;
    }

    function setIdentityRegistry(address newRegistry) external {
        _only(Roles.UPGRADE_ADMIN);
        Layout.ComplianceStorage storage s = Layout.compliance();
        emit IEvents.IdentityRegistryChanged(s.identityRegistry, newRegistry);
        s.identityRegistry = newRegistry;
    }

    // ── trust ───────────────────────────────────────────────────────────────

    /// @notice Exempt an address from claim and rule evaluation
    /// @dev Skips gates 3, 4 and 6 only. **Never** pause, and never a frozen
    ///      balance. The reason is mandatory: an unexplained exemption is
    ///      indistinguishable from an attack.
    function trust(address account, string calldata reason) external {
        _only(Roles.ISSUER_ADMIN);
        if (bytes(reason).length == 0) revert ReasonRequired();
        Layout.ComplianceStorage storage s = Layout.compliance();
        if (!s.trusted[account]) {
            s.trusted[account] = true;
            s.trustList.push(account);
        }
        s.trustReason[account] = reason;
        emit IEvents.Trusted(account, reason);
    }

    function distrust(address account, string calldata reason) external {
        _only(Roles.ISSUER_ADMIN);
        Layout.compliance().trusted[account] = false;
        emit IEvents.Distrusted(account, reason);
    }

    function isTrusted(address account) external view returns (bool) {
        return Layout.compliance().trusted[account];
    }

    function trustList() external view returns (address[] memory) {
        return Layout.compliance().trustList;
    }

    function trustReasonOf(address account) external view returns (string memory) {
        return Layout.compliance().trustReason[account];
    }

    // ── pause ───────────────────────────────────────────────────────────────

    function pause(string calldata reason) external {
        _only(Roles.COMPLIANCE_OFFICER);
        Layout.compliance().paused = true;
        emit IEvents.Paused(msg.sender, reason);
    }

    function unpause() external {
        _only(Roles.COMPLIANCE_OFFICER);
        Layout.compliance().paused = false;
        emit IEvents.Unpaused(msg.sender);
    }

    function paused() external view returns (bool) {
        return Layout.compliance().paused;
    }

    /// @notice Halt one address in both directions
    /// @dev Distinct from a freeze, which restricts sending only and takes an
    ///      amount. This is the instrument for a compromised wallet, where
    ///      continuing to receive is itself the problem.
    function pauseAddress(address account, string calldata reason) external {
        _only(Roles.COMPLIANCE_OFFICER);
        if (bytes(reason).length == 0) revert ReasonRequired();
        Layout.ComplianceStorage storage s = Layout.compliance();
        s.addressPaused[account] = true;
        s.addressPauseReason[account] = reason;
        emit IEvents.AddressPaused(account, msg.sender, reason);
    }

    function unpauseAddress(address account) external {
        _only(Roles.COMPLIANCE_OFFICER);
        Layout.compliance().addressPaused[account] = false;
        emit IEvents.AddressUnpaused(account, msg.sender);
    }

    function addressPaused(address account) external view returns (bool) {
        return Layout.compliance().addressPaused[account];
    }

    // ── holder accounting ───────────────────────────────────────────────────

    function holderCount() external view returns (uint256) {
        return Layout.compliance().holderCount;
    }

    function subjectHolderCount() external view returns (uint256) {
        return Layout.compliance().subjectHolderCount;
    }

    function subjectBalanceOf(bytes32 subject) external view returns (uint256) {
        return Layout.compliance().subjectBalance[subject];
    }

    function _only(bytes32 role) private view {
        if (!Layout.roles().roles[role][msg.sender]) revert NotAuthorized(msg.sender, role);
    }
}
