// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Namespaced storage slots
/// @notice Every facet reads its own struct from a fixed slot derived from a
///         string. Two facets can therefore never collide, and a facet added
///         years from now cannot disturb one written today.
/// @dev The strings are load-bearing. Changing one orphans live storage, which
///      is why `L3.4` asserts each constant against the string documented in
///      docs/04-storage.md rather than against a hard-coded hash.
library Slots {
    bytes32 internal constant CORE = keccak256("urwa.storage.core.v1");
    bytes32 internal constant COMPLIANCE = keccak256("urwa.storage.compliance.v1");
    bytes32 internal constant FREEZE = keccak256("urwa.storage.freeze.v1");
    bytes32 internal constant LOCKUP = keccak256("urwa.storage.lockup.v1");
    bytes32 internal constant MONETARY = keccak256("urwa.storage.monetary.v1");
    bytes32 internal constant ROLES = keccak256("urwa.storage.roles.v1");
    bytes32 internal constant UPGRADE = keccak256("urwa.storage.upgrade.v1");
}
