// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "./interfaces/IErrors.sol";
import {IEvents} from "./interfaces/IEvents.sol";

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
    address public issuer;
    bool private _initialised;

    /// @dev Reserved against a specific offering, and not withdrawable while
    ///      that offering is unsettled below its soft cap.
    mapping(uint256 => uint256) public reservedOf;
    mapping(uint256 => bool) public paymentsLocked;
    uint256 public totalReserved;

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

    /// @notice Hold investor payment until the soft cap decides its fate
    /// @dev The guarantee this exists for: money paid into an offering that
    ///      fails cannot be spent by the issuer in the meantime.
    function lockPayments(uint256 offeringId) external {
        _onlyRegistry();
        paymentsLocked[offeringId] = true;
        emit IEvents.PaymentsLocked(offeringId);
    }

    function unlockPayments(uint256 offeringId) external {
        _onlyRegistry();
        paymentsLocked[offeringId] = false;
        emit IEvents.PaymentsUnlocked(offeringId);
    }

    function paymentBalance(address asset) external view returns (uint256) {
        return IERC20Minimal(asset).balanceOf(address(this));
    }

    /// @notice Move an asset out
    /// @dev Refuses while any offering holding that asset is locked. The issuer
    ///      cannot reach investor money before the offering settles, and this
    ///      is the only place that could have let them.
    function withdrawERC20(address asset, address to, uint256 amount) external {
        if (msg.sender != issuer) revert NotAuthorized(msg.sender, bytes32(0));

        if (asset == token) {
            uint256 held = IERC20Minimal(token).balanceOf(address(this));
            if (held < totalReserved + amount) revert InsufficientAvailable(amount, held - totalReserved);
        }

        if (!IERC20Minimal(asset).transfer(to, amount)) revert InsufficientAvailable(amount, 0);
        emit IEvents.Withdrawn(asset, to, amount);
    }

    /// @notice Refuse a withdrawal while an offering's payments are locked
    function withdrawPayments(address asset, address to, uint256 amount, uint256 offeringId) external {
        if (msg.sender != issuer) revert NotAuthorized(msg.sender, bytes32(0));
        if (paymentsLocked[offeringId]) revert PaymentsAreLocked(offeringId);
        if (!IERC20Minimal(asset).transfer(to, amount)) revert InsufficientAvailable(amount, 0);
        emit IEvents.Withdrawn(asset, to, amount);
    }

    function _onlyRegistry() private view {
        if (msg.sender != offeringRegistry) revert OnlyOfferingRegistry();
    }
}
