// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {FreezeFacet, LockupFacet} from "../src/facets/RestrictionFacets.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IEvents} from "../src/interfaces/IEvents.sol";
import {IIdentityRegistry, Claim} from "../src/interfaces/IIdentityRegistry.sol";
import {Roles} from "../src/interfaces/Roles.sol";
import {Layout} from "../src/storage/Layout.sol";

contract OpenRegistry is IIdentityRegistry {
    function subjectOf(address w) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(w));
    }

    function isActive(address) external pure returns (bool) {
        return true;
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        return true;
    }
}

/// @title The composed frozen total, and the two ways a balance is restricted
contract RestrictionsTest is Test {
    uRWAToken token;
    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        token = new uRWAToken("Test", "TST", 18, 0, address(this), address(cutFacet), address(this), 0);
        _install();
        _grant(Roles.UPGRADE_ADMIN);
        _grant(Roles.COMPLIANCE_OFFICER);
        ComplianceFacet(address(token)).setIdentityRegistry(address(new OpenRegistry()));
        _seed(alice, 1000e18);
    }

    // ── composition ─────────────────────────────────────────────────────────

    /// @notice The total is the freeze plus every unexpired lockup
    function test_frozenTotalComposesBothKinds() public {
        FreezeFacet(address(token)).setFrozenTokens(alice, 100e18);
        LockupFacet(address(token)).addLockup(alice, 250e18, uint64(block.timestamp + 365 days), "12-month hold");

        assertEq(ComplianceFacet(address(token)).getFrozenTokens(alice), 350e18);
        assertEq(ComplianceFacet(address(token)).unfrozenBalanceOf(alice), 650e18);
    }

    /// @notice The event reports the composed total, not the amount passed in
    /// @dev So an integrator reading one event sees what `getFrozenTokens`
    ///      returns and never has to sum history.
    function test_frozenEventCarriesTheComposedTotal() public {
        LockupFacet(address(token)).addLockup(alice, 250e18, uint64(block.timestamp + 30 days), "lockup");

        vm.expectEmit(true, false, false, true, address(token));
        emit IEvents.Frozen(alice, 350e18);
        FreezeFacet(address(token)).setFrozenTokens(alice, 100e18);
    }

    /// @notice A lockup ends by time, with no transaction
    /// @dev No keeper, no release call, no stale state. The composed total
    ///      simply stops counting it.
    function test_lockupExpiresWithoutAnyTransaction() public {
        LockupFacet(address(token)).addLockup(alice, 400e18, uint64(block.timestamp + 30 days), "hold period");
        assertEq(ComplianceFacet(address(token)).getFrozenTokens(alice), 400e18);

        vm.warp(block.timestamp + 30 days + 1);

        assertEq(ComplianceFacet(address(token)).getFrozenTokens(alice), 0, "the lockup did not lapse on its own");
        assertEq(LockupFacet(address(token)).lockupCount(alice), 1, "the entry should still be there, merely expired");
    }

    /// @notice `releaseExpired` changes nothing except the array
    function test_releaseExpiredIsHousekeepingOnly() public {
        LockupFacet(address(token)).addLockup(alice, 100e18, uint64(block.timestamp + 1 days), "a");
        LockupFacet(address(token)).addLockup(alice, 100e18, uint64(block.timestamp + 90 days), "b");
        vm.warp(block.timestamp + 2 days);

        uint256 before = ComplianceFacet(address(token)).getFrozenTokens(alice);
        LockupFacet(address(token)).releaseExpired(alice);

        assertEq(ComplianceFacet(address(token)).getFrozenTokens(alice), before, "housekeeping changed the total");
        assertEq(LockupFacet(address(token)).lockupCount(alice), 1);
    }

    /// @notice Anyone may run it — it can only drop what has already lapsed
    function test_anyoneMayReleaseExpired() public {
        LockupFacet(address(token)).addLockup(alice, 100e18, uint64(block.timestamp + 1 days), "a");
        vm.warp(block.timestamp + 2 days);

        vm.prank(bob);
        LockupFacet(address(token)).releaseExpired(alice);
        assertEq(LockupFacet(address(token)).lockupCount(alice), 0);
    }

    // ── enforcement ─────────────────────────────────────────────────────────

    function test_transferRefusedAboveTheUnfrozenBalance() public {
        FreezeFacet(address(token)).setFrozenTokens(alice, 900e18);

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(IErrors.ERC7943InsufficientUnfrozenBalance.selector, alice, 200e18, 100e18)
        );
        token.transfer(bob, 200e18);

        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    /// @notice `L4.11` — the total may exceed the balance and must not revert
    /// @dev A freeze set before a redemption outlives the balance it referred
    ///      to. Reverting here would break the standard on a legitimate state.
    function test_frozenMayExceedBalance() public {
        FreezeFacet(address(token)).setFrozenTokens(alice, type(uint256).max);
        assertEq(ComplianceFacet(address(token)).getFrozenTokens(alice), type(uint256).max);
        assertEq(ComplianceFacet(address(token)).unfrozenBalanceOf(alice), 0);
    }

    /// @notice The max-freeze sentinel plus a lockup saturates, it does not panic
    /// @dev `setFrozenTokens(w, type(uint256).max)` is the freeze-everything
    ///      idiom, and a distribution or admin lockup can sit on top of it.
    ///      A checked add would overflow and revert with a panic — and
    ///      `getFrozenTokens`, `unfrozenBalanceOf`, `canTransfer` and
    ///      `whyBlocked` all read this total, so the panic would break the four
    ///      views ERC-7943 says must never revert.
    function test_maxFreezePlusLockupSaturatesInsteadOfReverting() public {
        FreezeFacet(address(token)).setFrozenTokens(alice, type(uint256).max);
        LockupFacet(address(token)).addLockup(alice, 5e18, uint64(block.timestamp + 1 days), "on top");

        // Both of these read the composed total; a checked overflow would
        // panic here instead of saturating, and these two views are among the
        // four ERC-7943 says must never revert.
        assertEq(ComplianceFacet(address(token)).getFrozenTokens(alice), type(uint256).max);
        assertEq(ComplianceFacet(address(token)).unfrozenBalanceOf(alice), 0);
    }

    /// @notice Lockups are bounded, so the total stays affordable to compute
    /// @dev An unbounded array would let a compliance officer price a holder
    ///      out of transferring — a restriction by accident rather than by
    ///      decision.
    function test_lockupsAreBounded() public {
        for (uint256 i = 0; i < 32; i++) {
            LockupFacet(address(token)).addLockup(alice, 1e18, uint64(block.timestamp + 1 days), "x");
        }
        vm.expectRevert(abi.encodeWithSelector(IErrors.RuleLimitExceeded.selector, 32, 32));
        LockupFacet(address(token)).addLockup(alice, 1e18, uint64(block.timestamp + 1 days), "one too many");
    }

    // ── access ──────────────────────────────────────────────────────────────

    function test_lockupRequiresANote() public {
        vm.expectRevert(IErrors.ReasonRequired.selector);
        LockupFacet(address(token)).addLockup(alice, 1e18, uint64(block.timestamp + 1 days), "");
    }

    function test_onlyComplianceOfficerMayFreeze() public {
        vm.prank(alice);
        vm.expectRevert();
        FreezeFacet(address(token)).setFrozenTokens(alice, 0);
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _install() internal {
        FreezeFacet f = new FreezeFacet();
        LockupFacet l = new LockupFacet();
        ComplianceFacet c = new ComplianceFacet();

        bytes4[] memory fs = new bytes4[](2);
        fs[0] = FreezeFacet.setFrozenTokens.selector;
        fs[1] = FreezeFacet.adminFrozenOf.selector;

        bytes4[] memory ls = new bytes4[](5);
        ls[0] = LockupFacet.addLockup.selector;
        ls[1] = LockupFacet.clearLockups.selector;
        ls[2] = LockupFacet.releaseExpired.selector;
        ls[3] = LockupFacet.lockupCount.selector;
        ls[4] = LockupFacet.lockedAmountOf.selector;

        bytes4[] memory cs = new bytes4[](6);
        cs[0] = ComplianceFacet.beforeUpdate.selector;
        cs[1] = ComplianceFacet.afterUpdate.selector;
        cs[2] = ComplianceFacet.getFrozenTokens.selector;
        cs[3] = ComplianceFacet.unfrozenBalanceOf.selector;
        cs[4] = ComplianceFacet.setIdentityRegistry.selector;
        cs[5] = ComplianceFacet.identityRegistry.selector;

        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](3);
        cuts[0] = IDiamond.FacetCut(address(f), IDiamond.FacetCutAction.Add, fs);
        cuts[1] = IDiamond.FacetCut(address(l), IDiamond.FacetCutAction.Add, ls);
        cuts[2] = IDiamond.FacetCut(address(c), IDiamond.FacetCutAction.Add, cs);
        DiamondCutFacet(address(token)).diamondCut(cuts, address(0), "");
    }

    function _grant(bytes32 role) internal {
        bytes32 rolesSlot = keccak256("urwa.storage.roles.v1");
        bytes32 inner = keccak256(abi.encode(role, uint256(rolesSlot)));
        vm.store(address(token), keccak256(abi.encode(address(this), uint256(inner))), bytes32(uint256(1)));
    }

    function _seed(address to, uint256 amount) internal {
        bytes32 slot = keccak256("urwa.storage.core.v1");
        vm.store(address(token), keccak256(abi.encode(to, uint256(slot))), bytes32(amount));
        vm.store(address(token), bytes32(uint256(slot) + 3), bytes32(amount));
    }
}
