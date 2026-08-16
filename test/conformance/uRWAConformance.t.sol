// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {ERC7943Conformance} from "./ERC7943Conformance.sol";
import {uRWAToken} from "../../src/uRWAToken.sol";
import {ComplianceFacet} from "../../src/facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "../../src/facets/DiamondCutFacet.sol";
import {FreezeFacet} from "../../src/facets/RestrictionFacets.sol";
import {IDiamond} from "../../src/interfaces/IDiamond.sol";
import {Claim, IIdentityRegistry} from "../../src/interfaces/IIdentityRegistry.sol";
import {Roles} from "../../src/interfaces/Roles.sol";

/// @dev Eligibility the binding steers: enrolled wallets pass, others do not.
contract Eligibility is IIdentityRegistry {
    mapping(address => bool) public enrolled;

    function enrol(address w) external {
        enrolled[w] = true;
    }

    function subjectOf(address w) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(w));
    }

    function isActive(address w) external view returns (bool) {
        return enrolled[w];
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        return true;
    }
}

/// @title This repository's token, judged by its own kit
/// @notice The kit is written for strangers; the first stranger is us. The
///         default token binds with **no force authority**, because seizure is
///         not installed by default — the kit skips that group, and the loupe
///         proves the absence on chain.
contract uRWAConformanceTest is ERC7943Conformance {
    uRWAToken internal urwa;
    Eligibility internal eligibility;

    address internal holder = address(0xA11CE);
    address internal receiver = address(0xB0B);
    address internal outsider = address(0x0DD);
    address internal officer = address(0x0FF1CE);

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        urwa = new uRWAToken("Conformant", "CNF", 18, 0, address(this), address(cutFacet), address(this), 0);
        eligibility = new Eligibility();

        ComplianceFacet compliance = new ComplianceFacet();
        FreezeFacet freeze = new FreezeFacet();

        bytes4[] memory cs = new bytes4[](8);
        cs[0] = ComplianceFacet.beforeUpdate.selector;
        cs[1] = ComplianceFacet.afterUpdate.selector;
        cs[2] = ComplianceFacet.canSend.selector;
        cs[3] = ComplianceFacet.canReceive.selector;
        cs[4] = ComplianceFacet.canTransfer.selector;
        cs[5] = ComplianceFacet.getFrozenTokens.selector;
        cs[6] = ComplianceFacet.setIdentityRegistry.selector;
        cs[7] = ComplianceFacet.unfrozenBalanceOf.selector;
        bytes4[] memory fs = new bytes4[](1);
        fs[0] = FreezeFacet.setFrozenTokens.selector;

        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](2);
        cuts[0] = IDiamond.FacetCut(address(compliance), IDiamond.FacetCutAction.Add, cs);
        cuts[1] = IDiamond.FacetCut(address(freeze), IDiamond.FacetCutAction.Add, fs);
        DiamondCutFacet(address(urwa)).diamondCut(cuts, address(0), "");

        ComplianceFacet(address(urwa)).setIdentityRegistry(address(eligibility));

        eligibility.enrol(holder);
        eligibility.enrol(receiver);
        _grantOfficer(officer);
        _seed(holder, 10e18);
    }

    // ── the kit's hooks ─────────────────────────────────────────────────────

    function token() internal view override returns (address) {
        return address(urwa);
    }

    function eligibleHolder() internal view override returns (address) {
        return holder;
    }

    function eligibleReceiver() internal view override returns (address) {
        return receiver;
    }

    function ineligibleAccount() internal view override returns (address) {
        return outsider;
    }

    function freezeAuthority() internal view override returns (address) {
        return officer;
    }

    // ── wiring ──────────────────────────────────────────────────────────────

    function _grantOfficer(address who) internal {
        bytes32 rolesSlot = keccak256("urwa.storage.roles.v1");
        bytes32 inner = keccak256(abi.encode(Roles.COMPLIANCE_OFFICER, uint256(rolesSlot)));
        vm.store(address(urwa), keccak256(abi.encode(who, uint256(inner))), bytes32(uint256(1)));
    }

    function _seed(address to, uint256 amount) internal {
        bytes32 slot = keccak256("urwa.storage.core.v1");
        vm.store(address(urwa), keccak256(abi.encode(to, uint256(slot))), bytes32(amount));
        vm.store(address(urwa), bytes32(uint256(slot) + 3), bytes32(amount));
    }
}
