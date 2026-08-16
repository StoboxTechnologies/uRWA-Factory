// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAFactory} from "../src/uRWAFactory.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {Treasury} from "../src/Treasury.sol";
import {PolicySet} from "../src/PolicySet.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {MonetaryFacet} from "../src/facets/MonetaryFacet.sol";
import {RolesFacet} from "../src/facets/RolesFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {HasValidIdentity, RequiresClaim, JurisdictionRule, MaxHolders} from "../src/rules/RuleLibrary.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IIdentityRegistry, Claim} from "../src/interfaces/IIdentityRegistry.sol";
import {ClaimKeys, Roles} from "../src/interfaces/Roles.sol";
import {TokenParams} from "../src/interfaces/IuRWAFactory.sol";

/// @dev A registry the test drives: activity per wallet, claims per subject.
contract Registry is IIdentityRegistry {
    mapping(address => bool) public active;
    mapping(bytes32 => mapping(bytes32 => bool)) public valid;

    function setActive(address w, bool v) external {
        active[w] = v;
    }

    function setClaim(address w, bytes32 key, bool v) external {
        valid[keccak256(abi.encodePacked(w))][key] = v;
    }

    function subjectOf(address w) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(w));
    }

    function isActive(address w) external view returns (bool) {
        return active[w];
    }

    function claim(bytes32 s, bytes32 k) external view returns (Claim memory c) {
        if (valid[s][k]) c.issuer = address(this);
    }

    function hasValidClaim(bytes32 s, bytes32 k) external view returns (bool) {
        return valid[s][k];
    }
}

/// @title `PO-08` — the regime presets, registered and applied
/// @notice A preset is a named composition of rules. Registering one in the
///         factory and choosing it at creation must give the token its own
///         policy set, owned by its compliance officer, that actually enforces
///         the regime — not merely record the choice in an event.
contract PresetTest is Test {
    uRWAFactory factory;
    Registry registry;

    // The shared, stateless rule contracts, deployed once for the chain.
    HasValidIdentity identityRule;
    RequiresClaim accreditedRule;
    RequiresClaim sanctionsRule;
    JurisdictionRule denyUS;
    MaxHolders maxHolders;

    bytes32 constant PACKAGE = keccak256("default.v1");
    bytes32 constant REGD = keccak256("RegD506c");
    bytes32 constant REGS = keccak256("RegS");
    bytes32 constant OPEN = keccak256("Open");

    // Group ids. Same group => OR; distinct groups => AND.
    bytes32 constant G_ID = keccak256("identity");
    bytes32 constant G_ACCRED = keccak256("accredited");
    bytes32 constant G_SANCTIONS = keccak256("sanctions");
    bytes32 constant G_HOLDERS = keccak256("holders");
    bytes32 constant G_JURIS = keccak256("jurisdiction");

    bytes32 constant SANCTIONS_KEY = keccak256("aml.sanctions.clear");

    address issuer = address(0x1551E4);
    address officer = address(0x0FF1CE);
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        DiamondCutFacet cut = new DiamondCutFacet();
        Treasury treasuryImpl = new Treasury();
        factory = new uRWAFactory(address(cut), address(treasuryImpl));
        registry = new Registry();

        factory.registerPackage(PACKAGE, _package());

        identityRule = new HasValidIdentity(address(registry));
        accreditedRule = new RequiresClaim(address(registry), ClaimKeys.US_ACCREDITED, "not accredited", 0, 0);
        sanctionsRule = new RequiresClaim(address(registry), SANCTIONS_KEY, "sanctions not cleared", 0, 0);
        bytes32[] memory us = new bytes32[](1);
        us[0] = keccak256("US");
        denyUS = new JurisdictionRule(address(registry), true, us);
        maxHolders = new MaxHolders(2000);

        _registerPresets();
    }

    // ── the presets are registered and queryable ────────────────────────────

    /// @notice A malformed preset — parallel arrays of unequal length — is refused
    function test_aMalformedPresetIsRefused() public {
        address[] memory rules = new address[](2);
        bytes32[] memory groups = new bytes32[](1);
        vm.expectRevert(abi.encodeWithSelector(IErrors.PresetLengthMismatch.selector, 2, 1));
        factory.registerPreset(keccak256("bad"), rules, groups);
    }

    /// @notice Every registered preset is readable, rule for rule
    function test_theRegisteredPresetsAreQueryable() public view {
        (address[] memory rules, bytes32[] memory groups) = factory.presetOf(REGD);
        assertEq(rules.length, 4, "RegD506c should carry four rules");
        assertEq(rules.length, groups.length, "parallel arrays must match");
        assertEq(rules[0], address(identityRule));
    }

    // ── the preset is applied at creation ───────────────────────────────────

    /// @notice Choosing a preset gives the token its own policy set
    /// @dev Owned by the compliance officer, not the factory and not a shared
    ///      party — so changing one token's compliance touches no other token.
    function test_creatingWithAPresetAttachesAnOwnedPolicySet() public {
        (address token,) = _create(OPEN);

        address ps = ComplianceFacet(token).policySet();
        assertTrue(ps != address(0), "no policy set was attached");
        assertEq(PolicySet(ps).owner(), officer, "the officer does not own the policy set");
    }

    /// @notice An unregistered preset attaches nothing, and says so by leaving it zero
    function test_anUnregisteredPresetAttachesNoPolicySet() public {
        (address token,) = _create(keccak256("NeverRegistered"));
        assertEq(ComplianceFacet(token).policySet(), address(0), "an unknown preset attached a policy set");
    }

    // ── the applied preset actually enforces ────────────────────────────────

    /// @notice RegD506c refuses a verified-but-unaccredited recipient
    /// @dev The regime, enforced — not just recorded. Both parties are active
    ///      and sanctions-clear, but the recipient is not accredited, so the
    ///      accreditation group has no passing rule and the transfer refuses.
    function test_regDRefusesAnUnaccreditedHolder() public {
        (address token, address treasury) = _create(REGD);

        _seed(token, treasury, alice, 1000e18);
        // Both active and sanctions-clear; only accreditation differs.
        registry.setActive(bob, true);
        registry.setClaim(alice, SANCTIONS_KEY, true);
        registry.setClaim(alice, ClaimKeys.US_ACCREDITED, true);
        registry.setClaim(bob, SANCTIONS_KEY, true);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ERC7943CannotTransfer.selector, alice, bob, 10e18));
        uRWAToken(payable(token)).transfer(bob, 10e18);

        // Accredit Bob, and the same transfer goes through.
        registry.setClaim(bob, ClaimKeys.US_ACCREDITED, true);
        vm.prank(alice);
        uRWAToken(payable(token)).transfer(bob, 10e18);
        assertEq(uRWAToken(payable(token)).balanceOf(bob), 10e18);
    }

    /// @notice The Open preset admits any verified, sanctions-clear holder
    function test_openAdmitsAVerifiedHolder() public {
        (address token, address treasury) = _create(OPEN);

        _seed(token, treasury, alice, 1000e18);
        registry.setActive(bob, true);
        registry.setClaim(alice, SANCTIONS_KEY, true);
        registry.setClaim(bob, SANCTIONS_KEY, true);

        vm.prank(alice);
        uRWAToken(payable(token)).transfer(bob, 10e18);
        assertEq(uRWAToken(payable(token)).balanceOf(bob), 10e18);
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _registerPresets() internal {
        // RegD506c: identity AND accredited AND sanctions AND holders. Four
        // groups, one rule each — a pure AND.
        address[] memory rd = new address[](4);
        bytes32[] memory rdG = new bytes32[](4);
        rd[0] = address(identityRule);
        rdG[0] = G_ID;
        rd[1] = address(accreditedRule);
        rdG[1] = G_ACCRED;
        rd[2] = address(sanctionsRule);
        rdG[2] = G_SANCTIONS;
        rd[3] = address(maxHolders);
        rdG[3] = G_HOLDERS;
        factory.registerPreset(REGD, rd, rdG);

        // RegS: identity AND jurisdiction-deny-US AND sanctions.
        address[] memory rs = new address[](3);
        bytes32[] memory rsG = new bytes32[](3);
        rs[0] = address(identityRule);
        rsG[0] = G_ID;
        rs[1] = address(denyUS);
        rsG[1] = G_JURIS;
        rs[2] = address(sanctionsRule);
        rsG[2] = G_SANCTIONS;
        factory.registerPreset(REGS, rs, rsG);

        // Open: identity AND sanctions.
        address[] memory op = new address[](2);
        bytes32[] memory opG = new bytes32[](2);
        op[0] = address(identityRule);
        opG[0] = G_ID;
        op[1] = address(sanctionsRule);
        opG[1] = G_SANCTIONS;
        factory.registerPreset(OPEN, op, opG);
    }

    function _create(bytes32 preset) internal returns (address token, address treasury) {
        registry.setActive(alice, true);
        registry.setClaim(alice, ClaimKeys.IDENTITY_VALID, true);
        registry.setClaim(bob, ClaimKeys.IDENTITY_VALID, true);

        TokenParams memory p = TokenParams({
            name: "Manhattan Office Tower",
            symbol: "MOTT",
            decimals: 18,
            maxSupply: 10_000_000e18,
            lockCap: false,
            preset: preset,
            identityRegistry: address(registry),
            upgradeDelay: 0,
            installEmergencyFacet: false,
            issuerAdmin: issuer,
            upgradeAdmin: issuer,
            supplyOperator: issuer,
            complianceOfficer: officer
        });
        vm.prank(issuer);
        (token, treasury) = factory.createToken(p, PACKAGE, address(0));
    }

    /// @dev Issue into the treasury and distribute to a holder, so the holder
    ///      arrives with a balance through the ordinary pipeline.
    /// @dev The treasury needs a valid-identity claim of its own: it is trusted,
    ///      so it passes the base gate, but `HasValidIdentity` is a rule and
    ///      rules do not see the trust list — it checks the sender's identity
    ///      claim like any other. A real issuer registers its treasury.
    function _seed(address token, address treasury, address to, uint256 amount) internal {
        registry.setClaim(treasury, ClaimKeys.IDENTITY_VALID, true);
        registry.setActive(to, true);
        registry.setClaim(to, ClaimKeys.IDENTITY_VALID, true);
        registry.setClaim(to, SANCTIONS_KEY, true);
        registry.setClaim(to, ClaimKeys.US_ACCREDITED, true);
        vm.startPrank(issuer);
        MonetaryFacet(token).issue(address(0), amount);
        MonetaryFacet(token).distributeFromTreasury(to, amount, 0);
        vm.stopPrank();
    }

    function _package() internal returns (IDiamond.FacetCut[] memory cuts) {
        ComplianceFacet c = new ComplianceFacet();
        MonetaryFacet m = new MonetaryFacet();
        RolesFacet r = new RolesFacet();

        bytes4[] memory cs = new bytes4[](11);
        cs[0] = ComplianceFacet.beforeUpdate.selector;
        cs[1] = ComplianceFacet.afterUpdate.selector;
        cs[2] = ComplianceFacet.canTransfer.selector;
        cs[3] = ComplianceFacet.whyBlocked.selector;
        cs[4] = ComplianceFacet.setPolicySet.selector;
        cs[5] = ComplianceFacet.policySet.selector;
        cs[6] = ComplianceFacet.setIdentityRegistry.selector;
        cs[7] = ComplianceFacet.trust.selector;
        cs[8] = ComplianceFacet.isTrusted.selector;
        cs[9] = ComplianceFacet.subjectHolderCount.selector;
        cs[10] = ComplianceFacet.subjectBalanceOf.selector;

        bytes4[] memory ms = new bytes4[](5);
        ms[0] = MonetaryFacet.issue.selector;
        ms[1] = MonetaryFacet.distributeFromTreasury.selector;
        ms[2] = MonetaryFacet.setTreasury.selector;
        ms[3] = MonetaryFacet.setOfferingRegistry.selector;
        ms[4] = MonetaryFacet.treasury.selector;

        bytes4[] memory rs = new bytes4[](3);
        rs[0] = RolesFacet.grantRole.selector;
        rs[1] = RolesFacet.revokeRole.selector;
        rs[2] = RolesFacet.hasRole.selector;

        cuts = new IDiamond.FacetCut[](3);
        cuts[0] = IDiamond.FacetCut(address(c), IDiamond.FacetCutAction.Add, cs);
        cuts[1] = IDiamond.FacetCut(address(m), IDiamond.FacetCutAction.Add, ms);
        cuts[2] = IDiamond.FacetCut(address(r), IDiamond.FacetCutAction.Add, rs);
    }
}
