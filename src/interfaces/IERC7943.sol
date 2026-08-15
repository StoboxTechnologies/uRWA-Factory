// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ERC-7943 — the uRWA interface
/// @notice The standard this project exists to implement. It fixes *that* a
///         token can gate transfers, freeze balances and force a transfer —
///         deliberately not *how* eligibility is decided.
/// @dev Interface id `0x3edbb4c4`.
///
///      **The four view functions must never revert.** An unknown wallet is the
///      most common input an integrator supplies, and a revert there turns a
///      pre-flight check into a failure. Every external call behind them is
///      wrapped in `try/catch`; absence is an answer, not an error.
interface IERC7943 {
    /// @notice May this account send at all
    function canSend(address account) external view returns (bool);

    /// @notice May this account receive at all
    function canReceive(address account) external view returns (bool);

    /// @notice Would this exact transfer succeed, right now
    /// @dev The same code path the transfer itself takes, in view mode, so
    ///      enforcement and explanation cannot drift.
    function canTransfer(address from, address to, uint256 amount) external view returns (bool);

    /// @notice Tokens held but not movable — admin freeze plus unexpired lockups
    /// @dev May exceed `balanceOf`. That is legal and must not revert: a freeze
    ///      set before a redemption can outlive the balance it referred to.
    function getFrozenTokens(address account) external view returns (uint256);

    /// @notice Set the frozen amount for an account
    function setFrozenTokens(address account, uint256 amount) external returns (bool);

    /// @notice Move tokens without the holder's consent, under legal compulsion
    /// @dev Bypasses freezes and lockups; still checks `canReceive`. A forced
    ///      transfer to an ineligible recipient is still an illegal transfer.
    function forcedTransfer(address from, address to, uint256 amount) external returns (bool);
}
