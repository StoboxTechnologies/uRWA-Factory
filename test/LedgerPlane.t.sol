// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IuRWAToken} from "../src/interfaces/IuRWAToken.sol";

/// @dev A facet that would rewrite balances if it could ever be installed over
///      the ERC-20 core. It exists to be refused.
contract HostileFacet {
    function transfer(address, uint256) external pure returns (bool) {
        return true; // steals nothing because it is never reachable
    }

    function balanceOf(address) external pure returns (uint256) {
        return type(uint256).max;
    }
}

/// @dev The minimum compliance facet: allows everything. Used to prove the
///      token works when one is installed, and fails closed when none is.
contract PermissiveCompliance {
    function beforeUpdate(address, address, uint256) external pure {}
}

/// @dev Refuses everything, with the standard error.
contract RefusingCompliance {
    function beforeUpdate(address from, address to, uint256 amount) external pure {
        revert IErrors.ERC7943CannotTransfer(from, to, amount);
    }
}

/// @title L4.1 and L4.3 — the two properties the ledger plane exists to give
contract LedgerPlaneTest is Test {
    uRWAToken token;
    DiamondCutFacet cutFacet;
    HostileFacet hostile;
    PermissiveCompliance permissive;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);

    function setUp() public {
        cutFacet = new DiamondCutFacet();
        token = new uRWAToken(
            "Manhattan Office Tower", "MOTT", 18, 10_000_000e18, address(this), address(cutFacet), address(this), 0
        );
        hostile = new HostileFacet();
        permissive = new PermissiveCompliance();
        _install(address(permissive), PermissiveCompliance.beforeUpdate.selector);
        _seed(alice, 1000e18);
    }

    // ── L4.1 · the ERC-20 core cannot be cut ────────────────────────────────

    /// @notice A cut cannot replace an ERC-20 selector
    /// @dev The single assertion the entire three-plane architecture rests on.
    ///      If this ever passes, a compromised upgrade admin can rewrite every
    ///      balance in the token.
    function test_cannotReplaceAnyErc20Selector() public {
        bytes4[7] memory core = [
            IuRWAToken.transfer.selector,
            IuRWAToken.transferFrom.selector,
            IuRWAToken.balanceOf.selector,
            IuRWAToken.totalSupply.selector,
            IuRWAToken.approve.selector,
            IuRWAToken.allowance.selector,
            IuRWAToken.permit.selector
        ];
        for (uint256 i = 0; i < core.length; i++) {
            vm.expectRevert(abi.encodeWithSelector(IErrors.CannotReplaceImmutableFunction.selector, core[i]));
            _cut(address(hostile), core[i], IDiamond.FacetCutAction.Replace);
        }
    }

    /// @notice Nor remove one
    function test_cannotRemoveAnyErc20Selector() public {
        vm.expectRevert(
            abi.encodeWithSelector(IErrors.CannotReplaceImmutableFunction.selector, IuRWAToken.transfer.selector)
        );
        _cut(address(0), IuRWAToken.transfer.selector, IDiamond.FacetCutAction.Remove);
    }

    /// @notice Nor add over one, which would be a replace in disguise
    /// @dev The obvious way around the rule, if the rule only checked Replace.
    function test_cannotAddOverAnErc20Selector() public {
        vm.expectRevert(
            abi.encodeWithSelector(IErrors.CannotReplaceImmutableFunction.selector, IuRWAToken.balanceOf.selector)
        );
        _cut(address(hostile), IuRWAToken.balanceOf.selector, IDiamond.FacetCutAction.Add);
    }

    /// @notice Balances survive an upgrade admin installing whatever they like
    /// @dev `L4.8`, stated as an outcome rather than a mechanism: the attacker
    ///      succeeds at every step they are allowed, and the balance is
    ///      unchanged at the end.
    function test_hostileFacetCannotChangeABalance() public {
        assertEq(token.balanceOf(alice), 1000e18);

        // Everything the attacker *can* do: install a facet on a free selector.
        _cut(address(hostile), bytes4(keccak256("somethingElse()")), IDiamond.FacetCutAction.Add);

        // And what they cannot.
        vm.expectRevert();
        _cut(address(hostile), IuRWAToken.balanceOf.selector, IDiamond.FacetCutAction.Replace);

        assertEq(token.balanceOf(alice), 1000e18, "a balance changed");
    }

    // ── L4.3 · fail closed ──────────────────────────────────────────────────

    /// @notice With no compliance facet, every transfer reverts
    /// @dev Not by a flag, and not by a check anyone wrote. The router does not
    ///      recognise `beforeUpdate`, so the call out fails and the transfer
    ///      never reaches the balance update.
    function test_removingComplianceHaltsTransfers() public {
        vm.prank(alice);
        token.transfer(bob, 1e18);
        assertEq(token.balanceOf(bob), 1e18);

        _cut(address(0), PermissiveCompliance.beforeUpdate.selector, IDiamond.FacetCutAction.Remove);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1e18);

        assertEq(token.balanceOf(bob), 1e18, "value moved with no compliance installed");
    }

    /// @notice A refusing rule stops the transfer and its reason survives
    /// @dev The revert data is re-raised unchanged, so a holder sees which rule
    ///      refused rather than a generic failure.
    function test_refusalReachesTheCallerIntact() public {
        RefusingCompliance refusing = new RefusingCompliance();
        _cut(address(refusing), PermissiveCompliance.beforeUpdate.selector, IDiamond.FacetCutAction.Replace);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ERC7943CannotTransfer.selector, alice, bob, 1e18));
        token.transfer(bob, 1e18);
    }

    /// @notice An unknown selector reverts rather than silently succeeding
    /// @dev A diamond that returns empty data for an unrecognised call is one
    ///      where removing a facet makes calls appear to work.
    function test_unknownSelectorReverts() public {
        (bool ok,) = address(token).call(abi.encodeWithSignature("neverDeclared()"));
        assertFalse(ok, "an unknown selector did not revert");
    }

    // ── the upgrade delay ───────────────────────────────────────────────────

    /// @notice With a delay set, the first call schedules and changes nothing
    /// @dev The property a holder relies on: an upgrade becomes public before
    ///      it takes effect, leaving a window to act on it.
    function test_delayedCutSchedulesBeforeItExecutes() public {
        DiamondCutFacet facet = new DiamondCutFacet();
        uRWAToken delayed = new uRWAToken("Delayed", "DLY", 18, 0, address(this), address(facet), address(this), 7 days);

        bytes4 sel = bytes4(keccak256("somethingNew()"));
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = sel;
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(address(hostile), IDiamond.FacetCutAction.Add, sels);

        DiamondCutFacet(address(delayed)).diamondCut(cuts, address(0), "");
        assertEq(delayed.facetAddress(sel), address(0), "a delayed cut took effect immediately");

        bytes32 cutHash = keccak256(abi.encode(cuts, address(0), bytes("")));
        assertEq(DiamondCutFacet(address(delayed)).scheduledAt(cutHash), uint64(block.timestamp + 7 days));

        // Too early.
        vm.expectRevert();
        DiamondCutFacet(address(delayed)).diamondCut(cuts, address(0), "");

        vm.warp(block.timestamp + 7 days);
        DiamondCutFacet(address(delayed)).diamondCut(cuts, address(0), "");
        assertEq(delayed.facetAddress(sel), address(hostile), "the cut did not execute after its delay");
    }

    /// @notice A delay does not make the ERC-20 core cuttable, only slower
    function test_delayDoesNotWeakenImmutability() public {
        DiamondCutFacet facet = new DiamondCutFacet();
        uRWAToken delayed = new uRWAToken("Delayed", "DLY", 18, 0, address(this), address(facet), address(this), 7 days);

        bytes4[] memory sels = new bytes4[](1);
        sels[0] = IuRWAToken.balanceOf.selector;
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(address(hostile), IDiamond.FacetCutAction.Replace, sels);

        // Scheduling is allowed; executing is not.
        DiamondCutFacet(address(delayed)).diamondCut(cuts, address(0), "");
        vm.warp(block.timestamp + 7 days);
        vm.expectRevert(
            abi.encodeWithSelector(IErrors.CannotReplaceImmutableFunction.selector, IuRWAToken.balanceOf.selector)
        );
        DiamondCutFacet(address(delayed)).diamondCut(cuts, address(0), "");
    }

    /// @notice Only the upgrade admin may cut
    function test_onlyUpgradeAdminMayCut() public {
        bytes4[] memory sels = new bytes4[](1);
        sels[0] = bytes4(keccak256("x()"));
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(address(hostile), IDiamond.FacetCutAction.Add, sels);

        vm.prank(alice);
        vm.expectRevert();
        DiamondCutFacet(address(token)).diamondCut(cuts, address(0), "");
    }

    // ── conformance ─────────────────────────────────────────────────────────

    function test_advertisesErc7943AndErc20() public view {
        assertTrue(token.supportsInterface(0x3edbb4c4), "ERC-7943 not advertised");
        assertTrue(token.supportsInterface(0x36372b07), "ERC-20 not advertised");
        assertTrue(token.supportsInterface(0x01ffc9a7), "ERC-165 not advertised");
    }

    /// @notice The loupe proves which code serves each call
    function test_loupeReportsTheCoreAsTheDiamondItself() public view {
        assertEq(token.facetAddress(IuRWAToken.transfer.selector), address(token));
        assertEq(token.facetAddress(PermissiveCompliance.beforeUpdate.selector), address(permissive));
        assertEq(token.facetAddress(bytes4(keccak256("neverDeclared()"))), address(0));
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _cut(address facet, bytes4 selector, IDiamond.FacetCutAction action) internal {
        bytes4[] memory sel = new bytes4[](1);
        sel[0] = selector;
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(facet, action, sel);
        DiamondCutFacet(address(token)).diamondCut(cuts, address(0), "");
    }

    function _install(address facet, bytes4 selector) internal {
        _cut(facet, selector, IDiamond.FacetCutAction.Add);
    }

    /// @dev No monetary facet exists yet, so balances are written directly.
    ///      Replaced by `issue` once `MonetaryFacet` lands.
    function _seed(address to, uint256 amount) internal {
        bytes32 slot = keccak256("urwa.storage.core.v1");
        bytes32 balanceSlot = keccak256(abi.encode(to, uint256(slot)));
        vm.store(address(token), balanceSlot, bytes32(amount));
        bytes32 totalSlot = bytes32(uint256(slot) + 3);
        vm.store(address(token), totalSlot, bytes32(amount));
    }
}
