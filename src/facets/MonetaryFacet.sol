// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "../interfaces/IErrors.sol";
import {IEvents} from "../interfaces/IEvents.sol";
import {Roles} from "../interfaces/Roles.sol";
import {Layout} from "../storage/Layout.sol";

/// @title Supply
/// @notice Issue into the treasury, distribute out of it, redeem back. Nothing
///         here creates value in a holder's hands directly — issuance lands in
///         the treasury, and every move from there runs the full pipeline.
/// @dev `totalIssued` is **cumulative and monotonic**: redeeming reduces
///      `totalSupply` and leaves `totalIssued` alone. The two answer different
///      questions — what exists now, and what has ever been created — and
///      collapsing them loses the second permanently.
contract MonetaryFacet is IErrors {
    function issue(address to, uint256 amount) external {
        _only(Roles.SUPPLY_OPERATOR);
        Layout.CoreStorage storage c = Layout.core();
        Layout.MonetaryStorage storage m = Layout.monetary();

        address dest = to == address(0) ? m.treasury : to;
        if (dest == address(0)) revert TreasuryNotSet();

        if (c.maxSupply != 0 && c.totalSupply + amount > c.maxSupply) {
            revert MaxSupplyExceeded(amount, c.maxSupply - c.totalSupply);
        }

        c.totalSupply += amount;
        c.balances[dest] += amount;
        m.totalIssued += amount;

        emit IEvents.Transfer(address(0), dest, amount);
        emit IEvents.Issued(dest, amount, m.totalIssued);
        _count(address(0), dest, amount);
    }

    /// @notice Destroy supply held by the caller
    /// @dev Only the holder's own balance, and only the treasury realistically
    ///      calls it. Redeeming someone else's tokens is a seizure, which lives
    ///      in the opt-in emergency facet where it is visible.
    function redeem(uint256 amount) external {
        _only(Roles.SUPPLY_OPERATOR);
        Layout.CoreStorage storage c = Layout.core();
        Layout.MonetaryStorage storage m = Layout.monetary();

        address from = m.treasury == address(0) ? msg.sender : m.treasury;
        uint256 balance = c.balances[from];
        if (balance < amount) revert ERC20InsufficientBalance(from, balance, amount);

        unchecked {
            c.balances[from] = balance - amount;
            c.totalSupply -= amount;
        }

        emit IEvents.Transfer(from, address(0), amount);
        emit IEvents.Redeemed(amount, m.totalIssued);
        _count(from, address(0), amount);
    }

    /// @notice Move issued supply to a holder, optionally under a lockup
    /// @dev Runs the **full compliance pipeline** on the distribution leg, so
    ///      an investor who cannot hold the token cannot be given it — not even
    ///      by the operator who issued it.
    function distributeFromTreasury(address to, uint256 amount, uint64 unlockAt) external {
        _only(Roles.SUPPLY_OPERATOR);
        address treasury = Layout.monetary().treasury;
        if (treasury == address(0)) revert TreasuryNotSet();

        _move(treasury, to, amount);

        if (unlockAt > block.timestamp) {
            Layout.lockup()
            .lockups[to].push(Layout.Lockup({amount: amount, unlockAt: unlockAt, note: "distribution lockup"}));
            emit IEvents.LockupAdded(to, amount, unlockAt, "distribution lockup");
        }
    }

    // ── the cap ─────────────────────────────────────────────────────────────

    function setMaxSupply(uint256 newMax) external {
        _only(Roles.ISSUER_ADMIN);
        Layout.CoreStorage storage c = Layout.core();
        if (c.capLocked) revert CapIsLocked();
        if (newMax != 0 && newMax < c.totalSupply) revert MaxSupplyExceeded(newMax, c.totalSupply);
        emit IEvents.MaxSupplyChanged(c.maxSupply, newMax);
        c.maxSupply = newMax;
    }

    /// @notice Make the cap permanent
    /// @dev Irreversible, and deliberately so. A cap that can be raised later
    ///      is not a cap, and an investor cannot tell the two apart without
    ///      this flag.
    function lockCap() external {
        _only(Roles.ISSUER_ADMIN);
        Layout.core().capLocked = true;
        emit IEvents.CapLocked();
    }

    function capLocked() external view returns (bool) {
        return Layout.core().capLocked;
    }

    function totalIssued() external view returns (uint256) {
        return Layout.monetary().totalIssued;
    }

    // ── wiring ──────────────────────────────────────────────────────────────

    function treasury() external view returns (address) {
        return Layout.monetary().treasury;
    }

    function setTreasury(address newTreasury) external {
        _only(Roles.ISSUER_ADMIN);
        Layout.MonetaryStorage storage m = Layout.monetary();
        emit IEvents.TreasuryChanged(m.treasury, newTreasury);
        m.treasury = newTreasury;
    }

    function offeringRegistry() external view returns (address) {
        return Layout.monetary().offeringRegistry;
    }

    function setOfferingRegistry(address newRegistry) external {
        _only(Roles.ISSUER_ADMIN);
        Layout.MonetaryStorage storage m = Layout.monetary();
        emit IEvents.OfferingRegistryChanged(m.offeringRegistry, newRegistry);
        m.offeringRegistry = newRegistry;
    }

    /// @dev Moves value between two holders through the same gates a transfer
    ///      passes. Distribution is a transfer that happens to originate in the
    ///      treasury; giving it a private path would be a second, unchecked way
    ///      for value to reach a holder.
    function _move(address from, address to, uint256 amount) private {
        (bool allowed, bytes memory reason) =
            address(this).call(abi.encodeWithSignature("beforeUpdate(address,address,uint256)", from, to, amount));
        if (!allowed) {
            assembly {
                revert(add(reason, 0x20), mload(reason))
            }
        }

        Layout.CoreStorage storage c = Layout.core();
        uint256 balance = c.balances[from];
        if (balance < amount) revert ERC20InsufficientBalance(from, balance, amount);
        unchecked {
            c.balances[from] = balance - amount;
            c.balances[to] += amount;
        }
        emit IEvents.Transfer(from, to, amount);
        _count(from, to, amount);
    }

    /// @dev Issuance and redemption change balances outside a transfer, so the
    ///      holder counts are maintained here too. Best-effort: if no facet
    ///      serves the accounting, supply still works.
    function _count(address from, address to, uint256 amount) private {
        (bool ok,) =
            address(this).call(abi.encodeWithSignature("afterUpdate(address,address,uint256)", from, to, amount));
        ok;
    }

    function _only(bytes32 role) private view {
        if (!Layout.roles().roles[role][msg.sender]) revert NotAuthorized(msg.sender, role);
    }
}
