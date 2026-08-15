// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice One anchored state of an asset record
/// @dev Roots and metadata only. **No values, ever.**
struct Snapshot {
    bytes32 root; // sparse Merkle root over every datapoint leaf
    bytes32 revocationRoot; // revoked attestations
    uint32 version;
    uint64 takenAt;
    bytes32 schemaVersion; // the registry version the leaves conform to
}

struct Attestation {
    address attestor;
    bytes32 group;
    uint64 issuedAt;
    uint64 validUntil;
    bool revoked;
}

/// @dev Group-scoped rather than per datapoint, and always expiring. There is
///      no perpetual grant in the type.
struct AccessGrant {
    address grantee;
    bytes32[] groups;
    uint64 expiresAt;
    bytes32 termsHash; // the NDA or engagement letter this grant sits under
    bool revoked;
}

struct TokenLink {
    address token;
    uint256 chainId;
    bool confirmed; // true only after the passport side agrees
}

/// @title Evidence about the underlying asset
/// @notice The one proprietary component — and the token works entirely without
///         it. A passport is **descriptive, never dispositive**: it records what
///         an asset is, and never gates a transfer unless the issuer opts in
///         through an ordinary policy rule.
/// @dev The interface is open so a fork can write its own passport. What is
///      retained is the work of maintaining an attested record, not the ability
///      to interoperate with one.
interface IAssetPassport {
    // ── the handshake ───────────────────────────────────────────────────────

    /// @notice Anyone may point a token at a passport
    function declareToken(address token, uint256 chainId) external;

    /// @notice Only the passport confirms — this is what makes it provenance
    /// @dev Declared-but-unconfirmed is exactly what a forgery looks like.
    function confirmToken(bytes32 passportId, address token, uint256 chainId) external;
    function revokeToken(bytes32 passportId, address token) external;
    function isConfirmed(bytes32 passportId, address token) external view returns (bool);
    function tokensOf(bytes32 passportId) external view returns (address[] memory);

    // ── snapshots ───────────────────────────────────────────────────────────

    function anchorSnapshot(bytes32 passportId, Snapshot calldata snapshot) external;

    /// @notice The current snapshot, and whether its group windows have elapsed
    /// @dev Staleness is a readable fact. That is the difference between
    ///      "nothing has changed" and "nobody has looked in three years".
    function snapshotOf(bytes32 passportId) external view returns (Snapshot memory, bool stale);

    // ── proofs, verifiable by anyone ────────────────────────────────────────

    /// @notice Verify a disclosed value against the anchored root
    /// @dev Needs no permission and no cooperation from us. A proof only we
    ///      could verify would be worth nothing.
    function verify(bytes32 passportId, bytes32 code, bytes calldata value, bytes32 salt, bytes32[] calldata proof)
        external
        view
        returns (bool);

    /// @notice Prove a datapoint was never recorded
    /// @dev The tree spans the whole key space, so an issuer cannot quietly
    ///      omit an inconvenient fact and leave "missing" indistinguishable
    ///      from "not disclosed".
    function verifyAbsence(bytes32 passportId, bytes32 code, bytes32[] calldata proof) external view returns (bool);

    // ── attestations and access ─────────────────────────────────────────────

    function recordAttestation(bytes32 passportId, Attestation calldata attestation) external;
    function attestationsOf(bytes32 passportId) external view returns (Attestation[] memory);

    function grantAccess(bytes32 passportId, AccessGrant calldata grant) external;
    function revokeAccess(bytes32 passportId, address grantee) external;
    function accessOf(bytes32 passportId, address grantee) external view returns (AccessGrant memory);
}

/// @title Who may sign, and when they could
/// @notice Signature validity is checked against the key valid **at signing
///         time**, not at reading time — otherwise rotating a key would
///         invalidate every attestation ever made under it.
interface IAttestorRegistry {
    function registerKey(address attestor, uint64 validFrom, uint64 validTo) external;
    function revokeKey(address attestor) external;
    function isValidAt(address attestor, uint64 timestamp) external view returns (bool);
    function attestors() external view returns (address[] memory);
}
