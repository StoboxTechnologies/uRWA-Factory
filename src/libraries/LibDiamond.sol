// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDiamond} from "../interfaces/IDiamond.sol";
import {IErrors} from "../interfaces/IErrors.sol";
import {IEvents} from "../interfaces/IEvents.sol";
import {Layout} from "../storage/Layout.sol";

/// @title The function table, and the one rule that makes the architecture work
/// @notice A selector whose facet is the diamond itself is **immutable**: no
///         cut can replace or remove it. The ERC-20 entry points are registered
///         that way at deployment, so the ledger plane is immutable by
///         construction rather than by policy.
/// @dev This is the whole three-plane split in about thirty lines. Everything
///      else in the system — replaceable policy, extensible claims, a
///      compliance bug that stops trading without corrupting supply — follows
///      from `_enforceMutable` refusing.
library LibDiamond {
    bytes32 internal constant DIAMOND_SLOT = keccak256("urwa.storage.diamond.v1");

    struct DiamondStorage {
        mapping(bytes4 => address) facetOf;
        mapping(address => bytes4[]) selectorsOf;
        address[] facetAddresses;
        mapping(bytes4 => bool) supportedInterface;
    }

    function s() internal pure returns (DiamondStorage storage d) {
        bytes32 slot = DIAMOND_SLOT;
        assembly {
            d.slot := slot
        }
    }

    // ── the immutability rule ───────────────────────────────────────────────

    /// @notice Is this selector served by the diamond itself
    /// @dev The test for immutability. Nothing else distinguishes an immutable
    ///      selector from a replaceable one, which is deliberate: there is no
    ///      flag an admin could clear.
    function isImmutable(bytes4 selector) internal view returns (bool) {
        return s().facetOf[selector] == address(this);
    }

    function _enforceMutable(bytes4 selector) private view {
        if (isImmutable(selector)) {
            revert IErrors.CannotReplaceImmutableFunction(selector);
        }
    }

    /// @notice Register selectors against the diamond itself, permanently
    /// @dev Called once, from the constructor. There is no function that undoes
    ///      it, because a function that undid it would be the vulnerability the
    ///      whole design exists to remove.
    function registerImmutable(bytes4[] memory selectors) internal {
        DiamondStorage storage d = s();
        // The diamond appears in its own loupe report. An outsider reading
        // `facets()` sees which selectors the core serves, and a selector
        // served by the diamond's own address is one no cut can reach — that
        // is how immutability is proven from outside rather than asserted.
        _track(d, address(this));
        for (uint256 i = 0; i < selectors.length; i++) {
            d.facetOf[selectors[i]] = address(this);
            d.selectorsOf[address(this)].push(selectors[i]);
        }
    }

    // ── cutting ─────────────────────────────────────────────────────────────

    function cut(IDiamond.FacetCut[] memory cuts) internal {
        for (uint256 i = 0; i < cuts.length; i++) {
            IDiamond.FacetCut memory c = cuts[i];
            if (c.action == IDiamond.FacetCutAction.Add) {
                _add(c.facetAddress, c.functionSelectors);
            } else if (c.action == IDiamond.FacetCutAction.Replace) {
                _replace(c.facetAddress, c.functionSelectors);
            } else {
                _remove(c.functionSelectors);
            }
        }
    }

    function _add(address facet, bytes4[] memory selectors) private {
        if (facet == address(0)) revert IErrors.ZeroAddress();
        DiamondStorage storage d = s();
        for (uint256 i = 0; i < selectors.length; i++) {
            bytes4 sel = selectors[i];
            // Adding over an existing selector is a replace in disguise, and
            // must not be a way around the rule — nor a way around the loupe's
            // bookkeeping. `_enforceMutable` stops it overwriting the core;
            // `_untrack` takes the selector off whatever facet used to serve it,
            // exactly as `_replace` does, so the report never claims one
            // selector for two facets or lists a facet that serves nothing.
            if (d.facetOf[sel] != address(0)) {
                _enforceMutable(sel);
                _untrack(d, d.facetOf[sel], sel);
            }
            _track(d, facet);
            d.facetOf[sel] = facet;
            d.selectorsOf[facet].push(sel);
        }
    }

    function _replace(address facet, bytes4[] memory selectors) private {
        if (facet == address(0)) revert IErrors.ZeroAddress();
        DiamondStorage storage d = s();
        for (uint256 i = 0; i < selectors.length; i++) {
            bytes4 sel = selectors[i];
            _enforceMutable(sel);
            _untrack(d, d.facetOf[sel], sel);
            _track(d, facet);
            d.facetOf[sel] = facet;
            d.selectorsOf[facet].push(sel);
        }
    }

    function _remove(bytes4[] memory selectors) private {
        DiamondStorage storage d = s();
        for (uint256 i = 0; i < selectors.length; i++) {
            bytes4 sel = selectors[i];
            _enforceMutable(sel);
            _untrack(d, d.facetOf[sel], sel);
            d.facetOf[sel] = address(0);
        }
    }

    function _track(DiamondStorage storage d, address facet) private {
        if (d.selectorsOf[facet].length == 0) {
            d.facetAddresses.push(facet);
        }
    }

    /// @notice Take a selector off the facet that used to serve it
    /// @dev Without this the loupe keeps reporting a selector after it has been
    ///      replaced or removed, and an outsider reading `facets()` is told
    ///      something the router would contradict. The loupe exists to be
    ///      believed by people who cannot ask us, so it has to be maintained on
    ///      the way out as well as the way in.
    function _untrack(DiamondStorage storage d, address facet, bytes4 sel) private {
        if (facet == address(0)) return;
        bytes4[] storage owned = d.selectorsOf[facet];
        for (uint256 i = 0; i < owned.length; i++) {
            if (owned[i] != sel) continue;
            owned[i] = owned[owned.length - 1];
            owned.pop();
            break;
        }
        if (owned.length != 0) return;

        // A facet serving nothing is not installed. Leaving it in the list
        // would show an address in the loupe report that no call can reach.
        address[] storage addrs = d.facetAddresses;
        for (uint256 i = 0; i < addrs.length; i++) {
            if (addrs[i] != facet) continue;
            addrs[i] = addrs[addrs.length - 1];
            addrs.pop();
            break;
        }
    }

    // ── the delay ───────────────────────────────────────────────────────────

    /// @notice Schedule a cut, or report that it is ready
    /// @dev With `delay == 0` nothing is scheduled at all, rather than being
    ///      scheduled for now. The two would differ by one block, which is the
    ///      kind of near-equality that produces bugs.
    /// @return ready True when the caller may execute the cut immediately
    function scheduleOrCheck(bytes32 cutHash) internal returns (bool ready) {
        Layout.UpgradeStorage storage u = Layout.upgrade();
        if (u.delay == 0) return true;

        uint64 at = u.scheduledAt[cutHash];
        if (at == 0) {
            uint64 executableAt = uint64(block.timestamp) + u.delay;
            u.scheduledAt[cutHash] = executableAt;
            emit IEvents.UpgradeScheduled(cutHash, executableAt);
            return false;
        }
        if (block.timestamp < at) {
            revert IErrors.UpgradeNotReady(cutHash, at);
        }
        u.scheduledAt[cutHash] = 0;
        emit IEvents.UpgradeExecuted(cutHash);
        return true;
    }
}
