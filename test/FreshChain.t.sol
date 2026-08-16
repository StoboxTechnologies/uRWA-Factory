// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAFactory} from "../src/uRWAFactory.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {Treasury} from "../src/Treasury.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {MonetaryFacet} from "../src/facets/MonetaryFacet.sol";
import {FreezeFacet, LockupFacet} from "../src/facets/RestrictionFacets.sol";
import {Erc1404Facet, RolesFacet} from "../src/facets/RolesFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IIdentityRegistry, Claim} from "../src/interfaces/IIdentityRegistry.sol";
import {TokenParams} from "../src/interfaces/IuRWAFactory.sol";
import {Roles} from "../src/interfaces/Roles.sol";

/// @dev Tier 0: the open-source default. Its own storage, no Stobox contract,
///      no attestation service, nothing to depend on.
contract AllowlistRegistry is IIdentityRegistry {
    mapping(address => bool) public permitted;

    function allow(address a) external {
        permitted[a] = true;
    }

    function subjectOf(address wallet) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(wallet));
    }

    function isActive(address wallet) external view returns (bool) {
        return permitted[wallet];
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        return true;
    }
}

/// @title The open-source claim, as a test
/// @notice Deploys the entire stack on a chain where **no Stobox contract
///         exists**, issues, distributes and transfers — the credibility test
///         from doc 19, run rather than asserted.
/// @dev `L4.13`. If this ever fails, the open-source claim has broken and
///         nothing in the documentation is worth reading.
contract FreshChainTest is Test {
    uRWAFactory factory;
    AllowlistRegistry registry;

    address issuer = address(0x1551E4);
    address upgradeAdmin = address(0x11);
    address supplyOperator = address(0x22);
    address complianceOfficer = address(0x33);
    address investor = address(0x44);
    address second = address(0x55);

    bytes32 constant PACKAGE = keccak256("default.v1");

    function setUp() public {
        // Everything a forker deploys, in order, with no external dependency.
        DiamondCutFacet cut = new DiamondCutFacet();
        Treasury treasuryImpl = new Treasury();
        factory = new uRWAFactory(address(cut), address(treasuryImpl));
        registry = new AllowlistRegistry();

        factory.registerPackage(PACKAGE, _defaultPackage());
    }

    /// @notice One transaction from nothing to a working compliant token
    function test_theWholeStackDeploysAndTransfers() public {
        (address token, address treasury) = _create(0);

        // The token is what it claims to be, verifiable by anyone.
        assertTrue(uRWAToken(payable(token)).supportsInterface(0x3edbb4c4), "not ERC-7943");
        assertTrue(factory.isFactoryIssued(token), "provenance not recorded");
        assertEq(uRWAToken(payable(token)).symbol(), "MOTT");

        registry.allow(investor);
        registry.allow(second);

        // Issue into the treasury, distribute out of it.
        vm.prank(supplyOperator);
        MonetaryFacet(token).issue(address(0), 1_000e18);
        assertEq(uRWAToken(payable(token)).balanceOf(treasury), 1_000e18);

        vm.prank(supplyOperator);
        MonetaryFacet(token).distributeFromTreasury(investor, 400e18, 0);
        assertEq(uRWAToken(payable(token)).balanceOf(investor), 400e18);

        // And a holder-to-holder transfer, through the full pipeline.
        vm.prank(investor);
        uRWAToken(payable(token)).transfer(second, 100e18);
        assertEq(uRWAToken(payable(token)).balanceOf(second), 100e18);

        // The counts are maintained, by people rather than addresses.
        assertEq(ComplianceFacet(token).subjectHolderCount(), 3, "treasury, investor, second");
    }

    /// @notice The factory keeps nothing
    /// @dev The property that stops the factory being a single point of
    ///      compromise for every token on the chain. Asserted directly,
    ///      because "we do not keep the keys" is exactly the kind of claim that
    ///      needs to be checkable rather than believed.
    function test_theFactoryRetainsNoPowerOverWhatItCreated() public {
        (address token,) = _create(0);
        RolesFacet r = RolesFacet(token);

        assertFalse(r.hasRole(Roles.UPGRADE_ADMIN, address(factory)), "factory kept upgrade rights");
        assertFalse(r.hasRole(Roles.ISSUER_ADMIN, address(factory)), "factory kept admin rights");
        assertFalse(r.hasRole(Roles.SUPPLY_OPERATOR, address(factory)));
        assertFalse(r.hasRole(Roles.COMPLIANCE_OFFICER, address(factory)));

        vm.prank(address(factory));
        vm.expectRevert();
        ComplianceFacet(token).setPolicySet(address(0xBAD));
    }

    /// @notice The four roles went where the issuer said
    function test_rolesLandWhereTheIssuerAsked() public {
        (address token,) = _create(0);
        RolesFacet r = RolesFacet(token);

        assertTrue(r.hasRole(Roles.ISSUER_ADMIN, issuer));
        assertTrue(r.hasRole(Roles.UPGRADE_ADMIN, upgradeAdmin));
        assertTrue(r.hasRole(Roles.SUPPLY_OPERATOR, supplyOperator));
        assertTrue(r.hasRole(Roles.COMPLIANCE_OFFICER, complianceOfficer));
    }

    /// @notice The treasury is trusted openly, not exempted secretly
    /// @dev An exemption written into the ledger would be one nobody could
    ///      audit. This one is a trust-list entry with a reason, readable by
    ///      anyone.
    function test_theTreasuryIsTrustedWithAStatedReason() public {
        (address token, address treasury) = _create(0);
        assertTrue(ComplianceFacet(token).isTrusted(treasury));
        assertEq(ComplianceFacet(token).trustReasonOf(treasury), "token treasury");
    }

    /// @notice A configured delay is in force on the token the issuer receives
    /// @dev The factory's own wiring cuts land immediately; the delay applies
    ///      to everything after.
    function test_aConfiguredDelayIsAlreadyInForce() public {
        (address token,) = _create(7 days);
        assertEq(DiamondCutFacet(token).upgradeDelay(), 7 days);
    }

    /// @notice The delay cannot be lowered without waiting it out
    /// @dev Otherwise it is worthless: an admin would zero it and cut in the
    ///      same transaction, and a holder who relied on a week's notice would
    ///      have had none.
    function test_theDelayCannotBeEscapedByLoweringIt() public {
        (address token,) = _create(7 days);

        vm.prank(upgradeAdmin);
        DiamondCutFacet(token).setUpgradeDelay(0);
        assertEq(DiamondCutFacet(token).upgradeDelay(), 7 days, "the delay was lowered immediately");

        vm.warp(block.timestamp + 7 days);
        vm.prank(upgradeAdmin);
        DiamondCutFacet(token).setUpgradeDelay(0);
        assertEq(DiamondCutFacet(token).upgradeDelay(), 0, "the delay never lowered");
    }

    /// @notice Raising it takes effect at once
    function test_theDelayMayBeRaisedImmediately() public {
        (address token,) = _create(1 days);
        vm.prank(upgradeAdmin);
        DiamondCutFacet(token).setUpgradeDelay(30 days);
        assertEq(DiamondCutFacet(token).upgradeDelay(), 30 days);
    }

    /// @notice Two tokens, two treasuries
    /// @dev Isolation is the reason the treasury is cloned rather than shared.
    function test_eachTokenGetsItsOwnTreasury() public {
        (address a, address ta) = _create(0);
        (address b, address tb) = _create(0);
        assertTrue(a != b && ta != tb, "a treasury was shared between tokens");
        assertEq(Treasury(ta).token(), a);
        assertEq(Treasury(tb).token(), b);
    }

    /// @notice `L4.12` — the default deployment charges nothing
    /// @dev The fee half is asserted here. The other half of the invariant —
    ///      that no Stobox token is named anywhere in the source — is a grep in
    ///      CI, because such a reference would be a string rather than a call,
    ///      and no test can see a string. Naming the ticker in this comment is
    ///      what broke that job once; it is checked literally, on purpose.
    function test_noFeeIsChargedInTheOpenDistribution() public view {
        assertEq(factory.fee(), 0);
        assertEq(factory.feeToken(), address(0));
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _create(uint64 delay) internal returns (address token, address treasury) {
        TokenParams memory p = TokenParams({
            name: "Manhattan Office Tower",
            symbol: "MOTT",
            decimals: 18,
            maxSupply: 10_000_000e18,
            lockCap: false,
            preset: keccak256("Open"),
            identityRegistry: address(registry),
            upgradeDelay: delay,
            installEmergencyFacet: false,
            issuerAdmin: issuer,
            upgradeAdmin: upgradeAdmin,
            supplyOperator: supplyOperator,
            complianceOfficer: complianceOfficer
        });
        vm.prank(issuer);
        (token, treasury) = factory.createToken(p, PACKAGE, address(0));
    }

    /// @dev The default package: everything a plain issuance needs, and the
    ///      emergency facet deliberately absent — its absence is provable
    ///      through the loupe.
    function _defaultPackage() internal returns (IDiamond.FacetCut[] memory cuts) {
        ComplianceFacet c = new ComplianceFacet();
        MonetaryFacet m = new MonetaryFacet();
        RolesFacet r = new RolesFacet();
        FreezeFacet f = new FreezeFacet();
        LockupFacet l = new LockupFacet();
        Erc1404Facet e = new Erc1404Facet();

        cuts = new IDiamond.FacetCut[](6);
        cuts[0] = IDiamond.FacetCut(address(c), IDiamond.FacetCutAction.Add, _compliance());
        cuts[1] = IDiamond.FacetCut(address(m), IDiamond.FacetCutAction.Add, _monetary());
        cuts[2] = IDiamond.FacetCut(address(r), IDiamond.FacetCutAction.Add, _roles());
        cuts[3] = IDiamond.FacetCut(address(f), IDiamond.FacetCutAction.Add, _freeze());
        cuts[4] = IDiamond.FacetCut(address(l), IDiamond.FacetCutAction.Add, _lockup());
        cuts[5] = IDiamond.FacetCut(address(e), IDiamond.FacetCutAction.Add, _legacy());
    }

    function _compliance() private pure returns (bytes4[] memory s) {
        s = new bytes4[](16);
        s[0] = ComplianceFacet.beforeUpdate.selector;
        s[1] = ComplianceFacet.afterUpdate.selector;
        s[2] = ComplianceFacet.canSend.selector;
        s[3] = ComplianceFacet.canReceive.selector;
        s[4] = ComplianceFacet.canTransfer.selector;
        s[5] = ComplianceFacet.getFrozenTokens.selector;
        s[6] = ComplianceFacet.unfrozenBalanceOf.selector;
        s[7] = ComplianceFacet.whyBlocked.selector;
        s[8] = ComplianceFacet.setPolicySet.selector;
        s[9] = ComplianceFacet.setIdentityRegistry.selector;
        s[10] = ComplianceFacet.identityRegistry.selector;
        s[11] = ComplianceFacet.trust.selector;
        s[12] = ComplianceFacet.isTrusted.selector;
        s[13] = ComplianceFacet.trustReasonOf.selector;
        s[14] = ComplianceFacet.pause.selector;
        s[15] = ComplianceFacet.subjectHolderCount.selector;
    }

    function _monetary() private pure returns (bytes4[] memory s) {
        s = new bytes4[](6);
        s[0] = MonetaryFacet.issue.selector;
        s[1] = MonetaryFacet.redeem.selector;
        s[2] = MonetaryFacet.distributeFromTreasury.selector;
        s[3] = MonetaryFacet.setTreasury.selector;
        s[4] = MonetaryFacet.setOfferingRegistry.selector;
        s[5] = MonetaryFacet.totalIssued.selector;
    }

    function _roles() private pure returns (bytes4[] memory s) {
        s = new bytes4[](4);
        s[0] = RolesFacet.grantRole.selector;
        s[1] = RolesFacet.revokeRole.selector;
        s[2] = RolesFacet.hasRole.selector;
        s[3] = RolesFacet.renounceRole.selector;
    }

    function _freeze() private pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = FreezeFacet.setFrozenTokens.selector;
    }

    function _lockup() private pure returns (bytes4[] memory s) {
        s = new bytes4[](2);
        s[0] = LockupFacet.addLockup.selector;
        s[1] = LockupFacet.lockupCount.selector;
    }

    function _legacy() private pure returns (bytes4[] memory s) {
        s = new bytes4[](1);
        s[0] = Erc1404Facet.detectTransferRestriction.selector;
    }
}
