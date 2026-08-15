// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title ERC-20 core and ERC-2612 permit
/// @notice The ledger plane. These selectors are registered against the diamond
///         itself, so `diamondCut` reverts rather than replacing them.
/// @dev This is the whole basis of the three-plane split: a compliance bug can
///      stop trading, and can never reach a balance.
interface IuRWAToken {
    function name() external view returns (string memory);
    function symbol() external view returns (string memory);
    function decimals() external view returns (uint8);
    function totalSupply() external view returns (uint256);
    function balanceOf(address account) external view returns (uint256);
    function allowance(address owner, address spender) external view returns (uint256);

    function transfer(address to, uint256 value) external returns (bool);
    function transferFrom(address from, address to, uint256 value) external returns (bool);
    function approve(address spender, uint256 value) external returns (bool);

    // ── ERC-2612 ────────────────────────────────────────────────────────────

    function permit(address owner, address spender, uint256 value, uint256 deadline, uint8 v, bytes32 r, bytes32 s)
        external;
    function nonces(address owner) external view returns (uint256);
    function DOMAIN_SEPARATOR() external view returns (bytes32);

    // ── provenance ──────────────────────────────────────────────────────────

    /// @notice ERC-173, for explorer and tooling compatibility
    function owner() external view returns (address);

    /// @notice Which factory deployed this token
    function deployer() external view returns (address);

    /// @notice Hard cap; `0` means unlimited
    /// @dev An investor must be able to see that dilution is bounded.
    function maxSupply() external view returns (uint256);
}
