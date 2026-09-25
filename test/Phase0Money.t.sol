// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {Vm} from "forge-std/Vm.sol";
import {uRWAFactory} from "../src/uRWAFactory.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {Treasury} from "../src/Treasury.sol";
import {OfferingRegistry} from "../src/OfferingRegistry.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {MonetaryFacet} from "../src/facets/MonetaryFacet.sol";
import {PurchaseFacet} from "../src/facets/PurchaseFacet.sol";
import {RolesFacet} from "../src/facets/RolesFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IEvents} from "../src/interfaces/IEvents.sol";
import {Roles} from "../src/interfaces/Roles.sol";
import {OfferingParams, Tier} from "../src/interfaces/ITreasuryAndOfferings.sol";
import {TokenParams} from "../src/interfaces/IuRWAFactory.sol";
import {Verified, Cash} from "./PurchaseDoor.t.sol";

/// @title Phase 0 · slice 1 — the money paths (G2, G9, G10, G17, G20)
/// @notice Every test here failed before its fix and is the standing proof
///         that the fix holds. The stack is real end to end: the factory-made
///         diamond, the real treasury clone, the real registry. The first
///         test is the treasury-drain proof of concept from session 11, kept
///         as a test so it can never come back.
contract Phase0MoneyTest is Test {
    uRWAFactory factory;
    OfferingRegistry registry;
    Verified verified;
    Cash cash;

    address token;
    address payable treasury;

    address issuer = address(0x1551E4);
    address alice = address(0xA11CE);
    address mallory = address(0xBAD);

    bytes32 constant PACKAGE = keccak256("default.v1");

    function setUp() public {
        vm.warp(1_000_000);
        DiamondCutFacet cut = new DiamondCutFacet();
        Treasury treasuryImpl = new Treasury();
        factory = new uRWAFactory(address(cut), address(treasuryImpl));
        registry = new OfferingRegistry(address(this));
        verified = new Verified();
        cash = new Cash();
        factory.registerPackage(PACKAGE, _package());

        vm.prank(issuer);
        (token, treasury) = _create(false);

        verified.enrol(alice);
        verified.enrol(mallory);
        cash.mint(alice, 1_000_000e18);
        cash.mint(mallory, 1_000_000e18);

        vm.prank(issuer);
        MonetaryFacet(token).issue(address(0), 1_000_000e18);
    }

    // ── G2 · the treasury drain ─────────────────────────────────────────────

    /// @notice A stranger cannot create an offering against someone else's treasury
    /// @dev Session 11's proof of concept: an allow-listed wallet created an
    ///      offering pointing at the issuer's treasury, bought into it, then
    ///      `beginRefunding` and `claimRefund` walked investor money out of a
    ///      treasury the stranger never controlled — and `settle` would have
    ///      unlocked the issuer's real raise to boot. The registry now asks the
    ///      token whether the caller holds `OFFERING_OPERATOR` or `ISSUER_ADMIN`.
    function test_G2_aStrangerCannotCreateAnOfferingAgainstAnotherTreasury() public {
        vm.prank(mallory);
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotAuthorized.selector, mallory, Roles.OFFERING_OPERATOR));
        registry.createOffering(_params(500e18, 1000e18, token), treasury);
    }

    /// @notice The treasury named must belong to the token named, and answer to this registry
    function test_G2_theTreasuryMustBelongToTheTokenAndToThisRegistry() public {
        // A second token, whose treasury is wired to this registry but holds another token.
        vm.prank(issuer);
        (address other, address payable otherTreasury) = _create(false);

        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(IErrors.TreasuryMismatch.selector, otherTreasury, token));
        registry.createOffering(_params(500e18, 1000e18, token), otherTreasury);

        // And a treasury wired to a different registry is refused too.
        OfferingRegistry foreign = new OfferingRegistry(address(this));
        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(IErrors.TreasuryMismatch.selector, otherTreasury, other));
        foreign.createOffering(_params(500e18, 1000e18, other), otherTreasury);
    }

    /// @notice The issuer's own operator creates offerings as before
    function test_G2_theOperatorStillCreatesOfferings() public {
        vm.prank(issuer);
        RolesFacet(token).grantRole(Roles.OFFERING_OPERATOR, alice);
        vm.prank(alice);
        uint256 id = registry.createOffering(_params(500e18, 1000e18, token), treasury);
        assertEq(registry.operatorOf(id), alice);
    }

    // ── G9 · settlement mid-raise ───────────────────────────────────────────

    /// @notice An active offering cannot be settled while its raise is still open
    /// @dev Settling from `Active` before `endAt` unlocked the money raised so
    ///      far while purchases kept landing — the later purchases were then
    ///      locked against an offering already marked Settled, and refunds for
    ///      them were impossible. Settlement now needs `Closed`, or `Active`
    ///      after the end date.
    function test_G9_anActiveOfferingCannotSettleBeforeItsEndDate() public {
        uint256 id = _offering(500e18, 1000e18);
        _buy(alice, id, 600e18);

        vm.expectRevert(abi.encodeWithSelector(IErrors.OfferingNotActive.selector, id, uint8(1)));
        registry.settle(id);

        // After the end date the raise is over and anyone may settle.
        vm.warp(block.timestamp + 31 days);
        registry.settle(id);
        assertEq(registry.statusOf(id), 4, "Settled");
    }

    // ── G10 · rules and states that could go backwards ──────────────────────

    /// @notice A rule cannot be removed from a live offering
    /// @dev Removing an accreditation rule between two purchases let a buyer
    ///      the rule would have refused in through the gap. Rules change while
    ///      the offering is in Draft or Paused, never while it is Active.
    function test_G10_aRuleCannotBeRemovedWhileTheOfferingIsActive() public {
        uint256 id = _offering(500e18, 1000e18);
        vm.prank(issuer);
        registry.pause(id);
        address rule = address(0x5E1F);
        vm.prank(issuer);
        registry.addRule(id, rule);
        vm.prank(issuer);
        registry.unpause(id);

        vm.prank(issuer);
        vm.expectRevert(abi.encodeWithSelector(IErrors.OfferingNotActive.selector, id, uint8(1)));
        registry.removeRule(id, rule);

        vm.prank(issuer);
        registry.pause(id);
        vm.prank(issuer);
        registry.removeRule(id, rule);
        assertEq(registry.rulesOf(id).length, 0);
    }

    /// @notice A finished offering cannot be forced back to life, and nothing can be forced to Settled
    /// @dev `forceStatus` moved any offering to any state. Forcing a Refunding
    ///      offering back to Active trapped the refunds; forcing one to Settled
    ///      skipped the soft-cap check that guards the issuer's withdrawal.
    function test_G10_forceStatusNeverLeavesAFinalStateNorEntersSettled() public {
        uint256 id = _offering(500e18, 1000e18);
        _buy(alice, id, 100e18);
        vm.warp(block.timestamp + 31 days);
        registry.beginRefunding(id);

        vm.expectRevert(abi.encodeWithSelector(IErrors.OfferingStateFinal.selector, id, uint8(5)));
        registry.forceStatus(id, 1, "bring it back");

        uint256 fresh = _offering(500e18, 1000e18);
        vm.expectRevert(abi.encodeWithSelector(IErrors.OfferingStateFinal.selector, fresh, uint8(4)));
        registry.forceStatus(fresh, 4, "skip the soft cap");
    }

    // ── G17 · the factory ignored lockCap; delivery emitted a purchase ──────

    /// @notice A token created with `lockCap` is created capped for good
    function test_G17_lockCapAtCreationIsHonoured() public {
        vm.prank(issuer);
        (address capped,) = _create(true);
        assertTrue(MonetaryFacet(capped).capLocked(), "lockCap was ignored at creation");
        assertFalse(MonetaryFacet(token).capLocked(), "an unlocked cap must stay unlocked");
    }

    /// @notice Delivery emits a delivery, not a second purchase
    /// @dev `PurchaseRecorded` fired again at delivery, so a replay of the logs
    ///      counted every settled purchase twice. The auditor pack rebuilds
    ///      the register from events; a doubled event is a doubled balance.
    function test_G17_deliveryEmitsTokensDeliveredNotASecondPurchase() public {
        uint256 id = _offering(500e18, 1000e18);
        _buy(alice, id, 600e18);
        vm.warp(block.timestamp + 31 days);
        registry.settle(id);

        vm.recordLogs();
        vm.prank(alice);
        registry.claimTokens(0);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bytes32 purchased = IEvents.PurchaseRecorded.selector;
        bytes32 delivered = IEvents.TokensDelivered.selector;
        bool sawDelivered;
        for (uint256 i = 0; i < logs.length; i++) {
            assertTrue(logs[i].topics[0] != purchased, "PurchaseRecorded fired at delivery");
            if (logs[i].topics[0] == delivered) sawDelivered = true;
        }
        assertTrue(sawDelivered, "no TokensDelivered event");
    }

    // ── G20 · the treasury refunded more than was locked ────────────────────

    /// @notice A refund larger than the offering's locked money is refused, not paid from other money
    /// @dev `Treasury.refund` capped the *accounting* decrement at what was
    ///      locked but transferred the full amount asked, so a registry defect
    ///      or a compromised registry could pay one investor out of another
    ///      offering's locked funds or the issuer's proceeds.
    function test_G20_theTreasuryRefusesToRefundMoreThanTheOfferingLocked() public {
        uint256 id = _offering(500e18, 1000e18);
        _buy(alice, id, 100e18);
        cash.mint(treasury, 900e18); // the issuer's other money, sitting in the same treasury

        vm.prank(address(registry));
        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientAvailable.selector, 500e18, 100e18));
        Treasury(treasury).refund(id, address(cash), alice, 500e18);
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _create(bool lockCap) internal returns (address t, address payable tr) {
        TokenParams memory p = TokenParams({
            name: "Phase Zero",
            symbol: "P0",
            decimals: 18,
            maxSupply: 10_000_000e18,
            lockCap: lockCap,
            preset: bytes32(0),
            identityRegistry: address(verified),
            upgradeDelay: 0,
            installEmergencyFacet: false,
            issuerAdmin: issuer,
            upgradeAdmin: issuer,
            supplyOperator: issuer,
            complianceOfficer: issuer
        });
        (address a, address b) = factory.createToken(p, PACKAGE, address(registry));
        return (a, payable(b));
    }

    function _params(uint256 softCap, uint256 hardCap, address t) internal view returns (OfferingParams memory) {
        address[] memory pay = new address[](1);
        pay[0] = address(cash);
        return OfferingParams({
            token: t,
            paymentTokens: pay,
            price: 1e18,
            tiers: new Tier[](0),
            softCap: softCap,
            hardCap: hardCap,
            minPerInvestor: 0,
            maxPerInvestor: 0,
            startAt: uint64(block.timestamp),
            endAt: uint64(block.timestamp + 30 days),
            lockupUntil: 0,
            preMint: true,
            regime: keccak256("Open")
        });
    }

    function _offering(uint256 softCap, uint256 hardCap) internal returns (uint256 id) {
        vm.prank(issuer);
        id = registry.createOffering(_params(softCap, hardCap, token), treasury);
        vm.prank(issuer);
        registry.activate(id);
    }

    function _buy(address who, uint256 id, uint256 amount) internal {
        vm.startPrank(who);
        cash.approve(address(registry), amount);
        PurchaseFacet(token).purchase(id, amount, address(cash));
        vm.stopPrank();
    }

    function _package() internal returns (IDiamond.FacetCut[] memory cuts) {
        ComplianceFacet c = new ComplianceFacet();
        MonetaryFacet m = new MonetaryFacet();
        RolesFacet r = new RolesFacet();
        PurchaseFacet pf = new PurchaseFacet();

        bytes4[] memory cs = new bytes4[](9);
        cs[0] = ComplianceFacet.beforeUpdate.selector;
        cs[1] = ComplianceFacet.afterUpdate.selector;
        cs[2] = ComplianceFacet.canTransfer.selector;
        cs[3] = ComplianceFacet.setPolicySet.selector;
        cs[4] = ComplianceFacet.setIdentityRegistry.selector;
        cs[5] = ComplianceFacet.trust.selector;
        cs[6] = ComplianceFacet.isTrusted.selector;
        cs[7] = ComplianceFacet.subjectOf.selector;
        cs[8] = ComplianceFacet.subjectHolderCount.selector;

        bytes4[] memory ms = new bytes4[](7);
        ms[0] = MonetaryFacet.issue.selector;
        ms[1] = MonetaryFacet.distributeFromTreasury.selector;
        ms[2] = MonetaryFacet.setTreasury.selector;
        ms[3] = MonetaryFacet.setOfferingRegistry.selector;
        ms[4] = MonetaryFacet.treasury.selector;
        ms[5] = MonetaryFacet.lockCap.selector;
        ms[6] = MonetaryFacet.capLocked.selector;

        bytes4[] memory rs = new bytes4[](3);
        rs[0] = RolesFacet.grantRole.selector;
        rs[1] = RolesFacet.revokeRole.selector;
        rs[2] = RolesFacet.hasRole.selector;

        bytes4[] memory ps = new bytes4[](3);
        ps[0] = PurchaseFacet.purchase.selector;
        ps[1] = PurchaseFacet.previewPurchase.selector;
        ps[2] = PurchaseFacet.refundPurchase.selector;

        cuts = new IDiamond.FacetCut[](4);
        cuts[0] = IDiamond.FacetCut(address(c), IDiamond.FacetCutAction.Add, cs);
        cuts[1] = IDiamond.FacetCut(address(m), IDiamond.FacetCutAction.Add, ms);
        cuts[2] = IDiamond.FacetCut(address(r), IDiamond.FacetCutAction.Add, rs);
        cuts[3] = IDiamond.FacetCut(address(pf), IDiamond.FacetCutAction.Add, ps);
    }
}
