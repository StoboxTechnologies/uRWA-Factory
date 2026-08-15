// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IDiamond} from "./IDiamond.sol";
import {OfferingParams} from "./ITreasuryAndOfferings.sol";

/// @notice Everything fixed at deployment
/// @dev `upgradeDelay` and `installEmergencyFacet` have no default in the
///      console: each is a governance decision an issuer must make knowingly,
///      and a pre-selected answer would be taken as advice.
struct TokenParams {
    string name;
    string symbol;
    uint8 decimals;
    uint256 maxSupply; // 0 = unlimited
    bool lockCap; // irreversible
    bytes32 preset; // regime from the factory's preset registry
    address identityRegistry;
    uint64 upgradeDelay; // 0 = immediate
    bool installEmergencyFacet;
    address issuerAdmin;
    address upgradeAdmin;
    address supplyOperator;
    address complianceOfficer;
}

/// @title The deployer
/// @notice Permissionless. One transaction from nothing to a working compliant
///         token — after which **the factory retains no role, no key and no
///         upgrade right** over what it created.
/// @dev That is the deliberate departure from designs where the factory keeps
///      admin rights: such a factory is a single point of compromise for every
///      token on the chain.
interface IuRWAFactory {
    function createToken(TokenParams calldata params) external returns (address token, address treasury);

    function createTokenWithOffering(TokenParams calldata params, OfferingParams calldata offering)
        external
        returns (address token, address treasury, uint256 offeringId);

    // ── packages and presets ────────────────────────────────────────────────

    function registerPackage(bytes32 id, IDiamond.FacetCut[] calldata cuts) external;
    function packageOf(bytes32 id) external view returns (IDiamond.FacetCut[] memory);
    function registerPreset(bytes32 id, address[] calldata rules, bytes32[] calldata groups) external;
    function presetOf(bytes32 id) external view returns (address[] memory rules, bytes32[] memory groups);

    // ── registry ────────────────────────────────────────────────────────────

    /// @notice Was this token issued by this factory
    /// @dev Answerable by anyone, with no account and no cooperation from the
    ///      deployer. Provenance has to be checkable by people who do not trust
    ///      either of us.
    function isFactoryIssued(address token) external view returns (bool);
    function deploymentsOf(address issuer) external view returns (address[] memory);
    function allDeployments() external view returns (address[] memory);

    // ── fee ─────────────────────────────────────────────────────────────────

    /// @notice The deployment fee; zero in the open distribution
    /// @dev Readable before a transaction. The claim is *no fee is charged
    ///      today, and any fee is visible on chain* — not that it is free
    ///      forever, which nothing in the code could enforce.
    function fee() external view returns (uint256);
    function feeToken() external view returns (address);
    function setFee(uint256 newFee) external;
    function setFeeToken(address newToken) external;
}
