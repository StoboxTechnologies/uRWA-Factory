// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "./interfaces/IErrors.sol";
import {IEvents} from "./interfaces/IEvents.sol";
import {Roles} from "./interfaces/Roles.sol";

/// @dev The treasury defers to the token's role register rather than to an
///      address stored here. Custody is the last place a revoked role should
///      still work.
interface ITokenRoles {
    function hasRole(bytes32 role, address account) external view returns (bool);
}

/// @dev The subset of ERC-20 the treasury needs from the tokens it holds.
interface IERC20Minimal {
    function balanceOf(address) external view returns (uint256);
    function transfer(address, uint256) external returns (bool);
}

/// @title Per-token custody
/// @notice **One treasury per token.** A compromise reaches exactly one asset,
///         which is the entire reason this is not a shared vault.
/// @dev The treasury holds security tokens as an ordinary holder: the
///      compliance pipeline applies to it too. The factory adds it to the trust
///      list explicitly rather than the token special-casing it in code — an
///      exemption written into the ledger would be one nobody could audit.
contract Treasury is IErrors {
    address public token;
    address public offeringRegistry;
    /// @dev Provenance only. Who may take money out is decided by the token's
    ///      roles, not by this address — see `_onlyRole`.
    address public issuer;
    bool private _initialised;

    /// @dev Reserved against a specific offering, and not withdrawable while
    ///      that offering is unsettled below its soft cap.
    mapping(uint256 => uint256) public reservedOf;
    uint256 public totalReserved;

    /// @dev Investor payments held against an unsettled offering, tracked by
    ///      amount and asset rather than a bare per-offering flag. The old flag
    ///      could not answer the only question a withdrawal asks — "how much of
    ///      *this asset* is spoken for?" — because funds are fungible per asset
    ///      while a lock was per offering. A withdrawal now compares the amount
    ///      wanted against the free (held minus locked) balance of that asset.
    mapping(address => uint256) public lockedPayments; // per asset
    mapping(uint256 => uint256) public lockedOf; // per offering
    mapping(uint256 => address) private _offeringAsset;

    /// @notice Initialise a clone
    /// @dev Minimal proxies have no constructor, so this stands in for one and
    ///      may be called exactly once.
    function initialise(address token_, address issuer_, address offeringRegistry_) external {
        if (_initialised) revert NotAuthorized(msg.sender, bytes32(0));
        _initialised = true;
        token = token_;
        issuer = issuer_;
        offeringRegistry = offeringRegistry_;
    }

    function availableBalance() external view returns (uint256) {
        uint256 held = IERC20Minimal(token).balanceOf(address(this));
        return held > totalReserved ? held - totalReserved : 0;
    }

    // ── reservations ────────────────────────────────────────────────────────

    function reserve(uint256 amount, uint256 offeringId) external {
        _onlyRegistry();
        uint256 held = IERC20Minimal(token).balanceOf(address(this));
        if (held < totalReserved + amount) revert InsufficientAvailable(amount, held - totalReserved);
        reservedOf[offeringId] += amount;
        totalReserved += amount;
        emit IEvents.Reserved(offeringId, amount);
    }

    function release(uint256 amount, uint256 offeringId) external {
        _onlyRegistry();
        uint256 held = reservedOf[offeringId];
        uint256 freed = amount > held ? held : amount;
        reservedOf[offeringId] = held - freed;
        totalReserved -= freed;
        emit IEvents.Released(offeringId, freed);
    }

    // ── investor payments ───────────────────────────────────────────────────

    /// @notice Lock a payment just received against an offering
    /// @dev Called by the registry as each purchase's money lands. The amount is
    ///      added to the locked total for that asset, so a withdrawal can tell
    ///      how much of the balance is investor money that must stay refundable.
    function lockPayment(uint256 offeringId, address asset, uint256 amount) external {
        _onlyRegistry();
        lockedPayments[asset] += amount;
        lockedOf[offeringId] += amount;
        _offeringAsset[offeringId] = asset;
        emit IEvents.PaymentsLocked(offeringId);
    }

    /// @notice Release an offering's locked payments once it settles
    /// @dev The soft cap was met; the money is the issuer's to withdraw. Only
    ///      the offering's own locked total is released — funds belonging to
    ///      other offerings in the same asset stay locked.
    function unlockPayments(uint256 offeringId) external {
        _onlyRegistry();
        address asset = _offeringAsset[offeringId];
        uint256 amount = lockedOf[offeringId];
        if (amount != 0) {
            lockedPayments[asset] -= amount;
            lockedOf[offeringId] = 0;
        }
        emit IEvents.PaymentsUnlocked(offeringId);
    }

    function paymentBalance(address asset) external view returns (uint256) {
        return IERC20Minimal(asset).balanceOf(address(this));
    }

    /// @notice What of an asset is free to withdraw — held, minus everything spoken for
    function freeBalance(address asset) public view returns (uint256) {
        uint256 held = IERC20Minimal(asset).balanceOf(address(this));
        uint256 encumbered = asset == token ? totalReserved : lockedPayments[asset];
        return held > encumbered ? held - encumbered : 0;
    }

    /// @notice Move an asset out
    /// @dev Refuses to touch anything spoken for: the security token's reserved
    ///      supply, or a payment asset's locked investor money. The treasury
    ///      enforces this, not operator discipline — the withdrawal fails
    ///      whichever door and whichever asset it comes through.
    function withdrawERC20(address asset, address to, uint256 amount) external {
        _onlyRole(Roles.SUPPLY_OPERATOR);
        uint256 free = freeBalance(asset);
        if (amount > free) revert InsufficientAvailable(amount, free);
        if (!IERC20Minimal(asset).transfer(to, amount)) revert InsufficientAvailable(amount, 0);
        emit IEvents.Withdrawn(asset, to, amount);
    }

    /// @notice Return investor payment
    /// @dev Callable by the offering registry **while payments are locked** —
    ///      that is precisely what the lock is for. Returning money reduces the
    ///      locked total for that asset and offering by the same amount, so the
    ///      free balance the invariant rests on stays correct.
    function refund(uint256 offeringId, address asset, address investor, uint256 amount) external {
        _onlyRegistry();
        uint256 locked = lockedOf[offeringId];
        uint256 dec = amount > locked ? locked : amount;
        lockedOf[offeringId] = locked - dec;
        lockedPayments[asset] = lockedPayments[asset] > dec ? lockedPayments[asset] - dec : 0;
        if (!IERC20Minimal(asset).transfer(investor, amount)) revert InsufficientAvailable(amount, 0);
        emit IEvents.Withdrawn(asset, investor, amount);
    }

    /// @notice Withdraw payment proceeds
    /// @dev Refuses to move locked investor money. The guard is the free
    ///      balance of the asset, not a caller-supplied offering id — a lock is
    ///      on an amount of an asset, and no id the caller chooses can unlock it.
    function withdrawPayments(address asset, address to, uint256 amount) external {
        _onlyRole(Roles.ISSUER_ADMIN);
        uint256 free = freeBalance(asset);
        if (amount > free) revert PaymentsAreLocked(0);
        if (!IERC20Minimal(asset).transfer(to, amount)) revert InsufficientAvailable(amount, 0);
        emit IEvents.Withdrawn(asset, to, amount);
    }

    /// @dev Asked of the token, every time. An address recorded here at
    ///      creation would go on working after the role behind it was revoked,
    ///      which is the one case where that matters most.
    function _onlyRole(bytes32 role) private view {
        if (!ITokenRoles(token).hasRole(role, msg.sender)) revert NotAuthorized(msg.sender, role);
    }

    function _onlyRegistry() private view {
        if (msg.sender != offeringRegistry) revert OnlyOfferingRegistry();
    }
}
