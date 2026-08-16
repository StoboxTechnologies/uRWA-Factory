// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {MonetaryFacet} from "../src/facets/MonetaryFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IIdentityRegistry, Claim} from "../src/interfaces/IIdentityRegistry.sol";
import {Roles} from "../src/interfaces/Roles.sol";

contract Gate is IIdentityRegistry {
    mapping(address => bool) public ok;

    function allow(address a) external {
        ok[a] = true;
    }

    function subjectOf(address w) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(w));
    }

    function isActive(address w) external view returns (bool) {
        return ok[w];
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        return true;
    }
}

/// @title L4.4 and L4.7 — supply, and the two facts about it that must hold
contract SupplyTest is Test {
    uRWAToken token;
    Gate gate;

    address treasury = address(0x7EA);
    address investor = address(0x1);
    address stranger = address(0xBAD);

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        token = new uRWAToken("Test", "TST", 18, 1_000_000e18, address(this), address(cutFacet), address(this), 0);
        gate = new Gate();

        _install();
        _grant(Roles.UPGRADE_ADMIN);
        _grant(Roles.ISSUER_ADMIN);
        _grant(Roles.SUPPLY_OPERATOR);

        ComplianceFacet(address(token)).setIdentityRegistry(address(gate));
        MonetaryFacet(address(token)).setTreasury(treasury);
        gate.allow(treasury);
        gate.allow(investor);
    }

    // ── L4.7 · totalIssued is monotonic, capLocked is irreversible ──────────

    /// @notice Redeeming lowers supply and leaves cumulative issuance alone
    /// @dev The two answer different questions — what exists now, and what has
    ///      ever been created. Collapsing them loses the second permanently,
    ///      and it is the one a regulator asks about.
    function test_totalIssuedNeverDecreases() public {
        MonetaryFacet m = MonetaryFacet(address(token));
        m.issue(treasury, 500e18);
        m.issue(treasury, 300e18);
        assertEq(m.totalIssued(), 800e18);
        assertEq(token.totalSupply(), 800e18);

        m.redeem(300e18);
        assertEq(token.totalSupply(), 500e18, "supply did not fall");
        assertEq(m.totalIssued(), 800e18, "cumulative issuance moved");
    }

    /// @notice A locked cap cannot be raised, lowered or unlocked
    /// @dev A cap that can be changed later is not a cap, and an investor
    ///      cannot tell the two apart without this flag.
    function test_lockedCapIsIrreversible() public {
        MonetaryFacet m = MonetaryFacet(address(token));
        m.setMaxSupply(2_000_000e18);
        m.lockCap();

        assertTrue(m.capLocked());
        vm.expectRevert(IErrors.CapIsLocked.selector);
        m.setMaxSupply(3_000_000e18);
        vm.expectRevert(IErrors.CapIsLocked.selector);
        m.setMaxSupply(1_000e18);
    }

    function test_issuanceCannotExceedTheCap() public {
        MonetaryFacet m = MonetaryFacet(address(token));
        m.issue(treasury, 999_000e18);

        vm.expectRevert(abi.encodeWithSelector(IErrors.MaxSupplyExceeded.selector, 2000e18, 1000e18));
        m.issue(treasury, 2000e18);

        m.issue(treasury, 1000e18);
        assertEq(token.totalSupply(), 1_000_000e18);
    }

    /// @notice The cap cannot be set below what already exists
    function test_capCannotBeSetBelowSupply() public {
        MonetaryFacet m = MonetaryFacet(address(token));
        m.issue(treasury, 500e18);
        vm.expectRevert(abi.encodeWithSelector(IErrors.MaxSupplyExceeded.selector, 100e18, 500e18));
        m.setMaxSupply(100e18);
    }

    // ── L4.4 · no value reaches a holder outside the pipeline ───────────────

    /// @notice Distribution runs the full pipeline
    /// @dev The operator who issued the supply still cannot hand it to someone
    ///      who may not hold it. If this passed, the pipeline would be optional
    ///      for exactly the party most able to bypass it.
    function test_distributionCannotReachAnIneligibleHolder() public {
        MonetaryFacet m = MonetaryFacet(address(token));
        m.issue(treasury, 100e18);

        vm.expectRevert(abi.encodeWithSelector(IErrors.ERC7943CannotReceive.selector, stranger));
        m.distributeFromTreasury(stranger, 10e18, 0);

        m.distributeFromTreasury(investor, 10e18, 0);
        assertEq(token.balanceOf(investor), 10e18);
    }

    /// @notice A distribution lockup restricts what was just delivered
    function test_distributionCanArriveLocked() public {
        MonetaryFacet m = MonetaryFacet(address(token));
        m.issue(treasury, 100e18);
        m.distributeFromTreasury(investor, 40e18, uint64(block.timestamp + 365 days));

        assertEq(token.balanceOf(investor), 40e18);
        assertEq(ComplianceFacet(address(token)).getFrozenTokens(investor), 40e18);
        assertEq(ComplianceFacet(address(token)).unfrozenBalanceOf(investor), 0, "locked tokens were movable");
    }

    /// @notice Issuance and redemption keep the holder counts honest
    function test_supplyChangesMaintainHolderCounts() public {
        MonetaryFacet m = MonetaryFacet(address(token));
        ComplianceFacet c = ComplianceFacet(address(token));

        m.issue(treasury, 100e18);
        assertEq(c.subjectHolderCount(), 1, "the treasury is a holder");

        m.distributeFromTreasury(investor, 100e18, 0);
        assertEq(c.subjectHolderCount(), 1, "the treasury emptied, the investor arrived");

        assertEq(c.subjectBalanceOf(keccak256(abi.encodePacked(investor))), 100e18);
    }

    // ── access ──────────────────────────────────────────────────────────────

    function test_onlySupplyOperatorMayIssue() public {
        vm.prank(investor);
        vm.expectRevert();
        MonetaryFacet(address(token)).issue(treasury, 1e18);
    }

    function test_issuingWithoutATreasuryReverts() public {
        MonetaryFacet(address(token)).setTreasury(address(0));
        vm.expectRevert(IErrors.TreasuryNotSet.selector);
        MonetaryFacet(address(token)).issue(address(0), 1e18);
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _install() internal {
        MonetaryFacet m = new MonetaryFacet();
        ComplianceFacet c = new ComplianceFacet();

        bytes4[] memory ms = new bytes4[](9);
        ms[0] = MonetaryFacet.issue.selector;
        ms[1] = MonetaryFacet.redeem.selector;
        ms[2] = MonetaryFacet.distributeFromTreasury.selector;
        ms[3] = MonetaryFacet.setMaxSupply.selector;
        ms[4] = MonetaryFacet.lockCap.selector;
        ms[5] = MonetaryFacet.capLocked.selector;
        ms[6] = MonetaryFacet.totalIssued.selector;
        ms[7] = MonetaryFacet.setTreasury.selector;
        ms[8] = MonetaryFacet.treasury.selector;

        bytes4[] memory cs = new bytes4[](7);
        cs[0] = ComplianceFacet.beforeUpdate.selector;
        cs[1] = ComplianceFacet.afterUpdate.selector;
        cs[2] = ComplianceFacet.setIdentityRegistry.selector;
        cs[3] = ComplianceFacet.getFrozenTokens.selector;
        cs[4] = ComplianceFacet.unfrozenBalanceOf.selector;
        cs[5] = ComplianceFacet.subjectHolderCount.selector;
        cs[6] = ComplianceFacet.subjectBalanceOf.selector;

        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](2);
        cuts[0] = IDiamond.FacetCut(address(m), IDiamond.FacetCutAction.Add, ms);
        cuts[1] = IDiamond.FacetCut(address(c), IDiamond.FacetCutAction.Add, cs);
        DiamondCutFacet(address(token)).diamondCut(cuts, address(0), "");
    }

    function _grant(bytes32 role) internal {
        bytes32 rolesSlot = keccak256("urwa.storage.roles.v1");
        bytes32 inner = keccak256(abi.encode(role, uint256(rolesSlot)));
        vm.store(address(token), keccak256(abi.encode(address(this), uint256(inner))), bytes32(uint256(1)));
    }
}
