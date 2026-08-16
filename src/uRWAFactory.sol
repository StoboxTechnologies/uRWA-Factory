// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ComplianceFacet} from "./facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "./facets/DiamondCutFacet.sol";
import {MonetaryFacet} from "./facets/MonetaryFacet.sol";
import {RolesFacet} from "./facets/RolesFacet.sol";
import {IDiamond} from "./interfaces/IDiamond.sol";
import {IErrors} from "./interfaces/IErrors.sol";
import {IEvents} from "./interfaces/IEvents.sol";
import {TokenParams} from "./interfaces/IuRWAFactory.sol";
import {Roles} from "./interfaces/Roles.sol";
import {Clones} from "./libraries/Clones.sol";
import {Treasury} from "./Treasury.sol";
import {uRWAToken} from "./uRWAToken.sol";

/// @title The deployer
/// @notice Permissionless. One transaction from nothing to a working compliant
///         token — after which **the factory retains no role, no key and no
///         upgrade right** over what it created.
/// @dev The deliberate departure from designs where the factory keeps admin
///      rights over everything it issues. Such a factory is a single point of
///      compromise for every token on the chain, and its operator becomes a
///      party every holder has to trust without ever having chosen to.
contract uRWAFactory is IErrors {
    address public immutable cutFacet;
    address public immutable treasuryImplementation;
    address public immutable deployer;

    /// @notice The deployment fee. **Zero in the open distribution.**
    /// @dev Readable before a transaction. The claim is that no fee is charged
    ///      today and any fee is visible on chain — not that it is free
    ///      forever, which nothing in the code could enforce.
    uint256 public fee;
    address public feeToken;

    address public admin;

    mapping(bytes32 => IDiamond.FacetCut[]) private _packages;
    bytes32[] private _packageIds;
    mapping(bytes32 => address[]) private _presetRules;
    mapping(bytes32 => bytes32[]) private _presetGroups;
    bytes32[] private _presetIds;

    mapping(address => bool) public isFactoryIssued;
    mapping(address => address[]) private _byIssuer;
    address[] private _all;

    constructor(address cutFacet_, address treasuryImplementation_) {
        cutFacet = cutFacet_;
        treasuryImplementation = treasuryImplementation_;
        deployer = msg.sender;
        admin = msg.sender;
    }

    // ── creation ────────────────────────────────────────────────────────────

    /// @notice Deploy a token, its treasury and its rule set, then let go
    function createToken(TokenParams calldata params, bytes32 packageId, address offeringRegistry)
        external
        returns (address token, address treasury)
    {
        // 1 · the diamond
        uRWAToken t = new uRWAToken(
            params.name,
            params.symbol,
            params.decimals,
            params.maxSupply,
            params.issuerAdmin,
            cutFacet,
            address(this), // the factory holds UPGRADE_ADMIN only for the length of this call
            0 // and no delay, so its own wiring cuts land immediately
        );
        token = address(t);

        // 2 · the facets
        IDiamond.FacetCut[] storage cuts = _packages[packageId];
        if (cuts.length == 0) revert FunctionNotFound(bytes4(packageId));
        _cut(token, cuts);

        // 3 · a treasury of its own, so a compromise reaches one asset
        treasury = Clones.clone(treasuryImplementation);
        Treasury(treasury).initialise(token, params.issuerAdmin, offeringRegistry);

        // 4 · wiring, then the regime
        _wire(token, treasury, offeringRegistry, params);

        // 5 · the four roles, to the four addresses given
        _grantRoles(token, params);

        // 6 · and the factory lets go
        RolesFacet(token).revokeRole(Roles.UPGRADE_ADMIN, address(this));
        RolesFacet(token).revokeRole(Roles.ISSUER_ADMIN, address(this));

        isFactoryIssued[token] = true;
        _byIssuer[msg.sender].push(token);
        _all.push(token);

        emit IEvents.TokenCreated(token, treasury, msg.sender, packageId, params.preset);
    }

    function _cut(address token, IDiamond.FacetCut[] storage cuts) private {
        IDiamond.FacetCut[] memory copy = new IDiamond.FacetCut[](cuts.length);
        for (uint256 i = 0; i < cuts.length; i++) {
            copy[i] = cuts[i];
        }
        IDiamond(token).diamondCut(copy, address(0), "");
    }

    function _wire(address token, address treasury, address offeringRegistry, TokenParams calldata params) private {
        // The constructor already gave the factory both bootstrap roles. It
        // uses them here and gives them up before this call returns, so it is
        // never an administrator of a token that outlives the transaction.
        ComplianceFacet(token).setIdentityRegistry(params.identityRegistry);
        MonetaryFacet(token).setTreasury(treasury);
        if (offeringRegistry != address(0)) MonetaryFacet(token).setOfferingRegistry(offeringRegistry);

        // The treasury holds tokens as an ordinary holder, so it is trusted
        // explicitly and visibly rather than special-cased inside the ledger.
        ComplianceFacet(token).trust(treasury, "token treasury");

        // Set last, and only upward from zero, so the wiring cuts above land
        // immediately while the token the issuer receives already has the delay
        // they asked for.
        if (params.upgradeDelay != 0) {
            DiamondCutFacet(token).setUpgradeDelay(params.upgradeDelay);
        }
    }

    function _grantRoles(address token, TokenParams calldata params) private {
        RolesFacet r = RolesFacet(token);
        r.grantRole(Roles.ISSUER_ADMIN, params.issuerAdmin);
        r.grantRole(Roles.UPGRADE_ADMIN, params.upgradeAdmin);
        r.grantRole(Roles.SUPPLY_OPERATOR, params.supplyOperator);
        r.grantRole(Roles.COMPLIANCE_OFFICER, params.complianceOfficer);
    }

    // ── packages and presets ────────────────────────────────────────────────

    function registerPackage(bytes32 id, IDiamond.FacetCut[] calldata cuts) external {
        _onlyAdmin();
        delete _packages[id];
        for (uint256 i = 0; i < cuts.length; i++) {
            _packages[id].push(cuts[i]);
        }
        _packageIds.push(id);
        emit IEvents.PackageRegistered(id);
    }

    function packageOf(bytes32 id) external view returns (IDiamond.FacetCut[] memory) {
        return _packages[id];
    }

    function packages() external view returns (bytes32[] memory) {
        return _packageIds;
    }

    function registerPreset(bytes32 id, address[] calldata rules, bytes32[] calldata groups) external {
        _onlyAdmin();
        _presetRules[id] = rules;
        _presetGroups[id] = groups;
        _presetIds.push(id);
        emit IEvents.PresetRegistered(id);
    }

    function presetOf(bytes32 id) external view returns (address[] memory rules, bytes32[] memory groups) {
        return (_presetRules[id], _presetGroups[id]);
    }

    function presets() external view returns (bytes32[] memory) {
        return _presetIds;
    }

    // ── registry ────────────────────────────────────────────────────────────

    function deploymentsOf(address issuer) external view returns (address[] memory) {
        return _byIssuer[issuer];
    }

    function allDeployments() external view returns (address[] memory) {
        return _all;
    }

    // ── fee ─────────────────────────────────────────────────────────────────

    function setFee(uint256 newFee) external {
        _onlyAdmin();
        fee = newFee;
        emit IEvents.FeeChanged(feeToken, newFee);
    }

    function setFeeToken(address newToken) external {
        _onlyAdmin();
        feeToken = newToken;
        emit IEvents.FeeChanged(newToken, fee);
    }

    function _onlyAdmin() private view {
        if (msg.sender != admin) revert NotAuthorized(msg.sender, Roles.FACTORY_ADMIN);
    }
}
