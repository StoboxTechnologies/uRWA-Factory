// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice One attested fact about a subject
/// @dev `valueHash`, never a plaintext value. A hashed passport number is still
///      personal data; a hashed jurisdiction is not, provided the value space is
///      not trivially enumerable — which is why thresholds use `numeric`.
struct Claim {
    bytes32 valueHash;
    uint256 numeric; // optional bound, for thresholds and tiers
    uint64 issuedAt;
    uint64 expiresAt; // 0 = no expiry
    address issuer; // the attesting authority
    bool revoked;
}

/// @title Who someone is
/// @notice One interface, three interchangeable implementations: an allowlist,
///         Ethereum Attestation Service, and StoboxDID. The token neither knows
///         nor cares which is installed, and switching is one call that moves
///         no balance.
/// @dev **Nothing here may revert.** The StoboxDID adapter wraps every call in
///      `try/catch` because the deployed registry reverts for unknown wallets —
///      the single most common input — and that would break ERC-7943
///      conformance on the ordinary case.
interface IIdentityRegistry {
    /// @notice Which identity owns this wallet
    /// @dev A wallet with no record is given a synthetic subject derived from
    ///      its address, so holder counts never under-report.
    function subjectOf(address wallet) external view returns (bytes32 subject);

    /// @notice Is this wallet usable right now
    /// @dev Reads deactivation where the source supports it. **Never an
    ///      enforcement signal** on StoboxDID: a holder can reverse their own
    ///      deactivation. Rules that must stop a person read the block status.
    function isActive(address wallet) external view returns (bool);

    function claim(bytes32 subject, bytes32 key) external view returns (Claim memory);

    /// @notice Claim exists, is unexpired and is not revoked
    /// @dev Absent, expired and revoked are three distinguishable states.
    function hasValidClaim(bytes32 subject, bytes32 key) external view returns (bool);
}
