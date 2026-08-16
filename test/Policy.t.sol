// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {PolicySet} from "../src/PolicySet.sol";
import {IRule, RuleContext} from "../src/interfaces/IPolicy.sol";
import {Claim, IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {ClaimKeys} from "../src/interfaces/Roles.sol";
import {
    HasValidIdentity,
    JurisdictionRule,
    MaxHolders,
    MiCARule,
    RequiresClaim,
    TransferWindow
} from "../src/rules/RuleLibrary.sol";

/// @dev A registry whose claims the test controls exactly.
contract Claims is IIdentityRegistry {
    mapping(bytes32 => mapping(bytes32 => Claim)) public store;

    function set(bytes32 subject, bytes32 key, bytes32 value, uint64 issuedAt) external {
        store[subject][key] = Claim(value, 0, issuedAt, 0, address(this), false);
    }

    function subjectOf(address w) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(w));
    }

    function isActive(address) external pure returns (bool) {
        return true;
    }

    function claim(bytes32 s, bytes32 k) external view returns (Claim memory) {
        return store[s][k];
    }

    function hasValidClaim(bytes32 s, bytes32 k) external view returns (bool) {
        return store[s][k].issuer != address(0);
    }
}

/// @dev A rule that reverts. Third-party code inside a transfer.
contract RevertingRule is IRule {
    function check(address, address, uint256, RuleContext calldata) external pure returns (bool, string memory) {
        revert("I am broken");
    }

    function bounds(address) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("Reverting");
    }
}

/// @dev A rule that never returns within its ceiling.
contract GasEatingRule is IRule {
    function check(address, address, uint256, RuleContext calldata) external view returns (bool, string memory) {
        uint256 x;
        while (gasleft() > 100) {
            x = uint256(keccak256(abi.encode(x)));
        }
        return (true, "");
    }

    function bounds(address) external pure returns (uint256, uint256) {
        return (0, 0);
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("GasEating");
    }
}

/// @dev Stands in for the token: answers the two views a policy set reads.
contract FakeToken {
    PolicySet public policy;
    uint256 public subjectHolderCount;
    mapping(address => uint256) public balanceOf;

    function setPolicy(PolicySet p) external {
        policy = p;
    }

    function setHolders(uint256 n) external {
        subjectHolderCount = n;
    }

    function setBalance(address a, uint256 v) external {
        balanceOf[a] = v;
    }

    function subjectOf(address w) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(w));
    }

    function ask(address from, address to, uint256 amount)
        external
        view
        returns (bool ok, address rule, string memory reason)
    {
        return policy.evaluate(from, to, amount);
    }
}

contract PolicyTest is Test {
    Claims claims;
    PolicySet policy;
    FakeToken token;

    address alice = address(0xA1);
    address bob = address(0xB1);

    bytes32 constant IDENTITY = keccak256("identity");
    bytes32 constant ELIGIBILITY = keccak256("eligibility");
    bytes32 constant LIMITS = keccak256("limits");

    bytes32 constant US = keccak256("US");
    bytes32 constant EE = keccak256("EE");

    function setUp() public {
        claims = new Claims();
        policy = new PolicySet(address(this));
        token = new FakeToken();
        token.setPolicy(policy);

        claims.set(_s(alice), ClaimKeys.IDENTITY_VALID, bytes32("ok"), uint64(block.timestamp));
        claims.set(_s(bob), ClaimKeys.IDENTITY_VALID, bytes32("ok"), uint64(block.timestamp));
    }

    // ── composition ─────────────────────────────────────────────────────────

    /// @notice Groups AND, rules within a group OR
    /// @dev The canonical case: professional in the EU **or** accredited in the
    ///      US. One token, two eligible populations, from a single identity set.
    function test_groupsAndRulesOr() public {
        policy.addGroup(ELIGIBILITY);
        policy.addRule(
            ELIGIBILITY, address(new RequiresClaim(address(claims), ClaimKeys.US_ACCREDITED, "not accredited", 0, 0))
        );
        policy.addRule(
            ELIGIBILITY,
            address(new RequiresClaim(address(claims), ClaimKeys.EU_PROFESSIONAL, "not professional", 0, 0))
        );

        (bool ok,,) = token.ask(alice, bob, 1e18);
        assertFalse(ok, "neither route satisfied and it passed");

        claims.set(_s(bob), ClaimKeys.EU_PROFESSIONAL, bytes32("ok"), uint64(block.timestamp));
        (ok,,) = token.ask(alice, bob, 1e18);
        assertTrue(ok, "the EU route did not satisfy the group");
    }

    /// @notice A second group must also pass
    function test_everyGroupMustPass() public {
        policy.addGroup(IDENTITY);
        policy.addRule(IDENTITY, address(new HasValidIdentity(address(claims))));
        policy.addGroup(LIMITS);
        policy.addRule(LIMITS, address(new MaxHolders(2)));

        token.setHolders(2);
        (bool ok,, string memory reason) = token.ask(alice, bob, 1e18);
        assertFalse(ok);
        assertEq(reason, "holder limit reached");
    }

    // ── the ceiling, and what failure means ─────────────────────────────────

    /// @notice A rule that reverts counts as a refusal
    /// @dev Third-party code runs inside a transfer. The only safe reading of
    ///      its failure is refusal — a broken rule must never open the gate.
    function test_aRevertingRuleRefuses() public {
        policy.addGroup(IDENTITY);
        policy.addRule(IDENTITY, address(new RevertingRule()));

        (bool ok, address failing, string memory reason) = token.ask(alice, bob, 1e18);
        assertFalse(ok, "a reverting rule let the transfer through");
        assertTrue(failing != address(0));
        assertEq(reason, "rule reverted or exceeded its gas ceiling");
    }

    /// @notice So does one that exhausts its ceiling
    /// @dev And the whole call still returns rather than running out of gas —
    ///      which is what makes `canTransfer` safe to call on a token whose
    ///      rules a stranger configured.
    function test_aGasEatingRuleRefusesAndTheCallReturns() public {
        policy.addGroup(IDENTITY);
        policy.addRule(IDENTITY, address(new GasEatingRule()));

        (bool ok,, string memory reason) = token.ask(alice, bob, 1e18);
        assertFalse(ok, "a gas-eating rule let the transfer through");
        assertEq(reason, "rule reverted or exceeded its gas ceiling");
    }

    /// @notice One broken rule does not brick the token
    /// @dev Another rule in the same group can still satisfy it, which is why
    ///      groups are OR rather than AND.
    function test_aBrokenRuleDoesNotBrickTheGroup() public {
        policy.addGroup(IDENTITY);
        policy.addRule(IDENTITY, address(new RevertingRule()));
        policy.addRule(IDENTITY, address(new HasValidIdentity(address(claims))));

        (bool ok,,) = token.ask(alice, bob, 1e18);
        assertTrue(ok, "a working rule could not rescue the group");
    }

    /// @notice Rules are bounded
    function test_rulesAreBounded() public {
        policy.addGroup(IDENTITY);
        for (uint256 i = 0; i < 24; i++) {
            policy.addRule(IDENTITY, address(new HasValidIdentity(address(claims))));
        }
        // Deploy first: `expectRevert` applies to the next call, and a `new`
        // in the argument list is that call.
        address oneTooMany = address(new HasValidIdentity(address(claims)));
        vm.expectRevert();
        policy.addRule(IDENTITY, oneTooMany);
    }

    // ── individual rules ────────────────────────────────────────────────────

    /// @notice Jurisdictions are compared as hashes
    /// @dev No plaintext country code in calldata, where an observer would read
    ///      a holder's residence out of the mempool.
    function test_jurisdictionDeny() public {
        bytes32[] memory denied = new bytes32[](1);
        denied[0] = US;
        policy.addGroup(IDENTITY);
        policy.addRule(IDENTITY, address(new JurisdictionRule(address(claims), true, denied)));

        claims.set(_s(bob), ClaimKeys.JURISDICTION_COUNTRY, US, uint64(block.timestamp));
        (bool ok,, string memory reason) = token.ask(alice, bob, 1e18);
        assertFalse(ok);
        assertEq(reason, "jurisdiction excluded");

        claims.set(_s(bob), ClaimKeys.JURISDICTION_COUNTRY, EE, uint64(block.timestamp));
        (ok,,) = token.ask(alice, bob, 1e18);
        assertTrue(ok);
    }

    /// @notice An unknown jurisdiction refuses rather than passes
    function test_unknownJurisdictionRefuses() public {
        bytes32[] memory denied = new bytes32[](1);
        denied[0] = US;
        policy.addGroup(IDENTITY);
        policy.addRule(IDENTITY, address(new JurisdictionRule(address(claims), true, denied)));

        (bool ok,, string memory reason) = token.ask(alice, bob, 1e18);
        assertFalse(ok, "an unknown jurisdiction passed a deny list");
        assertEq(reason, "jurisdiction unknown");
    }

    /// @notice An existing holder does not consume a place in the register
    function test_maxHoldersIgnoresExistingHolders() public {
        policy.addGroup(LIMITS);
        policy.addRule(LIMITS, address(new MaxHolders(2)));
        token.setHolders(2);

        (bool ok,,) = token.ask(alice, bob, 1e18);
        assertFalse(ok, "a new holder was admitted past the cap");

        token.setBalance(bob, 1);
        (ok,,) = token.ask(alice, bob, 1e18);
        assertTrue(ok, "an existing holder was refused by a full register");
    }

    /// @notice Screening goes stale on a clock the rule owns
    function test_sanctionsFreshnessIsEnforcedByTheRule() public {
        policy.addGroup(IDENTITY);
        policy.addRule(
            IDENTITY,
            address(new RequiresClaim(address(claims), ClaimKeys.AML_SANCTIONS_CLEAR, "not screened", 0, 30 days))
        );
        claims.set(_s(bob), ClaimKeys.AML_SANCTIONS_CLEAR, bytes32("clear"), uint64(block.timestamp));

        (bool ok,,) = token.ask(alice, bob, 1e18);
        assertTrue(ok);

        vm.warp(block.timestamp + 31 days);
        string memory reason;
        (ok,, reason) = token.ask(alice, bob, 1e18);
        assertFalse(ok, "stale screening still passed");
        assertEq(reason, "screening is stale");
    }

    /// @notice A MiCA rule stops the whole token, not one holder
    /// @dev It reads the issuer's subject, so the answer is identical for
    ///      everyone. Intended for a backed instrument, and surprising to an
    ///      issuer who has not been told.
    function test_aStaleReserveAttestationStopsEveryone() public {
        bytes32 issuerSubject = keccak256("the issuer");
        policy.addGroup(IDENTITY);
        policy.addRule(
            IDENTITY,
            address(
                new MiCARule(
                    address(claims), issuerSubject, ClaimKeys.MICA_RESERVE_ATTESTED, 30 days, "reserve not attested"
                )
            )
        );
        claims.set(issuerSubject, ClaimKeys.MICA_RESERVE_ATTESTED, bytes32("ok"), uint64(block.timestamp));

        (bool ok,,) = token.ask(alice, bob, 1e18);
        assertTrue(ok);

        vm.warp(block.timestamp + 31 days);
        (ok,,) = token.ask(alice, bob, 1e18);
        assertFalse(ok, "a stale reserve attestation did not stop the token");

        // And it stops a completely different pair too.
        (ok,,) = token.ask(bob, alice, 1e18);
        assertFalse(ok, "it stopped one direction only");
    }

    /// @notice Blackout windows close and reopen
    function test_transferWindow() public {
        uint64 closes = uint64(block.timestamp + 1 days);
        uint64 reopens = uint64(block.timestamp + 3 days);
        policy.addGroup(LIMITS);
        policy.addRule(LIMITS, address(new TransferWindow(closes, reopens)));

        (bool ok,,) = token.ask(alice, bob, 1e18);
        assertTrue(ok, "closed before it should");

        vm.warp(closes + 1);
        string memory reason;
        (ok,, reason) = token.ask(alice, bob, 1e18);
        assertFalse(ok);
        assertEq(reason, "transfers closed during this window");

        vm.warp(reopens + 1);
        (ok,,) = token.ask(alice, bob, 1e18);
        assertTrue(ok, "never reopened");
    }

    /// @notice An empty policy set permits everything
    /// @dev Which is why the empty set is a deliberate configuration and never
    ///      a default.
    function test_anEmptyPolicySetPermits() public view {
        (bool ok,,) = token.ask(alice, bob, 1e18);
        assertTrue(ok);
    }

    function _s(address a) private pure returns (bytes32) {
        return keccak256(abi.encodePacked(a));
    }
}
