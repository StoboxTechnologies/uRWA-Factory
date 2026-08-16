// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Claim, IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IErrors} from "../interfaces/IErrors.sol";

/// @title Tier 0 — the open-source default
/// @notice Its own storage, no external service, nothing to depend on. A fork
///         runs the entire stack on this alone, which is what makes the
///         open-source claim true rather than aspirational.
/// @dev Deliberately thin. It answers "is this address permitted" and, for any
///      other claim, "yes" — because a plain allowlist has no opinion about
///      accreditation, and pretending otherwise would let a regime preset
///      appear to be enforced when it is not.
contract AllowlistRegistry is IIdentityRegistry, IErrors {
    address public admin;
    mapping(address => bool) public permitted;
    mapping(address => bytes32) public subjectOverride;

    constructor(address admin_) {
        admin = admin_;
    }

    function allow(address wallet) external {
        _onlyAdmin();
        permitted[wallet] = true;
    }

    function deny(address wallet) external {
        _onlyAdmin();
        permitted[wallet] = false;
    }

    /// @notice Bind several wallets to one person
    /// @dev Without this the allowlist counts addresses, and a holder cap on a
    ///      tier-0 token would be defeated by one investor with two wallets.
    function link(address wallet, bytes32 subject) external {
        _onlyAdmin();
        subjectOverride[wallet] = subject;
    }

    function subjectOf(address wallet) external view returns (bytes32) {
        bytes32 s = subjectOverride[wallet];
        return s == bytes32(0) ? keccak256(abi.encodePacked(wallet)) : s;
    }

    function isActive(address wallet) external view returns (bool) {
        return permitted[wallet];
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    /// @dev Answers only the base gate honestly. A rule reading
    ///      `us.regd.accredited` against a plain allowlist gets `true`, and the
    ///      issuer who chose tier 0 has been told in doc 09 that this is what
    ///      tier 0 means.
    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        return true;
    }

    function _onlyAdmin() private view {
        if (msg.sender != admin) revert NotAuthorized(msg.sender, bytes32(0));
    }
}

/// @dev The slice of Ethereum Attestation Service this adapter reads.
/// @custom:external Somebody else's contract. Declared here so we can call
///      it; its signatures are documented by EAS, not by us.
interface IEAS {
    struct Attestation {
        bytes32 uid;
        bytes32 schema;
        uint64 time;
        uint64 expirationTime;
        uint64 revocationTime;
        bytes32 refUID;
        address recipient;
        address attester;
        bool revocable;
        bytes data;
    }

    function getAttestation(bytes32 uid) external view returns (Attestation memory);
}

/// @title Tier 1 — Ethereum Attestation Service
/// @notice Base-native, so a token on Base gets attested identity with nothing
///         deployed by us. Attestations are issued by whoever the issuer trusts
///         and readable by everyone.
contract EASAdapter is IIdentityRegistry, IErrors {
    IEAS public immutable eas;
    address public admin;

    /// @dev (subject, key) → attestation uid. The mapping is the adapter's only
    ///      state; the attestations themselves live in EAS.
    mapping(bytes32 => mapping(bytes32 => bytes32)) public attestationOf;
    mapping(address => bytes32) public subjectBinding;

    constructor(address eas_, address admin_) {
        eas = IEAS(eas_);
        admin = admin_;
    }

    function bind(address wallet, bytes32 subject) external {
        _onlyAdmin();
        subjectBinding[wallet] = subject;
    }

    function record(bytes32 subject, bytes32 key, bytes32 uid) external {
        _onlyAdmin();
        attestationOf[subject][key] = uid;
    }

    function subjectOf(address wallet) external view returns (bytes32) {
        bytes32 s = subjectBinding[wallet];
        return s == bytes32(0) ? keccak256(abi.encodePacked(wallet)) : s;
    }

    function isActive(address wallet) external view returns (bool) {
        bytes32 s = subjectBinding[wallet];
        if (s == bytes32(0)) s = keccak256(abi.encodePacked(wallet));
        return _valid(attestationOf[s][keccak256("urwa.identity.valid")]);
    }

    function claim(bytes32 subject, bytes32 key) external view returns (Claim memory c) {
        bytes32 uid = attestationOf[subject][key];
        if (uid == bytes32(0)) return c;
        try eas.getAttestation(uid) returns (IEAS.Attestation memory a) {
            c.valueHash = keccak256(a.data);
            c.issuedAt = a.time;
            c.expiresAt = a.expirationTime;
            c.issuer = a.attester;
            c.revoked = a.revocationTime != 0;
        } catch {}
    }

    function hasValidClaim(bytes32 subject, bytes32 key) external view returns (bool) {
        return _valid(attestationOf[subject][key]);
    }

    /// @dev Absent, expired and revoked are three distinguishable states, and
    ///      all three answer `false` here without reverting.
    function _valid(bytes32 uid) private view returns (bool) {
        if (uid == bytes32(0)) return false;
        try eas.getAttestation(uid) returns (IEAS.Attestation memory a) {
            if (a.revocationTime != 0) return false;
            if (a.expirationTime != 0 && a.expirationTime <= block.timestamp) return false;
            return a.uid != bytes32(0);
        } catch {
            return false;
        }
    }

    function _onlyAdmin() private view {
        if (msg.sender != admin) revert NotAuthorized(msg.sender, bytes32(0));
    }
}

/// @dev The deployed StoboxDID surface this adapter reads. Every one of these
///      **reverts** for a wallet it does not know.
/// @custom:external Somebody else's contract, already live on Arbitrum One.
///      We read it; we do not define it.
interface ISDID {
    function getLinker(address wallet)
        external
        view
        returns (string memory uDID, uint256 joinDate, uint256 updateDate, bool deactivated);

    function getUserDID(address wallet)
        external
        view
        returns (string memory UDID, uint256 validTo, uint256 updatedAt, bool blocked, address lastUpdatedBy);

    function getAttribute(address wallet, string memory attributeName)
        external
        view
        returns (
            bytes memory value,
            string memory valueType,
            uint256 createdAt,
            uint256 updatedAt,
            uint256 validTo,
            address lastUpdatedBy
        );
}

/// @title Tier 2 — StoboxDID
/// @notice Reads a registry that was not written for this interface, and whose
///         getters revert for unknown wallets — the most common input an
///         integrator supplies.
/// @dev **Every call is wrapped.** Without that the token would fail ERC-7943
///         conformance on the ordinary case: an exchange checking whether a new
///         counterparty may receive, before that counterparty has ever been
///         registered.
///
///      `deactivated` is read for `isActive` but is **never** an enforcement
///      signal: on StoboxDID a holder can reverse their own deactivation, so
///      only `blocked` stops a person. See doc 09.
contract StoboxDIDAdapter is IIdentityRegistry {
    ISDID public immutable did;

    /// @dev Claim keys are `bytes32`; StoboxDID attributes are strings. The
    ///      issuer registers the mapping rather than the adapter guessing.
    mapping(bytes32 => string) public attributeName;
    address public admin;

    constructor(address did_, address admin_) {
        did = ISDID(did_);
        admin = admin_;
    }

    function mapKey(bytes32 key, string calldata name) external {
        require(msg.sender == admin, "not admin");
        attributeName[key] = name;
    }

    /// @notice The subject, derived from the DID string
    /// @dev `keccak256(bytes(uDID))`, so the same person hashes to the same
    ///      identifier on every chain the registry is deployed to — no bridge,
    ///      no oracle. A wallet with no DID gets a synthetic subject so counts
    ///      never under-report.
    function subjectOf(address wallet) external view returns (bytes32) {
        try did.getLinker(wallet) returns (string memory uDID, uint256, uint256, bool) {
            if (bytes(uDID).length != 0) return keccak256(bytes(uDID));
        } catch {}
        return keccak256(abi.encodePacked(wallet));
    }

    function isActive(address wallet) external view returns (bool) {
        try did.getLinker(wallet) returns (string memory uDID, uint256, uint256, bool deactivated) {
            if (bytes(uDID).length == 0 || deactivated) return false;
        } catch {
            return false;
        }

        try did.getUserDID(wallet) returns (string memory, uint256 validTo, uint256, bool blocked, address) {
            return !blocked && validTo > block.timestamp;
        } catch {
            return false;
        }
    }

    /// @dev Claims are keyed by subject, and StoboxDID reads by wallet. The
    ///      adapter cannot invert that mapping on chain, so claim reads take
    ///      the wallet form below; `claim` returns empty rather than lying.
    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        return false;
    }

    /// @notice The wallet-keyed read StoboxDID actually supports
    function claimForWallet(address wallet, bytes32 key) external view returns (Claim memory c) {
        string memory name = attributeName[key];
        if (bytes(name).length == 0) return c;

        try did.getAttribute(wallet, name) returns (
            bytes memory value, string memory, uint256, uint256 updatedAt, uint256 validTo, address by
        ) {
            if (value.length == 0) return c;
            c.valueHash = keccak256(value);
            c.issuedAt = uint64(updatedAt);
            c.expiresAt = uint64(validTo);
            c.issuer = by;
            c.revoked = validTo == 0;
        } catch {}
    }

    function hasValidClaimForWallet(address wallet, bytes32 key) external view returns (bool) {
        Claim memory c = this.claimForWallet(wallet, key);
        if (c.issuer == address(0) || c.revoked) return false;
        return c.expiresAt == 0 || c.expiresAt > block.timestamp;
    }
}
