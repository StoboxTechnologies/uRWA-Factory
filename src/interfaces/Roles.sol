// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Role identifiers
/// @notice Four roles on the token, separated so that no one of them can act
///         alone. The separation matters most in the failure case: a
///         compromised upgrade admin can stop the token but cannot move
///         anyone's balance — not by policy, but because the ERC-20 selectors
///         are not replaceable.
library Roles {
    /// @notice Changes the code: facets, policy set, identity registry
    bytes32 internal constant UPGRADE_ADMIN = keccak256("urwa.role.upgrade_admin");

    /// @notice Moves supply: issue, redeem, distribute
    bytes32 internal constant SUPPLY_OPERATOR = keccak256("urwa.role.supply_operator");

    /// @notice Restricts holders: freeze, lockup, pause, forced operations
    bytes32 internal constant COMPLIANCE_OFFICER = keccak256("urwa.role.compliance_officer");

    /// @notice Configures: trust list, metadata, offering setup
    bytes32 internal constant ISSUER_ADMIN = keccak256("urwa.role.issuer_admin");

    // ── chain-level roles, on shared contracts ──────────────────────────────

    bytes32 internal constant FACTORY_ADMIN = keccak256("urwa.role.factory_admin");
    bytes32 internal constant REGISTRY_ADMIN = keccak256("urwa.role.registry_admin");
    bytes32 internal constant OFFERING_OPERATOR = keccak256("urwa.role.offering_operator");
    bytes32 internal constant ATTESTOR = keccak256("urwa.role.attestor");
    bytes32 internal constant PASSPORT_ISSUER = keccak256("urwa.role.passport_issuer");
}

/// @title Claim keys
/// @notice `keccak256` of a dotted namespace. Anyone may define their own —
///         `ch.finma.qualified` needs no permission and no core upgrade. That
///         is the extensibility guarantee, and the reason the schema is a
///         key-value registry rather than a fixed struct.
library ClaimKeys {
    bytes32 internal constant IDENTITY_VALID = keccak256("urwa.identity.valid");
    bytes32 internal constant JURISDICTION_COUNTRY = keccak256("urwa.jurisdiction.country");
    bytes32 internal constant INVESTOR_TYPE = keccak256("urwa.investor.type");

    bytes32 internal constant US_ACCREDITED = keccak256("us.regd.accredited");

    /// @dev EU professional and US accredited are different tests with
    ///      different thresholds. Collapsing them into one boolean would make
    ///      it impossible to run a Reg S tranche and an EU tranche off one
    ///      identity set.
    bytes32 internal constant EU_PROFESSIONAL = keccak256("eu.mifid2.professional");
    bytes32 internal constant EU_QUALIFIED = keccak256("eu.prospectus.qualified");

    bytes32 internal constant AML_SANCTIONS_CLEAR = keccak256("aml.sanctions.clear");
    bytes32 internal constant ISO17442_LEI = keccak256("iso17442.lei");

    // ── MiCA: facts about the issuer and the instrument, not the holder ─────

    bytes32 internal constant MICA_ISSUER_AUTHORISED = keccak256("mica.issuer.authorised");
    bytes32 internal constant MICA_TOKEN_CLASS = keccak256("mica.token.class");
    bytes32 internal constant MICA_WHITEPAPER_NOTIFIED = keccak256("mica.whitepaper.notified");
    bytes32 internal constant MICA_RESERVE_ATTESTED = keccak256("mica.reserve.attested");
}
