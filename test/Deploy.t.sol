// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {StackDeployer} from "../script/Deploy.s.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {PolicySet} from "../src/PolicySet.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {MonetaryFacet} from "../src/facets/MonetaryFacet.sol";
import {PurchaseFacet} from "../src/facets/PurchaseFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {OfferingParams, Tier} from "../src/interfaces/ITreasuryAndOfferings.sol";
import {TokenParams} from "../src/interfaces/IuRWAFactory.sol";

/// @dev The demo raise's payment stablecoin.
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

/// @title The deployment script, run as a test
/// @notice CI stands the whole stack up through **the same code an operator
///         runs** — `StackDeployer._deployStack` — then sells a token through
///         it. If the script rots, this suite goes red before any operator
///         finds out on a chain.
contract DeployTest is Test, StackDeployer {
    Cash cash;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        vm.warp(1_000_000);
        _deployStack(address(this));
        cash = new Cash();
    }

    /// @notice The stack sells: create, issue, offer, purchase, settle, deliver, transfer
    /// @dev Doc 16's per-asset steps, in order, against the freshly deployed
    ///      infrastructure — with the Open preset enforcing along the way.
    function test_theDeployedStackSellsATokenEndToEnd() public {
        (address token, address treasury) = _createToken();

        // The issuer's side: supply into the treasury.
        MonetaryFacet(token).issue(address(0), 1_000_000e18);

        // The raise.
        uint256 offeringId = _offering(token, treasury, 500e18, 10_000e18);
        offeringRegistry.activate(offeringId);

        identityRegistry.allow(alice);
        cash.mint(alice, 10_000e18);
        vm.startPrank(alice);
        cash.approve(address(offeringRegistry), 600e18);
        PurchaseFacet(token).purchase(offeringId, 600e18, address(cash));
        vm.stopPrank();

        vm.warp(block.timestamp + 31 days);
        offeringRegistry.settle(offeringId);
        vm.prank(alice);
        offeringRegistry.claimTokens(0);
        assertEq(uRWAToken(payable(token)).balanceOf(alice), 600e18, "delivery failed");

        // And the token trades on, through the pipeline.
        identityRegistry.allow(bob);
        vm.prank(alice);
        uRWAToken(payable(token)).transfer(bob, 100e18);
        assertEq(uRWAToken(payable(token)).balanceOf(bob), 100e18);
    }

    /// @notice The Open preset the script registered is attached and enforcing
    /// @dev An unverified recipient is refused; the same transfer passes once
    ///      the allowlist admits them. The preset is real, not a label.
    function test_theRegisteredPresetEnforcesOnTheDeployedToken() public {
        (address token, address treasury) = _createToken();
        MonetaryFacet(token).issue(address(0), 1000e18);
        identityRegistry.allow(alice);
        // The treasury distributes under the Open preset's identity rule.
        identityRegistry.allow(treasury);
        MonetaryFacet(token).distributeFromTreasury(alice, 500e18, 0);

        address ps = ComplianceFacet(token).policySet();
        assertTrue(ps != address(0), "the preset attached no policy set");
        assertEq(PolicySet(ps).owner(), address(this), "the compliance officer must own it");

        vm.prank(alice);
        vm.expectRevert();
        uRWAToken(payable(token)).transfer(bob, 10e18);

        identityRegistry.allow(bob);
        vm.prank(alice);
        uRWAToken(payable(token)).transfer(bob, 10e18);
        assertEq(uRWAToken(payable(token)).balanceOf(bob), 10e18);
    }

    /// @notice Every selector both packages promise actually routes
    /// @dev The loupe answers for each one on a freshly created token. A package
    ///      registering a selector no facet serves — or missing one a facet
    ///      has — would strand callers in production while every unit test of
    ///      the facet itself stayed green.
    function test_everyRegisteredSelectorRoutes() public {
        (address token,) = _createToken();

        IDiamond.FacetCut[] memory cuts = _basePurchasePackage();
        for (uint256 i = 0; i < cuts.length; i++) {
            for (uint256 j = 0; j < cuts[i].functionSelectors.length; j++) {
                assertEq(
                    uRWAToken(payable(token)).facetAddress(cuts[i].functionSelectors[j]),
                    cuts[i].facetAddress,
                    "a promised selector does not route to its facet"
                );
            }
        }
    }

    /// @notice The three presets are queryable, composed as doc 10 writes them
    function test_thePresetsAreRegisteredAsDocumented() public view {
        (address[] memory regd,) = factory.presetOf(PRESET_REGD);
        (address[] memory regs,) = factory.presetOf(PRESET_REGS);
        (address[] memory open,) = factory.presetOf(PRESET_OPEN);
        assertEq(regd.length, 4, "RegD506c: identity, accredited, sanctions, holder cap");
        assertEq(regs.length, 3, "RegS: identity, jurisdiction, sanctions");
        assertEq(open.length, 2, "Open: identity, sanctions");
        assertEq(regd[0], address(identityRule));
        assertEq(regs[1], address(jurisdictionDenyUS));
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _createToken() internal returns (address token, address treasury) {
        TokenParams memory p = TokenParams({
            name: "Demo Asset",
            symbol: "DEMO",
            decimals: 18,
            maxSupply: 0,
            lockCap: false,
            preset: PRESET_OPEN,
            identityRegistry: address(identityRegistry),
            upgradeDelay: 0,
            installEmergencyFacet: false,
            issuerAdmin: address(this),
            upgradeAdmin: address(this),
            supplyOperator: address(this),
            complianceOfficer: address(this)
        });
        (token, treasury) = factory.createToken(p, PACKAGE_BASE_PURCHASE, address(offeringRegistry));
        // The treasury sends under the preset's identity rule when distributing.
        identityRegistry.allow(treasury);
    }

    function _offering(address token, address treasury, uint256 softCap, uint256 hardCap) internal returns (uint256) {
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
            regime: PRESET_OPEN
        });
        return offeringRegistry.createOffering(p, treasury);
    }
}
