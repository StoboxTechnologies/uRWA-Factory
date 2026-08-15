// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Slots} from "./Slots.sol";

/// @title Storage layout for the uRWA token diamond
/// @notice One struct per facet, each at its own namespaced slot.
/// @dev **Append only.** A field inserted in the middle of a struct shifts
///      every field after it, and in a diamond those fields hold live balances.
///      New state goes at the end, or in a `.v2` slot. `L3.7` diffs this file
///      against the previous release and fails on anything but growth.
library Layout {
    // ── ledger plane · never replaceable ────────────────────────────────────

    struct CoreStorage {
        mapping(address => uint256) balances;
        mapping(address => mapping(address => uint256)) allowances;
        mapping(address => uint256) nonces; // ERC-2612
        uint256 totalSupply;
        uint256 maxSupply; // 0 = unlimited
        bool capLocked; // set at deployment, irreversible
        string name;
        string symbol;
        uint8 decimals;
    }

    // ── policy plane · replaceable ──────────────────────────────────────────

    struct ComplianceStorage {
        address policySet;
        address identityRegistry;
        mapping(address => bool) trusted;
        mapping(address => string) trustReason;
        address[] trustList;
        bool paused; // global; halts everything, trusted included
        mapping(address => bool) addressPaused; // one address, both directions
        mapping(address => string) addressPauseReason;
        uint256 holderCount; // addresses with a balance
        mapping(bytes32 => uint256) subjectBalance; // subject => total across wallets
        mapping(bytes32 => bool) subjectIsHolder;
        uint256 subjectHolderCount; // the number holder caps must use
    }

    struct FreezeStorage {
        mapping(address => uint256) adminFrozen; // indefinite, set by compliance
    }

    struct Lockup {
        uint256 amount;
        uint64 unlockAt; // unix seconds; expiry needs no transaction
        string note; // reason, for the audit trail
    }

    struct LockupStorage {
        mapping(address => Lockup[]) lockups;
    }

    struct MonetaryStorage {
        address treasury;
        address offeringRegistry;
        uint256 totalIssued; // monotonic; never decreases, even on redemption
    }

    struct RolesStorage {
        mapping(bytes32 => mapping(address => bool)) roles;
        mapping(bytes32 => address[]) members; // enumerable
    }

    struct UpgradeStorage {
        uint64 delay; // 0 = immediate
        mapping(bytes32 => uint64) scheduledAt; // cut hash => earliest execution
    }

    // ── accessors ───────────────────────────────────────────────────────────

    function core() internal pure returns (CoreStorage storage s) {
        bytes32 slot = Slots.CORE;
        assembly {
            s.slot := slot
        }
    }

    function compliance() internal pure returns (ComplianceStorage storage s) {
        bytes32 slot = Slots.COMPLIANCE;
        assembly {
            s.slot := slot
        }
    }

    function freeze() internal pure returns (FreezeStorage storage s) {
        bytes32 slot = Slots.FREEZE;
        assembly {
            s.slot := slot
        }
    }

    function lockup() internal pure returns (LockupStorage storage s) {
        bytes32 slot = Slots.LOCKUP;
        assembly {
            s.slot := slot
        }
    }

    function monetary() internal pure returns (MonetaryStorage storage s) {
        bytes32 slot = Slots.MONETARY;
        assembly {
            s.slot := slot
        }
    }

    function roles() internal pure returns (RolesStorage storage s) {
        bytes32 slot = Slots.ROLES;
        assembly {
            s.slot := slot
        }
    }

    function upgrade() internal pure returns (UpgradeStorage storage s) {
        bytes32 slot = Slots.UPGRADE;
        assembly {
            s.slot := slot
        }
    }
}
