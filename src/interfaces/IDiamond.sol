// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title EIP-2535 cut and loupe
/// @notice One facet changes the function table; the other reads it. The loupe
///         is how an outsider proves which code a deployed token runs, without
///         trusting anything we say about it.
interface IDiamond {
    enum FacetCutAction {
        Add,
        Replace,
        Remove
    }

    struct FacetCut {
        address facetAddress;
        FacetCutAction action;
        bytes4[] functionSelectors;
    }

    struct Facet {
        address facetAddress;
        bytes4[] functionSelectors;
    }

    /// @notice Add, replace or remove selectors
    /// @dev **Cannot touch the ERC-20 core.** Those selectors are registered
    ///      against the diamond itself and revert with
    ///      `CannotReplaceImmutableFunction`.
    ///
    ///      Where the issuer configured a delay, a cut is scheduled rather than
    ///      executed; call again after `upgradeDelay()` has elapsed.
    function diamondCut(FacetCut[] calldata cuts, address init, bytes calldata data) external;

    /// @notice The delay the issuer chose at deployment; `0` means immediate
    /// @dev Public because a token with no timelock and one with a seven-day
    ///      delay are materially different instruments.
    function upgradeDelay() external view returns (uint64);

    /// @notice When a scheduled cut becomes executable; `0` if not scheduled
    function scheduledAt(bytes32 cutHash) external view returns (uint64);

    // ── loupe ───────────────────────────────────────────────────────────────

    function facets() external view returns (Facet[] memory);
    function facetAddresses() external view returns (address[] memory);

    /// @notice Which facet serves a selector
    /// @dev `address(0)` proves an absent function is absent — this is how the
    ///      verifier shows that seizure is impossible on a given token.
    function facetAddress(bytes4 selector) external view returns (address);
    function facetFunctionSelectors(address facet) external view returns (bytes4[] memory);

    function supportsInterface(bytes4 interfaceId) external view returns (bool);
}
