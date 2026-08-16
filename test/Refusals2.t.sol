// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {Treasury} from "../src/Treasury.sol";
import {PolicySet} from "../src/PolicySet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {AllowlistRegistry, EASAdapter, IEAS} from "../src/identity/Adapters.sol";
import {HasValidIdentity, JurisdictionRule, MaxBalancePerHolder, MiCARule} from "../src/rules/RuleLibrary.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {Claim, IIdentityRegistry} from "../src/interfaces/IIdentityRegistry.sol";
import {RuleContext} from "../src/interfaces/IPolicy.sol";
import {ClaimKeys} from "../src/interfaces/Roles.sol";

/// @dev An initialiser for cuts: one function that works, one that reverts
///      with a reason, one that reverts saying nothing.
contract Init {
    event Ran();

    function fine() external {
        emit Ran();
    }

    function noisy() external pure {
        revert("the initialiser objects");
    }

    function mute() external pure {
        revert();
    }
}

contract Spare {
    function anything() external pure returns (uint256) {
        return 1;
    }
}

/// @title Second pass over the dark branches — the cut initialiser and its failures
contract CutRefusalsTest is Test {
    uRWAToken token;
    Init init;
    Spare spare;

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        token = new uRWAToken("Test", "TST", 18, 0, address(this), address(cutFacet), address(this), 0);
        init = new Init();
        spare = new Spare();
    }

    /// @notice An initialiser runs with the cut, and its failures keep their voice
    /// @dev Three shapes: an initialiser that works, one that reverts with a
    ///      reason (the reason must survive), and one that reverts silently —
    ///      which must be named by selector, not swallowed as success.
    function test_theCutInitialiserRunsAndItsFailuresAreNamed() public {
        _cutWith(address(init), abi.encodeCall(Init.fine, ()));
        assertEq(token.facetAddress(Spare.anything.selector), address(spare), "the cut with initialiser did not land");

        vm.expectRevert("the initialiser objects");
        _cutWith(address(init), abi.encodeCall(Init.noisy, ()));

        vm.expectRevert(abi.encodeWithSelector(IErrors.FunctionNotFound.selector, Init.mute.selector));
        _cutWith(address(init), abi.encodeCall(Init.mute, ()));
    }

    /// @notice A cut that was never scheduled cannot be cancelled
    function test_cancellingTheUnscheduledIsRefused() public {
        vm.expectRevert(abi.encodeWithSelector(IErrors.UpgradeNotScheduled.selector, keccak256("never")));
        DiamondCutFacet(address(token)).cancelCut(keccak256("never"));
    }

    function _cutWith(address target, bytes memory data) internal {
        bytes4[] memory sel = new bytes4[](1);
        sel[0] = Spare.anything.selector;
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(address(spare), IDiamond.FacetCutAction.Add, sel);
        DiamondCutFacet(address(token)).diamondCut(cuts, target, data);
    }
}

/// @dev A token for the treasury that answers roles and balances as told, and
///      a coin whose `transfer` lies — returns false with the balance intact.
contract RoleToken {
    mapping(address => uint256) public balanceOf;

    function setBalance(address who, uint256 v) external {
        balanceOf[who] = v;
    }

    function hasRole(bytes32, address) external pure returns (bool) {
        return true;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return true;
    }
}

contract FalseCoin {
    mapping(address => uint256) public balanceOf;

    function setBalance(address who, uint256 v) external {
        balanceOf[who] = v;
    }

    function transfer(address, uint256) external pure returns (bool) {
        return false; // the lie the treasury must treat as failure
    }
}

/// @title The treasury's refusals: over-reservation and the coin that lies
contract TreasuryRefusalsTest is Test {
    Treasury treasury;
    RoleToken token;
    FalseCoin falseCoin;

    function setUp() public {
        treasury = new Treasury();
        token = new RoleToken();
        falseCoin = new FalseCoin();
        // This test is both issuer and registry, so every door answers to it.
        treasury.initialise(address(token), address(this), address(this));
    }

    /// @notice Reserving more than the treasury holds is refused with the gap
    function test_overReservationIsRefused() public {
        token.setBalance(address(treasury), 10e18);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientAvailable.selector, 20e18, 10e18));
        treasury.reserve(20e18, 1);
    }

    /// @notice A token whose transfer returns false is a failed movement, everywhere
    /// @dev Three doors — withdrawERC20, refund, withdrawPayments — and none of
    ///      them may read a false return as money having moved. A treasury that
    ///      believed the lie would emit Withdrawn for value still sitting in it.
    function test_aFalseTransferIsAFailureThroughEveryDoor() public {
        falseCoin.setBalance(address(treasury), 100e18);

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientAvailable.selector, 50e18, 0));
        treasury.withdrawERC20(address(falseCoin), address(this), 50e18);

        treasury.lockPayment(1, address(falseCoin), 30e18);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientAvailable.selector, 30e18, 0));
        treasury.refund(1, address(falseCoin), address(0xA1), 30e18);

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientAvailable.selector, 10e18, 0));
        treasury.withdrawPayments(address(falseCoin), address(this), 10e18);
    }
}

/// @title The policy set's quiet edges
contract PolicySetEdgesTest is Test {
    PolicySet ps;

    function setUp() public {
        ps = new PolicySet(address(this));
    }

    /// @notice Ownership refuses the zero address and every stranger
    function test_ownershipIsGuardedBothWays() public {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        ps.transferOwnership(address(0));

        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotAuthorized.selector, address(0xBAD), bytes32(0)));
        ps.transferOwnership(address(0xBAD));

        ps.transferOwnership(address(0xCAFE));
        assertEq(ps.owner(), address(0xCAFE));
    }

    /// @notice An empty group is skipped, not counted as a refusal
    /// @dev A group whose last rule was removed must not brick every transfer:
    ///      groups AND together, and an empty conjunct is vacuously true.
    function test_anEmptyGroupIsVacuouslyTrue() public {
        ps.addGroup(keccak256("emptied"));
        (bool ok,,) = ps.evaluate(address(1), address(2), 1e18);
        assertTrue(ok, "an empty group refused a transfer");
    }

    /// @notice Repeated adds and absent removes are absorbed, and counts stay true
    /// @dev `ruleCount` is the gas-griefing bound; drift in either direction
    ///      would let an operator exceed the cap or be refused below it.
    function test_compositionBookkeepingSurvivesTheEdges() public {
        ps.addGroup(keccak256("g"));
        ps.addGroup(keccak256("g")); // a repeat, absorbed
        assertEq(ps.groups().length, 1);

        ps.addRule(keccak256("g"), address(0x51));
        ps.removeRule(keccak256("g"), address(0x99)); // never added — a no-op
        assertEq(ps.ruleCount(), 1, "an absent remove changed the count");

        ps.removeGroup(keccak256("ghost")); // never added — a no-op
        assertEq(ps.groups().length, 1);

        ps.removeGroup(keccak256("g")); // takes its rule's count with it
        assertEq(ps.ruleCount(), 0, "removing a group left its rules counted");
        assertEq(ps.groups().length, 0);
    }
}

/// @dev A registry the rule tests steer per subject and key — including into
///      reverting, which every rule must read as refusal.
contract SteerableRegistry is IIdentityRegistry {
    mapping(bytes32 => mapping(bytes32 => bool)) public has;
    mapping(bytes32 => mapping(bytes32 => Claim)) public claims;
    bool public broken;

    function setHas(bytes32 s, bytes32 k, bool v) external {
        has[s][k] = v;
    }

    function setClaim(bytes32 s, bytes32 k, Claim calldata c) external {
        claims[s][k] = c;
    }

    function setBroken(bool v) external {
        broken = v;
    }

    function subjectOf(address w) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(w));
    }

    function isActive(address) external pure returns (bool) {
        return true;
    }

    function claim(bytes32 s, bytes32 k) external view returns (Claim memory) {
        require(!broken, "registry down");
        return claims[s][k];
    }

    function hasValidClaim(bytes32 s, bytes32 k) external view returns (bool) {
        require(!broken, "registry down");
        return has[s][k];
    }
}

/// @dev Answers `totalSupply` and `subjectBalanceOf` for the concentration rule.
contract SupplyView {
    uint256 public supply;
    mapping(bytes32 => uint256) public held;

    function set(uint256 supply_, bytes32 subject, uint256 held_) external {
        supply = supply_;
        held[subject] = held_;
    }

    function totalSupply() external view returns (uint256) {
        return supply;
    }

    function subjectBalanceOf(bytes32 s) external view returns (uint256) {
        return held[s];
    }
}

/// @title The rules' own dark corners
contract RuleEdgesTest is Test {
    SteerableRegistry registry;
    bytes32 FROM = keccak256("from-subject");
    bytes32 TO = keccak256("to-subject");

    function setUp() public {
        registry = new SteerableRegistry();
    }

    function _ctx(address token) internal view returns (RuleContext memory ctx) {
        ctx.token = token;
        ctx.fromSubject = FROM;
        ctx.toSubject = TO;
    }

    /// @notice A registry that reverts refuses — and names the sender first
    /// @dev The `try/catch` in `ClaimReader`, both branches of `HasValidIdentity`:
    ///      the sender's missing identity is reported before the recipient's.
    function test_identityRefusesBrokenRegistriesAndNamesTheParty() public {
        HasValidIdentity rule = new HasValidIdentity(address(registry));

        registry.setBroken(true);
        (bool ok, string memory why) = rule.check(address(1), address(2), 1, _ctx(address(0)));
        assertFalse(ok, "a broken registry admitted a transfer");
        assertEq(why, "sender has no valid identity");
        registry.setBroken(false);

        registry.setHas(FROM, ClaimKeys.IDENTITY_VALID, true);
        (ok, why) = rule.check(address(1), address(2), 1, _ctx(address(0)));
        assertEq(why, "recipient has no valid identity");

        registry.setHas(TO, ClaimKeys.IDENTITY_VALID, true);
        (ok,) = rule.check(address(1), address(2), 1, _ctx(address(0)));
        assertTrue(ok);
    }

    /// @notice A valid claim with an empty value is still an unknown jurisdiction
    /// @dev `hasValidClaim` true but `valueHash` zero — a misconfigured
    ///      attestation must fail closed, not pass an allow-list check on the
    ///      empty hash.
    function test_anEmptyJurisdictionValueFailsClosed() public {
        bytes32[] memory none = new bytes32[](0);
        JurisdictionRule rule = new JurisdictionRule(address(registry), true, none);

        registry.setHas(TO, ClaimKeys.JURISDICTION_COUNTRY, true); // valid, but value empty
        (bool ok, string memory why) = rule.check(address(1), address(2), 1, _ctx(address(0)));
        assertFalse(ok);
        assertEq(why, "jurisdiction unknown");
    }

    /// @notice A stale MiCA attestation refuses; a fresh one passes
    function test_micaFreshnessBinds() public {
        bytes32 ISSUER = keccak256("issuer");
        MiCARule rule =
            new MiCARule(address(registry), ISSUER, keccak256("mica.reserve.attested"), 1 days, "no reserve");

        vm.warp(30 days);
        registry.setHas(ISSUER, keccak256("mica.reserve.attested"), true);
        Claim memory c;
        c.issuedAt = uint64(block.timestamp - 2 days); // outside the window
        registry.setClaim(ISSUER, keccak256("mica.reserve.attested"), c);

        (bool ok, string memory why) = rule.check(address(1), address(2), 1, _ctx(address(0)));
        assertFalse(ok);
        assertEq(why, "attestation is stale");

        c.issuedAt = uint64(block.timestamp - 2 hours); // inside it
        registry.setClaim(ISSUER, keccak256("mica.reserve.attested"), c);
        (ok,) = rule.check(address(1), address(2), 1, _ctx(address(0)));
        assertTrue(ok);
    }

    /// @notice The basis-points cap tracks supply, and the tighter bound wins
    /// @dev Both arms of the concentration rule: a 10% cap on a 1000-token
    ///      supply is 100; a holder at 90 may take 10 and not 11. With both an
    ///      absolute cap and basis points set, the smaller governs.
    function test_concentrationCapComputesFromSupply() public {
        SupplyView token = new SupplyView();
        token.set(1000e18, TO, 90e18);

        MaxBalancePerHolder pct = new MaxBalancePerHolder(0, 1000); // 10%
        (bool ok,) = pct.check(address(1), address(2), 10e18, _ctx(address(token)));
        assertTrue(ok, "exactly at the cap must pass");
        (ok,) = pct.check(address(1), address(2), 11e18, _ctx(address(token)));
        assertFalse(ok, "over the cap must refuse");

        MaxBalancePerHolder both = new MaxBalancePerHolder(50e18, 1000); // 10% but never over 50
        (ok,) = both.check(address(1), address(2), 1e18, _ctx(address(token)));
        assertFalse(ok, "the tighter absolute cap must govern");
    }
}

/// @dev EAS with three attestations: one live, one expired, one revoked — and a
///      switch that makes the whole service revert.
contract SteerableEAS {
    mapping(bytes32 => IEAS.Attestation) public att;
    bool public broken;

    function set(bytes32 uid, uint64 expires, uint64 revoked) external {
        IEAS.Attestation memory a;
        a.uid = uid;
        a.time = uint64(block.timestamp);
        a.expirationTime = expires;
        a.revocationTime = revoked;
        a.attester = address(this);
        a.data = "x";
        att[uid] = a;
    }

    function setBroken(bool v) external {
        broken = v;
    }

    function getAttestation(bytes32 uid) external view returns (IEAS.Attestation memory) {
        require(!broken, "eas down");
        return att[uid];
    }
}

/// @title The adapters' guards and fallbacks
contract AdapterEdgesTest is Test {
    /// @notice Only the admin curates the allowlist
    function test_theAllowlistRefusesStrangers() public {
        AllowlistRegistry reg = new AllowlistRegistry(address(this));
        vm.prank(address(0xBAD));
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotAuthorized.selector, address(0xBAD), bytes32(0)));
        reg.allow(address(0xBAD));
    }

    /// @notice Absent, expired, revoked and unreachable are all invalid — quietly
    /// @dev The four ways an EAS attestation stops counting, none of which may
    ///      revert into the pipeline.
    function test_easInvalidityIsFourfoldAndSilent() public {
        SteerableEAS eas = new SteerableEAS();
        EASAdapter adapter = new EASAdapter(address(eas), address(this));
        bytes32 SUBJECT = keccak256("s");
        bytes32 KEY = keccak256("k");

        vm.warp(30 days);
        assertFalse(adapter.hasValidClaim(SUBJECT, KEY), "an absent attestation counted");
        assertEq(adapter.claim(SUBJECT, KEY).issuer, address(0), "an absent claim carried an issuer");

        adapter.record(SUBJECT, KEY, keccak256("expired"));
        SteerableEAS(eas).set(keccak256("expired"), uint64(block.timestamp - 1), 0);
        assertFalse(adapter.hasValidClaim(SUBJECT, KEY), "an expired attestation counted");

        adapter.record(SUBJECT, KEY, keccak256("revoked"));
        SteerableEAS(eas).set(keccak256("revoked"), 0, uint64(block.timestamp - 1));
        assertFalse(adapter.hasValidClaim(SUBJECT, KEY), "a revoked attestation counted");
        assertTrue(adapter.claim(SUBJECT, KEY).revoked, "the claim must say it was revoked");

        adapter.record(SUBJECT, KEY, keccak256("live"));
        SteerableEAS(eas).set(keccak256("live"), 0, 0);
        assertTrue(adapter.hasValidClaim(SUBJECT, KEY));

        eas.setBroken(true);
        assertFalse(adapter.hasValidClaim(SUBJECT, KEY), "an unreachable EAS admitted a claim");
    }
}
