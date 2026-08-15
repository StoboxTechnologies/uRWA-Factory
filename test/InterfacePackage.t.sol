// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {IERC7943} from "../src/interfaces/IERC7943.sol";
import {Slots} from "../src/storage/Slots.sol";
import {Roles, ClaimKeys} from "../src/interfaces/Roles.sol";

/// @title Phase 0 — what the interface package must already be true about
/// @notice No contracts exist yet, so these test the declarations themselves.
///         They are the first two of the `L3` checks in
///         docs/31-verification.md, and they run from today rather than
///         arriving with the implementation.
contract InterfacePackageTest is Test {
    /// @notice The interface id we claim everywhere is the one our declaration
    ///         actually produces.
    /// @dev This is the load-bearing number in the whole project: it is what
    ///      `supportsInterface` answers, what an integrator checks, and what
    ///      every conformance claim rests on. Deriving it from the interface
    ///      rather than pasting a constant means a signature edited by one
    ///      character fails here instead of on a deployed token.
    function test_erc7943InterfaceIdIsAsDocumented() public pure {
        bytes4 computed = IERC7943.canSend.selector ^ IERC7943.canReceive.selector ^ IERC7943.canTransfer.selector
            ^ IERC7943.getFrozenTokens.selector ^ IERC7943.setFrozenTokens.selector ^ IERC7943.forcedTransfer.selector;

        assertEq(computed, bytes4(0x3edbb4c4), "ERC-7943 interface id no longer matches the documented value");
    }

    /// @notice Slot constants are the hash of the documented string
    /// @dev `L3.4`. Changing a slot string orphans live storage, so the test
    ///      asserts against the string rather than a hard-coded hash — a
    ///      hard-coded hash would happily agree with a typo.
    function test_storageSlotsDeriveFromTheDocumentedStrings() public pure {
        assertEq(Slots.CORE, keccak256("urwa.storage.core.v1"));
        assertEq(Slots.COMPLIANCE, keccak256("urwa.storage.compliance.v1"));
        assertEq(Slots.FREEZE, keccak256("urwa.storage.freeze.v1"));
        assertEq(Slots.LOCKUP, keccak256("urwa.storage.lockup.v1"));
        assertEq(Slots.MONETARY, keccak256("urwa.storage.monetary.v1"));
        assertEq(Slots.ROLES, keccak256("urwa.storage.roles.v1"));
        assertEq(Slots.UPGRADE, keccak256("urwa.storage.upgrade.v1"));
    }

    /// @notice No two namespaced slots collide
    /// @dev The property the whole diamond depends on. Cheap to assert, and
    ///      catastrophic to discover late.
    function test_storageSlotsAreDistinct() public pure {
        bytes32[7] memory slots =
            [Slots.CORE, Slots.COMPLIANCE, Slots.FREEZE, Slots.LOCKUP, Slots.MONETARY, Slots.ROLES, Slots.UPGRADE];
        for (uint256 i = 0; i < slots.length; i++) {
            for (uint256 j = i + 1; j < slots.length; j++) {
                assertTrue(slots[i] != slots[j], "two storage slots collide");
            }
        }
    }

    /// @notice Role identifiers are distinct
    /// @dev Two roles hashing alike would silently merge two sets of powers —
    ///      exactly the separation the design exists to maintain.
    function test_roleIdentifiersAreDistinct() public pure {
        bytes32[4] memory roles =
            [Roles.UPGRADE_ADMIN, Roles.SUPPLY_OPERATOR, Roles.COMPLIANCE_OFFICER, Roles.ISSUER_ADMIN];
        for (uint256 i = 0; i < roles.length; i++) {
            for (uint256 j = i + 1; j < roles.length; j++) {
                assertTrue(roles[i] != roles[j], "two token roles collide");
            }
        }
    }

    /// @notice EU professional and US accredited are separate keys
    /// @dev The schema decision that would be most expensive to reverse: one
    ///      combined `accredited` flag makes a Reg S tranche and an EU tranche
    ///      impossible to run off a single identity set.
    function test_euAndUsEligibilityAreSeparateKeys() public pure {
        assertTrue(ClaimKeys.EU_PROFESSIONAL != ClaimKeys.US_ACCREDITED);
        assertEq(ClaimKeys.US_ACCREDITED, keccak256("us.regd.accredited"));
        assertEq(ClaimKeys.EU_PROFESSIONAL, keccak256("eu.mifid2.professional"));
    }

    /// @notice The four MiCA keys exist and are distinct
    function test_micaKeysAreDeclared() public pure {
        assertEq(ClaimKeys.MICA_ISSUER_AUTHORISED, keccak256("mica.issuer.authorised"));
        assertEq(ClaimKeys.MICA_TOKEN_CLASS, keccak256("mica.token.class"));
        assertEq(ClaimKeys.MICA_WHITEPAPER_NOTIFIED, keccak256("mica.whitepaper.notified"));
        assertEq(ClaimKeys.MICA_RESERVE_ATTESTED, keccak256("mica.reserve.attested"));
    }
}
