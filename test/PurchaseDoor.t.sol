// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
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
import {IIdentityRegistry, Claim} from "../src/interfaces/IIdentityRegistry.sol";
import {OfferingParams, Tier} from "../src/interfaces/ITreasuryAndOfferings.sol";
import {TokenParams} from "../src/interfaces/IuRWAFactory.sol";

/// @dev Everyone registered here is verified. The pipeline still runs; this
///      registry just answers yes for wallets the test enrols.
contract Verified is IIdentityRegistry {
    mapping(address => bool) public enrolled;

    function enrol(address w) external {
        enrolled[w] = true;
    }

    function subjectOf(address w) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(w));
    }

    function isActive(address w) external view returns (bool) {
        return enrolled[w];
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        return true;
    }
}

/// @dev A payment stablecoin.
contract Cash {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 v) external {
        balanceOf[to] += v;
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        return true;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        if (balanceOf[msg.sender] < v) return false;
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        return true;
    }

    function transferFrom(address f, address to, uint256 v) external returns (bool) {
        if (allowance[f][msg.sender] < v || balanceOf[f] < v) return false;
        allowance[f][msg.sender] -= v;
        balanceOf[f] -= v;
        balanceOf[to] += v;
        return true;
    }
}

/// @title `CU-06` — primary issuance end to end, through the real stack
/// @notice No stubs on the money path: the factory-made diamond, the real
///         treasury clone, the real offering registry. The audit found that a
///         permissive token stub had hidden a purchase that reverted in
///         production; this suite is the standing answer — if the chain from
///         wallet to token door to registry to treasury to delivery breaks
///         anywhere, something here goes red.
contract PurchaseDoorTest is Test {
    uRWAFactory factory;
    OfferingRegistry registry;
    Verified verified;
    Cash cash;

    address token;
    address payable treasury;
    uint256 offeringId;

    address issuer = address(0x1551E4);
    address alice = address(0xA11CE);

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

        TokenParams memory p = TokenParams({
            name: "Manhattan Office Tower",
            symbol: "MOTT",
            decimals: 18,
            maxSupply: 10_000_000e18,
            lockCap: false,
            preset: bytes32(0),
            identityRegistry: address(verified),
            upgradeDelay: 0,
            installEmergencyFacet: false,
            issuerAdmin: issuer,
            upgradeAdmin: issuer,
            supplyOperator: issuer,
            complianceOfficer: issuer
        });
        vm.prank(issuer);
        (address t, address tr) = factory.createToken(p, PACKAGE, address(registry));
        token = t;
        treasury = payable(tr);

        verified.enrol(alice);
        cash.mint(alice, 1_000_000e18);

        // Supply exists before anything is sold: issued into the treasury,
        // where it stays until settlement delivers it.
        vm.prank(issuer);
        MonetaryFacet(token).issue(address(0), 1_000_000e18);

        offeringId = _offering(500e18, 1000e18);
        registry.activate(offeringId);
    }

    // ── the whole chain, forward ────────────────────────────────────────────

    /// @notice Wallet → token door → registry → treasury → settlement → delivery
    /// @dev One address for the investor from start to finish: they approve the
    ///      registry once, then talk only to the token. The distribution leg at
    ///      the end runs the token's full pipeline against the real compliance
    ///      facet — nothing on this path is a stub.
    function test_aPurchaseThroughTheTokenSettlesAndDelivers() public {
        vm.startPrank(alice);
        cash.approve(address(registry), 600e18);
        PurchaseFacet(token).purchase(offeringId, 600e18, address(cash));
        vm.stopPrank();

        // Money landed in the treasury and is locked; nothing delivered yet.
        assertEq(cash.balanceOf(treasury), 600e18);
        assertEq(Treasury(treasury).lockedPayments(address(cash)), 600e18, "investor money must lock on arrival");
        assertEq(uRWAToken(payable(token)).balanceOf(alice), 0, "delivered before settlement");

        // Soft cap met: anyone settles, the buyer claims, the pipeline runs.
        vm.warp(block.timestamp + 31 days);
        registry.settle(offeringId);
        vm.prank(alice);
        registry.claimTokens(0);

        assertEq(uRWAToken(payable(token)).balanceOf(alice), 600e18, "delivery did not reach the buyer");
        assertEq(Treasury(treasury).lockedPayments(address(cash)), 0, "the lock outlived settlement");
    }

    /// @notice The preview through the token answers before anyone signs
    function test_thePreviewAnswersThroughTheToken() public view {
        (uint256 cost, uint256 tokens,) = PurchaseFacet(token).previewPurchase(offeringId, 250e18);
        assertEq(cost, 250e18);
        assertEq(tokens, 250e18);
    }

    // ── the whole chain, reversed ───────────────────────────────────────────

    /// @notice A failed raise refunds through the same door it sold through
    /// @dev Soft cap missed: the investor claims their money back at the token,
    ///      without the operator's help, and the treasury pays even though the
    ///      lock is still on — refunding is what the lock exists for.
    function test_aFailedRaiseRefundsThroughTheToken() public {
        vm.startPrank(alice);
        cash.approve(address(registry), 100e18);
        PurchaseFacet(token).purchase(offeringId, 100e18, address(cash)); // below the 500e18 soft cap
        vm.stopPrank();

        uint256 before = cash.balanceOf(alice);
        vm.warp(block.timestamp + 31 days);
        registry.beginRefunding(offeringId);

        vm.prank(alice);
        PurchaseFacet(token).refundPurchase(0);

        assertEq(cash.balanceOf(alice), before + 100e18, "the refund did not come back");
        assertEq(uRWAToken(payable(token)).balanceOf(alice), 0, "a failed raise must deliver nothing");
    }

    /// @notice A token with no registry wired says so, before touching money
    function test_anUnwiredTokenRefusesThePurchaseDoor() public {
        TokenParams memory p = TokenParams({
            name: "Unwired",
            symbol: "UNW",
            decimals: 18,
            maxSupply: 0,
            lockCap: false,
            preset: bytes32(0),
            identityRegistry: address(verified),
            upgradeDelay: 0,
            installEmergencyFacet: false,
            issuerAdmin: issuer,
            upgradeAdmin: issuer,
            supplyOperator: issuer,
            complianceOfficer: issuer
        });
        vm.prank(issuer);
        (address bare,) = factory.createToken(p, PACKAGE, address(0));

        vm.prank(alice);
        vm.expectRevert(IErrors.OfferingRegistryNotSet.selector);
        PurchaseFacet(bare).purchase(1, 1e18, address(cash));
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _offering(uint256 softCap, uint256 hardCap) internal returns (uint256) {
        address[] memory pay = new address[](1);
        pay[0] = address(cash);
        OfferingParams memory p = OfferingParams({
            token: token,
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
        return registry.createOffering(p, treasury);
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
