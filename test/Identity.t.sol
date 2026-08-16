// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AllowlistRegistry, EASAdapter, IEAS, StoboxDIDAdapter} from "../src/identity/Adapters.sol";
import {IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {ClaimKeys} from "../src/interfaces/Roles.sol";

/// @dev StoboxDID as deployed: **every getter reverts for an unknown wallet.**
///      This is not a hypothetical failure mode; it is the contract on Arbitrum
///      One today, and the reason `ID-04` has an exit criterion.
contract StoboxDIDMock {
    struct Record {
        string uDID;
        uint256 validTo;
        bool blocked;
        bool deactivated;
        bool exists;
    }

    mapping(address => Record) public records;
    mapping(address => mapping(string => bytes)) public attributes;
    mapping(address => mapping(string => uint256)) public attributeValidTo;

    function register(address wallet, string calldata uDID, uint256 validTo) external {
        records[wallet] = Record(uDID, validTo, false, false, true);
    }

    function block_(address wallet) external {
        records[wallet].blocked = true;
    }

    function deactivate(address wallet) external {
        records[wallet].deactivated = true;
    }

    function setAttribute(address wallet, string calldata name, bytes calldata value, uint256 validTo) external {
        attributes[wallet][name] = value;
        attributeValidTo[wallet][name] = validTo;
    }

    function getLinker(address wallet) external view returns (string memory, uint256, uint256, bool) {
        Record memory r = records[wallet];
        require(r.exists, "AddressDoesNotHaveLinker");
        return (r.uDID, 0, 0, r.deactivated);
    }

    function getUserDID(address wallet) external view returns (string memory, uint256, uint256, bool, address) {
        Record memory r = records[wallet];
        require(r.exists, "AddressDoesNotLinkedToDID");
        return (r.uDID, r.validTo, 0, r.blocked, address(this));
    }

    function getAttribute(address wallet, string memory name)
        external
        view
        returns (bytes memory, string memory, uint256, uint256, uint256, address)
    {
        require(records[wallet].exists, "AddressDoesNotLinkedToDID");
        return (attributes[wallet][name], "bytes", 0, block.timestamp, attributeValidTo[wallet][name], address(this));
    }
}

contract EASMock is IEAS {
    mapping(bytes32 => Attestation) public store;

    function set(bytes32 uid, uint64 expiry, uint64 revoked) external {
        store[uid] =
            Attestation(uid, 0, uint64(block.timestamp), expiry, revoked, 0, address(0), address(this), true, "x");
    }

    function getAttestation(bytes32 uid) external view returns (Attestation memory) {
        return store[uid];
    }
}

/// @title The three tiers, and the guarantee all of them must keep
contract IdentityTest is Test {
    address alice = address(0xA1);
    address unknown = address(0xDEAD);

    // ── tier 0 ──────────────────────────────────────────────────────────────

    /// @notice A fork runs on this alone
    function test_allowlistIsSelfContained() public {
        AllowlistRegistry r = new AllowlistRegistry(address(this));
        assertFalse(r.isActive(alice));
        r.allow(alice);
        assertTrue(r.isActive(alice));
        r.deny(alice);
        assertFalse(r.isActive(alice));
    }

    /// @notice Even tier 0 can bind wallets to one person
    /// @dev Without it a holder cap on a tier-0 token is defeated by one
    ///      investor with two wallets — the cap would count addresses again.
    function test_allowlistCanBindWalletsToOneSubject() public {
        AllowlistRegistry r = new AllowlistRegistry(address(this));
        bytes32 person = keccak256("one person");
        r.link(alice, person);
        r.link(address(0xA2), person);

        assertEq(r.subjectOf(alice), person);
        assertEq(r.subjectOf(address(0xA2)), person);
        assertEq(r.subjectOf(unknown), keccak256(abi.encodePacked(unknown)), "unregistered wallets need a subject too");
    }

    // ── tier 1 ──────────────────────────────────────────────────────────────

    /// @notice Absent, expired and revoked are three distinguishable states
    /// @dev And all three answer false without reverting, which is what the
    ///      standard requires of every view behind them.
    function test_easDistinguishesAbsentExpiredAndRevoked() public {
        // Foundry starts at timestamp 1, and `expirationTime == 0` means "no
        // expiry" — so an expired attestation needs a clock to be behind.
        vm.warp(1_000_000);

        EASMock eas = new EASMock();
        EASAdapter a = new EASAdapter(address(eas), address(this));
        bytes32 subject = keccak256("s");
        bytes32 key = ClaimKeys.US_ACCREDITED;

        assertFalse(a.hasValidClaim(subject, key), "absent should be false");

        eas.set(bytes32("live"), 0, 0);
        a.record(subject, key, bytes32("live"));
        assertTrue(a.hasValidClaim(subject, key));

        eas.set(bytes32("expired"), uint64(block.timestamp - 1), 0);
        a.record(subject, key, bytes32("expired"));
        assertFalse(a.hasValidClaim(subject, key), "expired should be false");

        eas.set(bytes32("revoked"), 0, uint64(block.timestamp));
        a.record(subject, key, bytes32("revoked"));
        assertFalse(a.hasValidClaim(subject, key), "revoked should be false");
    }

    // ── tier 2 · the exit criterion ─────────────────────────────────────────

    /// @notice **No view reverts, for any address**
    /// @dev `ID-04`'s definition of done. The deployed registry reverts for
    ///      unknown, and an integrator checking a new counterparty is the most
    ///      common call the token will ever receive.
    function test_noViewRevertsForUnknownZeroOrContractAddresses() public {
        StoboxDIDMock did = new StoboxDIDMock();
        StoboxDIDAdapter a = new StoboxDIDAdapter(address(did), address(this));

        address[3] memory hostile = [unknown, address(0), address(did)];
        for (uint256 i = 0; i < hostile.length; i++) {
            a.subjectOf(hostile[i]);
            a.isActive(hostile[i]);
            a.claimForWallet(hostile[i], ClaimKeys.US_ACCREDITED);
            a.hasValidClaimForWallet(hostile[i], ClaimKeys.US_ACCREDITED);
        }
    }

    function testFuzz_noViewRevertsForAnyAddress(address wallet) public {
        StoboxDIDMock did = new StoboxDIDMock();
        StoboxDIDAdapter a = new StoboxDIDAdapter(address(did), address(this));
        a.subjectOf(wallet);
        a.isActive(wallet);
        a.hasValidClaimForWallet(wallet, ClaimKeys.EU_PROFESSIONAL);
    }

    /// @notice The subject is the DID string, so it survives a change of chain
    /// @dev `keccak256(bytes(uDID))` — the same person hashes to the same
    ///      identifier wherever the registry is deployed, with no bridge.
    function test_theSubjectIsDerivedFromTheDidString() public {
        StoboxDIDMock did = new StoboxDIDMock();
        StoboxDIDAdapter a = new StoboxDIDAdapter(address(did), address(this));

        did.register(alice, "did:stobox:0001", block.timestamp + 365 days);
        assertEq(a.subjectOf(alice), keccak256(bytes("did:stobox:0001")));

        // A second wallet of the same person resolves to the same subject.
        did.register(address(0xA2), "did:stobox:0001", block.timestamp + 365 days);
        assertEq(a.subjectOf(address(0xA2)), a.subjectOf(alice));
    }

    /// @notice Blocking stops a person; deactivation is not enforcement
    /// @dev Both read false here, but only `blocked` is authoritative — a
    ///      holder can reverse their own deactivation on StoboxDID, so no rule
    ///      may treat it as a compliance signal.
    function test_blockedAndDeactivatedBothReadInactive() public {
        StoboxDIDMock did = new StoboxDIDMock();
        StoboxDIDAdapter a = new StoboxDIDAdapter(address(did), address(this));

        did.register(alice, "did:stobox:0001", block.timestamp + 365 days);
        assertTrue(a.isActive(alice));

        did.deactivate(alice);
        assertFalse(a.isActive(alice), "a deactivated wallet should not transact");

        StoboxDIDMock did2 = new StoboxDIDMock();
        StoboxDIDAdapter b = new StoboxDIDAdapter(address(did2), address(this));
        did2.register(alice, "did:stobox:0002", block.timestamp + 365 days);
        did2.block_(alice);
        assertFalse(b.isActive(alice), "a blocked person should not transact");
    }

    /// @notice An expired DID is inactive
    function test_anExpiredDidIsInactive() public {
        StoboxDIDMock did = new StoboxDIDMock();
        StoboxDIDAdapter a = new StoboxDIDAdapter(address(did), address(this));

        did.register(alice, "did:stobox:0001", block.timestamp + 1 days);
        assertTrue(a.isActive(alice));
        vm.warp(block.timestamp + 2 days);
        assertFalse(a.isActive(alice), "an expired DID still read active");
    }

    /// @notice Attributes are read through a mapping the issuer registers
    /// @dev The adapter never guesses a name. A wrong guess would read empty
    ///      and refuse silently, which is the worst of both outcomes.
    function test_attributeNamesAreRegisteredNotGuessed() public {
        StoboxDIDMock did = new StoboxDIDMock();
        StoboxDIDAdapter a = new StoboxDIDAdapter(address(did), address(this));
        did.register(alice, "did:stobox:0001", block.timestamp + 365 days);
        did.setAttribute(alice, "accredited", bytes("yes"), block.timestamp + 365 days);

        assertFalse(a.hasValidClaimForWallet(alice, ClaimKeys.US_ACCREDITED), "unmapped key should not resolve");

        a.mapKey(ClaimKeys.US_ACCREDITED, "accredited");
        assertTrue(a.hasValidClaimForWallet(alice, ClaimKeys.US_ACCREDITED));
    }

    /// @notice An attribute whose validity has lapsed is revoked, not valid
    function test_anAttributeWithNoValidityIsRevoked() public {
        StoboxDIDMock did = new StoboxDIDMock();
        StoboxDIDAdapter a = new StoboxDIDAdapter(address(did), address(this));
        did.register(alice, "did:stobox:0001", block.timestamp + 365 days);
        a.mapKey(ClaimKeys.US_ACCREDITED, "accredited");

        // StoboxDID deactivates an attribute by setting validTo to zero.
        did.setAttribute(alice, "accredited", bytes("yes"), 0);
        assertFalse(a.hasValidClaimForWallet(alice, ClaimKeys.US_ACCREDITED));
    }

    /// @notice All three tiers satisfy the same interface
    /// @dev The property that makes them interchangeable: a token neither knows
    ///      nor cares which is installed.
    function test_allThreeTiersAreTheSameInterface() public {
        IIdentityRegistry[3] memory tiers = [
            IIdentityRegistry(address(new AllowlistRegistry(address(this)))),
            IIdentityRegistry(address(new EASAdapter(address(new EASMock()), address(this)))),
            IIdentityRegistry(address(new StoboxDIDAdapter(address(new StoboxDIDMock()), address(this))))
        ];
        for (uint256 i = 0; i < tiers.length; i++) {
            tiers[i].subjectOf(unknown);
            tiers[i].isActive(unknown);
            tiers[i].claim(bytes32(0), bytes32(0));
            tiers[i].hasValidClaim(bytes32(0), bytes32(0));
        }
    }
}
