// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IIdentityRegistry, Claim} from "../src/interfaces/IIdentityRegistry.sol";
import {ClaimKeys, Roles} from "../src/interfaces/Roles.sol";
import {Layout} from "../src/storage/Layout.sol";

/// @dev A registry that behaves. Tier 0, the open-source default.
contract Allowlist is IIdentityRegistry {
    mapping(address => bool) public permitted;

    function allow(address a) external {
        permitted[a] = true;
    }

    function subjectOf(address wallet) external pure returns (bytes32) {
        return keccak256(abi.encodePacked(wallet));
    }

    function isActive(address wallet) external view returns (bool) {
        return permitted[wallet];
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        return true;
    }
}

/// @dev A registry that reverts on every call — the deployed StoboxDID's
///      behaviour for unknown wallets, which is the case that matters.
contract RevertingRegistry is IIdentityRegistry {
    function subjectOf(address) external pure returns (bytes32) {
        revert("AddressDoesNotLinkedToDID");
    }

    function isActive(address) external pure returns (bool) {
        revert("AddressDoesNotLinkedToDID");
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory) {
        revert("AddressDoesNotLinkedToDID");
    }

    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        revert("AddressDoesNotLinkedToDID");
    }
}

/// @dev A registry that consumes all the gas it is given.
contract GasBurningRegistry is IIdentityRegistry {
    function subjectOf(address) external view returns (bytes32) {
        _burn();
        return 0;
    }

    function isActive(address) external view returns (bool) {
        _burn();
        return true;
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    function hasValidClaim(bytes32, bytes32) external view returns (bool) {
        _burn();
        return true;
    }

    function _burn() private view {
        uint256 x;
        while (gasleft() > 1000) {
            x = uint256(keccak256(abi.encode(x)));
        }
    }
}

contract CompliancePipelineTest is Test {
    uRWAToken token;
    ComplianceFacet compliance;
    Allowlist registry;

    address alice = address(0xA11CE);
    address bob = address(0xB0B);
    address mallory = address(0x000A11);
    address treasury = address(0x7EA);

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        token =
            new uRWAToken("Manhattan Office Tower", "MOTT", 18, 0, address(this), address(cutFacet), address(this), 0);
        compliance = new ComplianceFacet();
        registry = new Allowlist();

        _installCompliance();
        _grant(Roles.ISSUER_ADMIN);
        _grant(Roles.COMPLIANCE_OFFICER);
        _grant(Roles.UPGRADE_ADMIN);

        ComplianceFacet(address(token)).setIdentityRegistry(address(registry));
        registry.allow(alice);
        registry.allow(bob);

        _seed(alice, 1000e18);
        _seed(treasury, 1000e18);
    }

    // ── L4.2 · the views never revert ───────────────────────────────────────

    /// @notice No input makes a view function revert
    /// @dev The standard's hardest requirement, and the one a real integration
    ///      breaks first: an integrator calls `canTransfer` on an unknown
    ///      counterparty long before anyone holds a token.
    function testFuzz_viewsNeverRevert(address from, address to, uint256 amount) public view {
        ComplianceFacet c = ComplianceFacet(address(token));
        c.canSend(from);
        c.canReceive(to);
        c.canTransfer(from, to, amount);
        c.getFrozenTokens(from);
        c.unfrozenBalanceOf(from);
        c.whyBlocked(from, to, amount);
    }

    /// @notice A registry that reverts on every call does not break the views
    /// @dev This is the StoboxDID integration defect, as a test. Without
    ///      try/catch the token would fail ERC-7943 conformance on its most
    ///      common input.
    function test_viewsSurviveARevertingRegistry() public {
        ComplianceFacet(address(token)).setIdentityRegistry(address(new RevertingRegistry()));

        assertFalse(ComplianceFacet(address(token)).canSend(alice));
        assertFalse(ComplianceFacet(address(token)).canTransfer(alice, bob, 1e18));
        (uint8 stage,,) = ComplianceFacet(address(token)).whyBlocked(alice, bob, 1e18);
        assertEq(stage, 3, "a reverting registry should read as an unverified sender");
    }

    /// @notice Nor does one that burns every drop of gas it is offered
    function test_viewsSurviveAGasBurningRegistry() public {
        ComplianceFacet(address(token)).setIdentityRegistry(address(new GasBurningRegistry()));
        assertFalse(ComplianceFacet(address(token)).canTransfer(alice, bob, 1e18));
    }

    // ── the gates, in order ─────────────────────────────────────────────────

    function test_verifiedHolderMayTransfer() public {
        vm.prank(alice);
        token.transfer(bob, 100e18);
        assertEq(token.balanceOf(bob), 100e18);
    }

    function test_unverifiedRecipientIsRefused() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ERC7943CannotReceive.selector, mallory));
        token.transfer(mallory, 1e18);
    }

    /// @notice `L4.9` — trust never bypasses pause
    /// @dev The exemption people assume is total. It is not: trust skips claims
    ///      and rules, and nothing else.
    function test_trustDoesNotBypassPause() public {
        ComplianceFacet(address(token)).trust(treasury, "token treasury");
        ComplianceFacet(address(token)).trust(alice, "market maker");

        vm.prank(treasury);
        token.transfer(alice, 1e18);

        ComplianceFacet(address(token)).pause("incident");

        vm.prank(treasury);
        vm.expectRevert(IErrors.ProtocolPaused.selector);
        token.transfer(alice, 1e18);
    }

    /// @notice Nor a frozen balance
    function test_trustDoesNotBypassAFrozenBalance() public {
        ComplianceFacet(address(token)).trust(alice, "market maker");
        ComplianceFacet(address(token)).trust(bob, "market maker");
        _freeze(alice, 1000e18);

        vm.prank(alice);
        vm.expectRevert();
        token.transfer(bob, 1e18);
    }

    /// @notice An address pause stops receiving, which a freeze does not
    /// @dev The distinction that justifies having both.
    function test_addressPauseBlocksBothDirections() public {
        ComplianceFacet(address(token)).pauseAddress(bob, "wallet compromised");

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.AddressIsPaused.selector, bob));
        token.transfer(bob, 1e18);

        _seed(bob, 10e18);
        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IErrors.AddressIsPaused.selector, bob));
        token.transfer(alice, 1e18);
    }

    /// @notice A freeze restricts sending only
    function test_freezeRestrictsSendingButNotReceiving() public {
        _freeze(bob, type(uint256).max);

        vm.prank(alice);
        token.transfer(bob, 1e18);
        assertEq(token.balanceOf(bob), 1e18, "a frozen holder could not be paid");
    }

    /// @notice `L4.11` — the frozen total may exceed the balance
    function test_frozenMayExceedBalanceWithoutReverting() public {
        _freeze(bob, type(uint256).max);
        assertEq(ComplianceFacet(address(token)).getFrozenTokens(bob), type(uint256).max);
        assertEq(ComplianceFacet(address(token)).unfrozenBalanceOf(bob), 0);
    }

    // ── the diagnostic ──────────────────────────────────────────────────────

    /// @notice `whyBlocked` and enforcement agree, always
    /// @dev They share `_evaluate`, so this asserts a property rather than a
    ///      coincidence: if the view says it would pass, the transfer passes.
    function testFuzz_diagnosticAgreesWithEnforcement(uint256 amount) public {
        amount = bound(amount, 0, 2000e18);
        ComplianceFacet c = ComplianceFacet(address(token));

        bool predicted = c.canTransfer(alice, bob, amount);
        (uint8 stage,,) = c.whyBlocked(alice, bob, amount);
        assertEq(predicted, stage == 0, "canTransfer and whyBlocked disagree");

        vm.prank(alice);
        (bool ok,) = address(token).call(abi.encodeWithSignature("transfer(address,uint256)", bob, amount));
        assertEq(ok, predicted, "the prediction did not match what happened");
    }

    // ── access control ──────────────────────────────────────────────────────

    function test_trustRequiresAReason() public {
        vm.expectRevert(IErrors.ReasonRequired.selector);
        ComplianceFacet(address(token)).trust(treasury, "");
    }

    function test_onlyComplianceOfficerMayPause() public {
        vm.prank(alice);
        vm.expectRevert();
        ComplianceFacet(address(token)).pause("no");
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _installCompliance() internal {
        bytes4[] memory sel = new bytes4[](19);
        sel[0] = ComplianceFacet.beforeUpdate.selector;
        sel[1] = ComplianceFacet.canSend.selector;
        sel[2] = ComplianceFacet.canReceive.selector;
        sel[3] = ComplianceFacet.canTransfer.selector;
        sel[4] = ComplianceFacet.getFrozenTokens.selector;
        sel[5] = ComplianceFacet.unfrozenBalanceOf.selector;
        sel[6] = ComplianceFacet.whyBlocked.selector;
        sel[7] = ComplianceFacet.setPolicySet.selector;
        sel[8] = ComplianceFacet.setIdentityRegistry.selector;
        sel[9] = ComplianceFacet.trust.selector;
        sel[10] = ComplianceFacet.distrust.selector;
        sel[11] = ComplianceFacet.isTrusted.selector;
        sel[12] = ComplianceFacet.pause.selector;
        sel[13] = ComplianceFacet.unpause.selector;
        sel[14] = ComplianceFacet.paused.selector;
        sel[15] = ComplianceFacet.pauseAddress.selector;
        sel[16] = ComplianceFacet.unpauseAddress.selector;
        sel[17] = ComplianceFacet.addressPaused.selector;
        sel[18] = ComplianceFacet.identityRegistry.selector;

        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(address(compliance), IDiamond.FacetCutAction.Add, sel);
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
    }

    function _freeze(address who, uint256 amount) internal {
        bytes32 slot = keccak256("urwa.storage.freeze.v1");
        vm.store(address(token), keccak256(abi.encode(who, uint256(slot))), bytes32(amount));
    }
}
