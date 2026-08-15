// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IERC7943} from "./IERC7943.sol";

/// @title The transfer hook, its diagnostics and its configuration
/// @notice The part that decides whether value may move. Everything else in the
///         system exists to feed it or to act on its answer.
interface IComplianceFacet is IERC7943 {
    // ── diagnostics ─────────────────────────────────────────────────────────

    /// @notice Why a transfer would fail — stage, rule and reason
    /// @dev Free, never reverts, same code path as the transfer. This is what
    ///      lets an interface refuse before asking anyone to sign.
    /// @return stage The pipeline gate that refused; see docs/06-states.md
    /// @return rule The rule contract that refused, or `address(0)`
    /// @return reason Plain language, safe to show a holder
    function whyBlocked(address from, address to, uint256 amount)
        external
        view
        returns (uint8 stage, address rule, string memory reason);

    /// @notice ERC-1404 compatibility for integrators that predate ERC-7943
    function detectTransferRestriction(address from, address to, uint256 amount) external view returns (uint8);
    function messageForTransferRestriction(uint8 code) external view returns (string memory);

    // ── configuration ───────────────────────────────────────────────────────

    function policySet() external view returns (address);
    function identityRegistry() external view returns (address);
    function setPolicySet(address newPolicySet) external;
    function setIdentityRegistry(address newRegistry) external;

    // ── trust list ──────────────────────────────────────────────────────────

    /// @notice Exempt an address from claim and rule evaluation
    /// @dev Skips rules **only**. Never skips pause, and never skips a frozen
    ///      balance. `reason` is mandatory: an unexplained exemption is
    ///      indistinguishable from an attack.
    function trust(address account, string calldata reason) external;
    function distrust(address account, string calldata reason) external;
    function isTrusted(address account) external view returns (bool);
    function trustList() external view returns (address[] memory);
    function trustReasonOf(address account) external view returns (string memory);

    // ── pause ───────────────────────────────────────────────────────────────

    /// @notice Halt every transfer, trusted addresses included
    function pause() external;
    function unpause() external;
    function paused() external view returns (bool);

    /// @notice Halt one address in **both** directions
    /// @dev Distinct from a freeze, which restricts sending only and takes an
    ///      amount. An address pause is the instrument for a compromised wallet,
    ///      where continuing to receive is itself the problem.
    function pauseAddress(address account, string calldata reason) external;
    function unpauseAddress(address account) external;
    function addressPaused(address account) external view returns (bool);

    // ── holder accounting ───────────────────────────────────────────────────

    /// @notice Addresses holding a balance
    function holderCount() external view returns (uint256);

    /// @notice **Identities** holding a balance — the number holder caps use
    /// @dev Counting addresses is defeated by one investor with several wallets.
    function subjectHolderCount() external view returns (uint256);
    function subjectBalanceOf(bytes32 subject) external view returns (uint256);
}
