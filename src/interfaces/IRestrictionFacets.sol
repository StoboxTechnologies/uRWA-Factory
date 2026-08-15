// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Layout} from "../storage/Layout.sol";

/// @title Admin freeze
/// @notice An indefinite restriction on part of a balance, set by compliance.
interface IFreezeFacet {
    function setFrozenTokens(address account, uint256 amount) external returns (bool);
    function adminFrozenOf(address account) external view returns (uint256);
}

/// @title Dated lockups
/// @notice Restrictions that expire by timestamp — no keeper, no transaction,
///         no stale state to clean up.
interface ILockupFacet {
    function addLockup(address account, uint256 amount, uint64 unlockAt, string calldata note) external;
    function clearLockups(address account, string calldata reason) external;

    /// @notice Housekeeping only; expiry is already in effect without it
    function releaseExpired(address account) external;

    function lockupsOf(address account) external view returns (Layout.Lockup[] memory);
    function lockupCount(address account) external view returns (uint256);
    function lockedAmountOf(address account) external view returns (uint256);

    /// @notice Balance minus everything restricted, floored at zero
    function unfrozenBalanceOf(address account) external view returns (uint256);
}

/// @title Supply
/// @notice Issue into the treasury, distribute out of it, redeem back.
interface IMonetaryFacet {
    function issue(address to, uint256 amount) external;
    function redeem(uint256 amount) external;

    /// @notice Move issued supply to a holder, optionally under a lockup
    /// @dev Runs the full compliance pipeline on the distribution leg.
    function distributeFromTreasury(address to, uint256 amount, uint64 unlockAt) external;

    function setMaxSupply(uint256 newMax) external;
    function lockCap() external;
    function capLocked() external view returns (bool);

    /// @notice Cumulative issuance; monotonic, never decreases on redemption
    function totalIssued() external view returns (uint256);

    function treasury() external view returns (address);
    function setTreasury(address newTreasury) external;
    function offeringRegistry() external view returns (address);
    function setOfferingRegistry(address newRegistry) external;
}

/// @title Roles
/// @notice Four separated roles, none able to do another's work.
interface IRolesFacet {
    function grantRole(bytes32 role, address account) external;
    function revokeRole(bytes32 role, address account) external;
    function renounceRole(bytes32 role) external;
    function hasRole(bytes32 role, address account) external view returns (bool);
    function roleAdmin(bytes32 role) external view returns (bytes32);
    function getRoleMember(bytes32 role, uint256 index) external view returns (address);
    function getRoleMemberCount(bytes32 role) external view returns (uint256);
}

/// @title Emergency operations — opt-in
/// @notice Not installed by default. Installing it is a deliberate act, and its
///         absence is provable through the loupe: `facetAddress(selector)`
///         returns `address(0)`, so an investor can verify that seizure is
///         impossible rather than merely unlikely.
interface IEmergencyFacet {
    function forcedTransfer(address from, address to, uint256 amount, string calldata reason) external returns (bool);
    function forcedMint(address to, uint256 amount, string calldata reason) external;
    function forcedBurn(address from, uint256 amount, string calldata reason) external;
}

/// @title Offering entry point on the token side
interface IPurchaseFacet {
    function purchaseFrom(address investor, uint256 amount, uint64 unlockAt) external;
}
