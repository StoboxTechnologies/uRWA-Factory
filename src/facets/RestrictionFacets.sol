// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "../interfaces/IErrors.sol";
import {IEvents} from "../interfaces/IEvents.sol";
import {Roles} from "../interfaces/Roles.sol";
import {Layout} from "../storage/Layout.sol";

/// @dev The composed frozen total, shared by both facets and by the pipeline.
///      One implementation, so the number a holder sees, the number the pipeline
///      enforces and the number the event reports cannot disagree.
library Restrictions {
    function frozenOf(address account) internal view returns (uint256 total) {
        total = Layout.freeze().adminFrozen[account];
        Layout.Lockup[] storage locks = Layout.lockup().lockups[account];
        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].unlockAt <= block.timestamp) continue;
            // Saturating add. `setFrozenTokens(account, type(uint256).max)` is
            // the freeze-everything idiom, and a frozen total is allowed to
            // exceed the balance — so a lockup on top of it must not overflow
            // and revert. `frozenOf` feeds the four views that ERC-7943 says
            // must never revert; a panic here would break every one of them.
            unchecked {
                uint256 next = total + locks[i].amount;
                total = next < total ? type(uint256).max : next;
            }
        }
    }
}

/// @title Admin freeze
/// @notice An indefinite restriction on part of a balance. Set by compliance,
///         cleared by compliance, and never expiring on its own.
contract FreezeFacet is IErrors {
    /// @notice Set the administratively frozen amount
    /// @dev The `Frozen` event carries the **composed** total — freeze plus
    ///      unexpired lockups — not the amount passed in, so an integrator
    ///      reading one event sees the same figure `getFrozenTokens` returns
    ///      and never has to sum history.
    function setFrozenTokens(address account, uint256 amount) external returns (bool) {
        _only(Roles.COMPLIANCE_OFFICER);
        Layout.freeze().adminFrozen[account] = amount;
        emit IEvents.Frozen(account, Restrictions.frozenOf(account));
        return true;
    }

    function adminFrozenOf(address account) external view returns (uint256) {
        return Layout.freeze().adminFrozen[account];
    }

    function _only(bytes32 role) private view {
        if (!Layout.roles().roles[role][msg.sender]) revert NotAuthorized(msg.sender, role);
    }
}

/// @title Dated lockups
/// @notice Restrictions that end by timestamp. **No transaction releases them,
///         no keeper watches them, and there is no stale state to clean up** —
///         the composed total simply stops counting a lockup once its date has
///         passed.
contract LockupFacet is IErrors {
    /// @dev Bounded so the composed total cannot be made unaffordable to
    ///      compute. A holder given a hundred lockups would find every transfer
    ///      priced out of reach, which is a restriction by accident.
    uint256 internal constant MAX_LOCKUPS = 32;

    function addLockup(address account, uint256 amount, uint64 unlockAt, string calldata note) external {
        _only(Roles.COMPLIANCE_OFFICER);
        if (bytes(note).length == 0) revert ReasonRequired();

        Layout.Lockup[] storage locks = Layout.lockup().lockups[account];
        if (locks.length >= MAX_LOCKUPS) revert RuleLimitExceeded(locks.length, MAX_LOCKUPS);

        locks.push(Layout.Lockup({amount: amount, unlockAt: unlockAt, note: note}));
        emit IEvents.LockupAdded(account, amount, unlockAt, note);
    }

    function clearLockups(address account, string calldata reason) external {
        _only(Roles.COMPLIANCE_OFFICER);
        if (bytes(reason).length == 0) revert ReasonRequired();
        delete Layout.lockup().lockups[account];
        emit IEvents.LockupsCleared(account, reason);
    }

    /// @notice Drop entries whose date has passed
    /// @dev **Housekeeping only.** Expiry is already in effect without it; this
    ///      exists so a long-lived holder's array does not grow forever, and
    ///      anyone may call it because it can only reduce restrictions that
    ///      have already lapsed.
    function releaseExpired(address account) external {
        Layout.Lockup[] storage locks = Layout.lockup().lockups[account];
        uint256 removed;
        for (uint256 i = locks.length; i > 0; i--) {
            uint256 idx = i - 1;
            if (locks[idx].unlockAt <= block.timestamp) {
                locks[idx] = locks[locks.length - 1];
                locks.pop();
                removed++;
            }
        }
        if (removed > 0) emit IEvents.ExpiredReleased(account, removed);
    }

    function lockupsOf(address account) external view returns (Layout.Lockup[] memory) {
        return Layout.lockup().lockups[account];
    }

    function lockupCount(address account) external view returns (uint256) {
        return Layout.lockup().lockups[account].length;
    }

    /// @notice The part of a balance held by unexpired lockups
    function lockedAmountOf(address account) external view returns (uint256 total) {
        Layout.Lockup[] storage locks = Layout.lockup().lockups[account];
        for (uint256 i = 0; i < locks.length; i++) {
            if (locks[i].unlockAt > block.timestamp) total += locks[i].amount;
        }
    }

    function _only(bytes32 role) private view {
        if (!Layout.roles().roles[role][msg.sender]) revert NotAuthorized(msg.sender, role);
    }
}
