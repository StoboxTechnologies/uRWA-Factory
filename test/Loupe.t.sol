// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IuRWAToken} from "../src/interfaces/IuRWAToken.sol";

/// @dev Two selectors, so a facet can lose one and keep the other.
contract TwoWayFacet {
    function alpha() external pure returns (uint256) {
        return 1;
    }

    function beta() external pure returns (uint256) {
        return 2;
    }
}

/// @dev The same two selectors, from a different address.
contract RivalFacet {
    function alpha() external pure returns (uint256) {
        return 3;
    }

    function beta() external pure returns (uint256) {
        return 4;
    }
}

/// @title `L4.16` — the loupe agrees with the router
/// @notice The loupe is the only thing standing between "this token is
///         compliant" as a claim and as a fact. Everything an outsider can
///         check about a deployed token — which facets exist, that seizure is
///         absent, that the ledger cannot be cut — is read through it.
/// @dev So it is held to the router rather than to itself: for every facet the
///      loupe reports, every selector it claims must actually route there, and
///      every selector that routes must be reported exactly once. A loupe that
///      merely returns something plausible is worse than none, because it is
///      believed.
contract LoupeTest is Test {
    uRWAToken token;
    DiamondCutFacet cutFacet;
    TwoWayFacet two;
    RivalFacet rival;

    function setUp() public {
        cutFacet = new DiamondCutFacet();
        token =
            new uRWAToken("Manhattan Office Tower", "MOTT", 18, 0, address(this), address(cutFacet), address(this), 0);
        two = new TwoWayFacet();
        rival = new RivalFacet();
    }

    // ── the report matches the router ───────────────────────────────────────

    /// @notice `L4.16` — every reported selector routes where the report says
    function test_theReportAgreesWithTheRouterFromTheStart() public view {
        _assertConsistent();
    }

    /// @notice And still does after adding, replacing and removing
    /// @dev The three operations that can put the two out of step. Bookkeeping
    ///      that is only maintained on the way in drifts on the way out, and
    ///      nothing in the router notices.
    function test_theReportSurvivesEveryKindOfCut() public {
        _cut(address(two), TwoWayFacet.alpha.selector, IDiamond.FacetCutAction.Add);
        _cut(address(two), TwoWayFacet.beta.selector, IDiamond.FacetCutAction.Add);
        _assertConsistent();

        _cut(address(rival), TwoWayFacet.alpha.selector, IDiamond.FacetCutAction.Replace);
        _assertConsistent();

        _cut(address(0), TwoWayFacet.beta.selector, IDiamond.FacetCutAction.Remove);
        _assertConsistent();
    }

    /// @notice A replaced selector leaves the facet that used to serve it
    /// @dev Otherwise two facets both claim it, and an outsider diffing the
    ///      report against a published package sees code that is not running.
    function test_aReplacedSelectorIsClaimedByOneFacetOnly() public {
        _cut(address(two), TwoWayFacet.alpha.selector, IDiamond.FacetCutAction.Add);
        _cut(address(rival), TwoWayFacet.alpha.selector, IDiamond.FacetCutAction.Replace);

        assertEq(token.facetFunctionSelectors(address(two)).length, 0, "the old facet still claims it");
        bytes4[] memory now_ = token.facetFunctionSelectors(address(rival));
        assertEq(now_.length, 1);
        assertEq(now_[0], TwoWayFacet.alpha.selector);
        assertEq(token.facetAddress(TwoWayFacet.alpha.selector), address(rival));
    }

    /// @notice A facet serving nothing is not listed as installed
    function test_anEmptiedFacetLeavesTheReport() public {
        _cut(address(two), TwoWayFacet.alpha.selector, IDiamond.FacetCutAction.Add);
        assertTrue(_listed(address(two)), "not installed");

        _cut(address(0), TwoWayFacet.alpha.selector, IDiamond.FacetCutAction.Remove);
        assertFalse(_listed(address(two)), "an address no call can reach is still reported");
        assertEq(token.facetAddress(TwoWayFacet.alpha.selector), address(0));
    }

    /// @notice Losing one selector does not unlist a facet that still serves another
    function test_aFacetKeepsItsPlaceWhileItStillServes() public {
        _cut(address(two), TwoWayFacet.alpha.selector, IDiamond.FacetCutAction.Add);
        _cut(address(two), TwoWayFacet.beta.selector, IDiamond.FacetCutAction.Add);
        _cut(address(0), TwoWayFacet.alpha.selector, IDiamond.FacetCutAction.Remove);

        assertTrue(_listed(address(two)), "unlisted while it still serves beta");
        assertEq(token.facetFunctionSelectors(address(two)).length, 1);
        assertEq(token.facetAddress(TwoWayFacet.beta.selector), address(two));
    }

    // ── what the loupe proves about the core ────────────────────────────────

    /// @notice The cut facet reports every selector it serves
    /// @dev It served five and reported one for a while. The upgrade machinery
    ///      is the last facet whose surface should be understated.
    function test_theCutFacetReportsAllOfIt() public view {
        bytes4[] memory sel = token.facetFunctionSelectors(address(cutFacet));
        assertEq(sel.length, 5, "the upgrade machinery is under-reported");
        assertEq(token.facetAddress(DiamondCutFacet.setUpgradeDelay.selector), address(cutFacet));
        assertEq(token.facetAddress(DiamondCutFacet.cancelCut.selector), address(cutFacet));
    }

    /// @notice The immutable set is enumerable, and every member proves itself
    /// @dev A selector served by the token's own address is one no cut can
    ///      reach. That is the whole immutability argument, and this is how it
    ///      is read from outside rather than taken on trust.
    function test_theImmutableSetIsReadableFromOutside() public view {
        bytes4[] memory core = token.facetFunctionSelectors(address(token));
        assertEq(core.length, 19, "fourteen ledger selectors and five loupe");

        for (uint256 i = 0; i < core.length; i++) {
            assertEq(token.facetAddress(core[i]), address(token), "not served by the diamond itself");
        }
        assertEq(token.facetAddress(IuRWAToken.transfer.selector), address(token));
        assertEq(token.facetAddress(IDiamond.facets.selector), address(token));
    }

    /// @notice The loupe cannot be cut out
    /// @dev A loupe an admin can remove proves nothing on the day somebody
    ///      needs it to. It is in the ledger plane for the same reason
    ///      `balanceOf` is.
    function test_theLoupeCannotBeRemoved() public {
        vm.expectRevert(
            abi.encodeWithSelector(IErrors.CannotReplaceImmutableFunction.selector, IDiamond.facets.selector)
        );
        _cut(address(0), IDiamond.facets.selector, IDiamond.FacetCutAction.Remove);

        vm.expectRevert(
            abi.encodeWithSelector(IErrors.CannotReplaceImmutableFunction.selector, IDiamond.facetAddress.selector)
        );
        _cut(address(two), IDiamond.facetAddress.selector, IDiamond.FacetCutAction.Replace);
    }

    /// @notice An absent function is provably absent
    /// @dev The verifier's central claim about a token without the emergency
    ///      facet: not "we did not install seizure" but "no code answers it".
    function test_anAbsentFunctionIsProvablyAbsent() public view {
        bytes4 forcedTransfer = bytes4(keccak256("forcedTransfer(address,address,uint256,string)"));
        assertEq(token.facetAddress(forcedTransfer), address(0));
        assertEq(token.facetFunctionSelectors(address(0)).length, 0);
    }

    /// @notice `facetAddresses()` and `facets()` describe the same diamond
    function test_theTwoReportsCannotDisagree() public {
        _cut(address(two), TwoWayFacet.alpha.selector, IDiamond.FacetCutAction.Add);

        address[] memory addrs = token.facetAddresses();
        IDiamond.Facet[] memory report = token.facets();
        assertEq(addrs.length, report.length, "one report lists a facet the other does not");
        for (uint256 i = 0; i < addrs.length; i++) {
            assertEq(addrs[i], report[i].facetAddress);
        }
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    /// @dev The invariant itself: the report and the router, checked against
    ///      each other in both directions.
    function _assertConsistent() internal view {
        IDiamond.Facet[] memory report = token.facets();
        for (uint256 i = 0; i < report.length; i++) {
            assertTrue(report[i].facetAddress != address(0), "a facet at the zero address");
            assertTrue(report[i].functionSelectors.length != 0, "a facet serving nothing");

            for (uint256 j = 0; j < report[i].functionSelectors.length; j++) {
                bytes4 sel = report[i].functionSelectors[j];
                assertEq(token.facetAddress(sel), report[i].facetAddress, "the router disagrees");
                assertEq(_claims(sel), 1, "a selector claimed by more than one facet");
            }
        }
    }

    /// @dev How many facets in the report claim this selector.
    function _claims(bytes4 sel) internal view returns (uint256 n) {
        IDiamond.Facet[] memory report = token.facets();
        for (uint256 i = 0; i < report.length; i++) {
            for (uint256 j = 0; j < report[i].functionSelectors.length; j++) {
                if (report[i].functionSelectors[j] == sel) n++;
            }
        }
    }

    function _listed(address facet) internal view returns (bool) {
        address[] memory addrs = token.facetAddresses();
        for (uint256 i = 0; i < addrs.length; i++) {
            if (addrs[i] == facet) return true;
        }
        return false;
    }

    function _cut(address facet, bytes4 selector, IDiamond.FacetCutAction action) internal {
        bytes4[] memory sel = new bytes4[](1);
        sel[0] = selector;
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(facet, action, sel);
        DiamondCutFacet(address(token)).diamondCut(cuts, address(0), "");
    }
}
