// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Claim, IIdentityRegistry} from "../interfaces/IIdentityRegistry.sol";
import {IRule, RuleContext} from "../interfaces/IPolicy.sol";
import {ClaimKeys} from "../interfaces/Roles.sol";

/// @dev Shared reading of the claims plane. Every rule needs the same
///      try/catch discipline, and writing it once means no rule can forget it.
abstract contract ClaimReader is IRule {
    IIdentityRegistry public immutable registry;

    constructor(address registry_) {
        registry = IIdentityRegistry(registry_);
    }

    function _has(bytes32 subject, bytes32 key) internal view returns (bool) {
        try registry.hasValidClaim(subject, key) returns (bool ok) {
            return ok;
        } catch {
            return false;
        }
    }

    function _claim(bytes32 subject, bytes32 key) internal view returns (Claim memory c) {
        try registry.claim(subject, key) returns (Claim memory got) {
            return got;
        } catch {
            return c;
        }
    }

    /// @dev Rules read; they never write. Where one appears to need state, the
    ///      token maintains it and passes it through `RuleContext` — which is
    ///      what keeps every rule replaceable without a data migration.
    function bounds(address) external view virtual returns (uint256, uint256) {
        return (0, type(uint256).max);
    }
}

/// @title The base gate every preset includes
contract HasValidIdentity is ClaimReader {
    constructor(address r) ClaimReader(r) {}

    function check(address, address, uint256, RuleContext calldata ctx) external view returns (bool, string memory) {
        if (!_has(ctx.fromSubject, ClaimKeys.IDENTITY_VALID)) return (false, "sender has no valid identity");
        if (!_has(ctx.toSubject, ClaimKeys.IDENTITY_VALID)) return (false, "recipient has no valid identity");
        return (true, "");
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("HasValidIdentity");
    }
}

/// @title Jurisdiction, either way round
/// @notice Countries are compared as **hashes**, so no plaintext country code
///         appears in calldata where an observer could read a holder's
///         residence from the mempool.
contract JurisdictionRule is ClaimReader {
    bool public immutable isDenyList;
    mapping(bytes32 => bool) public listed;

    constructor(address r, bool deny, bytes32[] memory countries) ClaimReader(r) {
        isDenyList = deny;
        for (uint256 i = 0; i < countries.length; i++) {
            listed[countries[i]] = true;
        }
    }

    function check(address, address, uint256, RuleContext calldata ctx) external view returns (bool, string memory) {
        // The claim must be valid before its value is read. `RequiresClaim`
        // gates on `_has` first; this rule did not, so it enforced jurisdiction
        // against a revoked or expired attestation — a holder who relocated
        // into an excluded country kept passing on the stale evidence.
        if (!_has(ctx.toSubject, ClaimKeys.JURISDICTION_COUNTRY)) return (false, "jurisdiction unknown");
        bytes32 country = _claim(ctx.toSubject, ClaimKeys.JURISDICTION_COUNTRY).valueHash;
        if (country == bytes32(0)) return (false, "jurisdiction unknown");
        if (isDenyList) {
            return listed[country] ? (false, "jurisdiction excluded") : (true, "");
        }
        return listed[country] ? (true, "") : (false, "jurisdiction not permitted");
    }

    function ruleId() external view returns (bytes32) {
        return isDenyList ? keccak256("JurisdictionDeny") : keccak256("JurisdictionAllow");
    }
}

/// @title A single claim must be present and valid
/// @notice Covers accreditation, professional status, qualified-investor status
///         and sanctions clearance — the same shape with a different key, so
///         one audited contract serves them all.
contract RequiresClaim is ClaimReader {
    bytes32 public immutable key;
    string private _failure;
    uint256 public immutable minimumInvestment;

    /// @notice Seconds a claim stays acceptable; `0` means no window
    /// @dev Sanctions clearance needs one; accreditation does not. Enforced by
    ///      the rule rather than the registry, so two tokens can demand
    ///      different cadences from the same claim.
    uint64 public immutable freshness;

    constructor(address r, bytes32 key_, string memory failure_, uint256 minimum_, uint64 freshness_) ClaimReader(r) {
        key = key_;
        _failure = failure_;
        minimumInvestment = minimum_;
        freshness = freshness_;
    }

    function check(address, address, uint256, RuleContext calldata ctx) external view returns (bool, string memory) {
        if (!_has(ctx.toSubject, key)) return (false, _failure);
        if (freshness != 0) {
            Claim memory c = _claim(ctx.toSubject, key);
            if (c.issuedAt + freshness < block.timestamp) return (false, "screening is stale");
        }
        return (true, "");
    }

    /// @notice The minimum this rule implies for an account
    /// @dev How accreditation-linked minimums reach the offering registry
    ///      without any rule mutating anything.
    function bounds(address) external view override returns (uint256, uint256) {
        return (minimumInvestment, type(uint256).max);
    }

    function ruleId() external view returns (bytes32) {
        return keccak256(abi.encodePacked("RequiresClaim", key));
    }
}

/// @title The holder register cap
/// @notice **Counts subjects, not addresses.** An address-based cap is defeated
///         by one investor using several wallets, and it refuses the honest
///         second investor at the same time.
contract MaxHolders is IRule {
    uint256 public immutable cap;

    constructor(uint256 cap_) {
        cap = cap_;
    }

    function check(address, address to, uint256, RuleContext calldata ctx) external view returns (bool, string memory) {
        // A recipient who already holds does not add to the register.
        if (_alreadyHolds(ctx.token, to)) return (true, "");
        if (ctx.subjectHolderCount >= cap) return (false, "holder limit reached");
        return (true, "");
    }

    function _alreadyHolds(address token, address who) private view returns (bool) {
        (bool ok, bytes memory data) = token.staticcall(abi.encodeWithSignature("balanceOf(address)", who));
        return ok && data.length >= 32 && abi.decode(data, (uint256)) > 0;
    }

    function bounds(address) external pure returns (uint256, uint256) {
        return (0, type(uint256).max);
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("MaxHolders");
    }
}

/// @title Blackout periods
/// @notice For record dates, distributions and corporate actions.
contract TransferWindow is IRule {
    uint64 public immutable closesAt;
    uint64 public immutable reopensAt;

    constructor(uint64 closesAt_, uint64 reopensAt_) {
        closesAt = closesAt_;
        reopensAt = reopensAt_;
    }

    function check(address, address, uint256, RuleContext calldata) external view returns (bool, string memory) {
        if (block.timestamp >= closesAt && block.timestamp < reopensAt) {
            return (false, "transfers closed during this window");
        }
        return (true, "");
    }

    function bounds(address) external pure returns (uint256, uint256) {
        return (0, type(uint256).max);
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("TransferWindow");
    }
}

/// @title MiCA — facts about the instrument, not the holder
/// @notice The subject queried is the **issuer's**, fixed at deployment, so the
///         answer is identical for every holder. A stale reserve attestation
///         therefore stops the whole token at once — intended for a backed
///         instrument, and surprising to an issuer who does not expect it.
contract MiCARule is ClaimReader {
    bytes32 public immutable subject;
    bytes32 public immutable key;
    uint64 public immutable freshness;
    string private _failure;

    constructor(address r, bytes32 issuerSubject, bytes32 key_, uint64 freshness_, string memory failure_)
        ClaimReader(r)
    {
        subject = issuerSubject;
        key = key_;
        freshness = freshness_;
        _failure = failure_;
    }

    function check(address, address, uint256, RuleContext calldata) external view returns (bool, string memory) {
        if (!_has(subject, key)) return (false, _failure);
        if (freshness != 0) {
            Claim memory c = _claim(subject, key);
            if (c.issuedAt + freshness < block.timestamp) return (false, "attestation is stale");
        }
        return (true, "");
    }

    function ruleId() external view returns (bytes32) {
        return keccak256(abi.encodePacked("MiCARule", key));
    }
}

/// @title The concentration ceiling
/// @notice A cap on how much of the supply **one person** may hold, counted
///         across every wallet they control. An address-based version is
///         defeated by the same evasion holder caps are.
contract MaxBalancePerHolder is IRule {
    /// @dev Either an absolute amount, or basis points of supply. Basis points
    ///      track a growing float; an absolute figure does not, and an issuer
    ///      who picks the wrong one finds out only when supply changes.
    uint256 public immutable absoluteCap;
    uint16 public immutable basisPoints;

    constructor(uint256 absoluteCap_, uint16 basisPoints_) {
        absoluteCap = absoluteCap_;
        basisPoints = basisPoints_;
    }

    function check(address, address, uint256 amount, RuleContext calldata ctx)
        external
        view
        returns (bool, string memory)
    {
        uint256 cap = absoluteCap;
        if (basisPoints != 0) {
            uint256 supply = _read(ctx.token, abi.encodeWithSignature("totalSupply()"));
            uint256 fromSupply = (supply * basisPoints) / 10_000;
            cap = cap == 0 || fromSupply < cap ? fromSupply : cap;
        }
        if (cap == 0) return (true, "");

        uint256 held = _read(ctx.token, abi.encodeWithSignature("subjectBalanceOf(bytes32)", ctx.toSubject));
        if (held + amount > cap) return (false, "concentration limit exceeded");
        return (true, "");
    }

    function _read(address token, bytes memory call) private view returns (uint256) {
        (bool ok, bytes memory data) = token.staticcall(call);
        return ok && data.length >= 32 ? abi.decode(data, (uint256)) : 0;
    }

    function bounds(address) external pure returns (uint256, uint256) {
        return (0, type(uint256).max);
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("MaxBalancePerHolder");
    }
}
