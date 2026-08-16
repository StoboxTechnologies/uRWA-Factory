// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {Treasury, IERC20Minimal} from "../src/Treasury.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {Erc1404Facet, RolesFacet} from "../src/facets/RolesFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IIdentityRegistry, Claim} from "../src/interfaces/IIdentityRegistry.sol";
import {Roles} from "../src/interfaces/Roles.sol";

contract Everyone is IIdentityRegistry {
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

/// @dev A payment currency, for the treasury's custody tests.
contract Cash is IERC20Minimal {
    mapping(address => uint256) public balances;

    function mint(address to, uint256 amount) external {
        balances[to] += amount;
    }

    function balanceOf(address a) external view returns (uint256) {
        return balances[a];
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        if (balances[msg.sender] < amount) return false;
        balances[msg.sender] -= amount;
        balances[to] += amount;
        return true;
    }
}

contract RolesAndCustodyTest is Test {
    uRWAToken token;
    Treasury treasury;
    Cash cash;

    address issuer = address(this);
    address officer = address(0xC0);
    address other = address(0xC1);
    address registry = address(0x2E6);

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        token = new uRWAToken("Test", "TST", 18, 0, address(this), address(cutFacet), address(this), 0);
        _install();
        _seedRole(Roles.ISSUER_ADMIN, issuer);
        ComplianceFacet(address(token)).setIdentityRegistry(address(new Everyone()));

        treasury = new Treasury();
        treasury.initialise(address(token), issuer, registry);
        cash = new Cash();
    }

    // ── roles ───────────────────────────────────────────────────────────────

    function test_grantAndRevoke() public {
        RolesFacet r = RolesFacet(address(token));
        r.grantRole(Roles.COMPLIANCE_OFFICER, officer);
        assertTrue(r.hasRole(Roles.COMPLIANCE_OFFICER, officer));
        assertEq(r.getRoleMemberCount(Roles.COMPLIANCE_OFFICER), 1);

        r.grantRole(Roles.COMPLIANCE_OFFICER, other);
        r.revokeRole(Roles.COMPLIANCE_OFFICER, officer);
        assertFalse(r.hasRole(Roles.COMPLIANCE_OFFICER, officer));
        assertEq(r.getRoleMemberCount(Roles.COMPLIANCE_OFFICER), 1);
    }

    /// @notice A role cannot be emptied
    /// @dev A token whose only compliance officer renounces can never be paused
    ///      again, and the mistake is unrecoverable. Refusing is the only safe
    ///      behaviour, so it is asserted rather than left to operational care.
    function test_theLastHolderOfARoleCannotLeave() public {
        RolesFacet r = RolesFacet(address(token));
        r.grantRole(Roles.COMPLIANCE_OFFICER, officer);

        vm.expectRevert();
        r.revokeRole(Roles.COMPLIANCE_OFFICER, officer);

        vm.prank(officer);
        vm.expectRevert();
        r.renounceRole(Roles.COMPLIANCE_OFFICER);

        assertTrue(r.hasRole(Roles.COMPLIANCE_OFFICER, officer), "the role was emptied");
    }

    function test_onlyIssuerAdminMayGrant() public {
        vm.prank(other);
        vm.expectRevert();
        RolesFacet(address(token)).grantRole(Roles.SUPPLY_OPERATOR, other);
    }

    // ── ERC-1404 ────────────────────────────────────────────────────────────

    /// @notice The old interface and the new one give the same answer
    /// @dev It is a translation of `whyBlocked`, not a second opinion. Two
    ///      compliance answers from one token would be worse than one.
    function test_erc1404AgreesWithWhyBlocked() public {
        Erc1404Facet legacy = Erc1404Facet(address(token));
        ComplianceFacet c = ComplianceFacet(address(token));

        (uint8 stage,,) = c.whyBlocked(other, issuer, 1e18);
        assertEq(legacy.detectTransferRestriction(other, issuer, 1e18), stage);

        assertEq(legacy.messageForTransferRestriction(0), "transfer permitted");
        assertEq(legacy.messageForTransferRestriction(5), "amount exceeds the unfrozen balance");
    }

    // ── custody ─────────────────────────────────────────────────────────────

    /// @notice Reserved supply is not available
    function test_reservationsReduceAvailableBalance() public {
        _fund(address(treasury), 1000e18);
        assertEq(treasury.availableBalance(), 1000e18);

        vm.prank(registry);
        treasury.reserve(400e18, 1);
        assertEq(treasury.availableBalance(), 600e18);
        assertEq(treasury.reservedOf(1), 400e18);

        vm.prank(registry);
        treasury.release(400e18, 1);
        assertEq(treasury.availableBalance(), 1000e18);
    }

    /// @notice The issuer cannot withdraw reserved supply
    /// @dev The revert is asserted by selector. A bare `expectRevert` here
    ///      would pass just as happily if the caller simply lacked the role,
    ///      and would stop proving anything about reservations.
    function test_issuerCannotWithdrawWhatIsReserved() public {
        _seedRole(Roles.SUPPLY_OPERATOR, issuer);
        _fund(address(treasury), 1000e18);
        vm.prank(registry);
        treasury.reserve(900e18, 1);

        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientAvailable.selector, 200e18, 100e18));
        treasury.withdrawERC20(address(token), issuer, 200e18);
    }

    /// @notice Revoking the role stops the withdrawal
    /// @dev Custody asks the token's role register on every call rather than
    ///      trusting an address recorded when the treasury was created. An
    ///      issuer whose key is compromised is removed by revoking the role —
    ///      which has to reach the money, or it has not removed them at all.
    function test_revokingTheRoleReachesTheMoney() public {
        cash.mint(address(treasury), 500e18);

        treasury.withdrawPayments(address(cash), issuer, 100e18, 7);
        assertEq(cash.balanceOf(issuer), 100e18);

        // Somebody has to keep the role: it cannot be left empty, and a token
        // with no issuer admin can never grant one again.
        RolesFacet(address(token)).grantRole(Roles.ISSUER_ADMIN, other);
        RolesFacet(address(token)).revokeRole(Roles.ISSUER_ADMIN, issuer);

        vm.expectRevert(abi.encodeWithSelector(IErrors.NotAuthorized.selector, issuer, Roles.ISSUER_ADMIN));
        treasury.withdrawPayments(address(cash), issuer, 100e18, 7);
    }

    /// @notice Nor investor money while the offering is unsettled
    /// @dev The guarantee the treasury exists for. Money paid into an offering
    ///      that has not met its soft cap cannot be spent in the meantime.
    function test_lockedPaymentsCannotBeWithdrawn() public {
        cash.mint(address(treasury), 500e18);

        vm.prank(registry);
        treasury.lockPayments(7);

        vm.expectRevert(abi.encodeWithSelector(IErrors.PaymentsAreLocked.selector, uint256(7)));
        treasury.withdrawPayments(address(cash), issuer, 100e18, 7);

        vm.prank(registry);
        treasury.unlockPayments(7);
        treasury.withdrawPayments(address(cash), issuer, 100e18, 7);
        assertEq(cash.balanceOf(issuer), 100e18);
    }

    /// @notice Only the offering registry may reserve or lock
    function test_onlyTheRegistryMayReserve() public {
        vm.expectRevert(IErrors.OnlyOfferingRegistry.selector);
        treasury.reserve(1e18, 1);
    }

    /// @notice A clone is initialised once
    function test_initialiseIsOnce() public {
        vm.expectRevert();
        treasury.initialise(address(token), issuer, registry);
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _install() internal {
        RolesFacet r = new RolesFacet();
        ComplianceFacet c = new ComplianceFacet();
        Erc1404Facet e = new Erc1404Facet();

        bytes4[] memory rs = new bytes4[](6);
        rs[0] = RolesFacet.grantRole.selector;
        rs[1] = RolesFacet.revokeRole.selector;
        rs[2] = RolesFacet.renounceRole.selector;
        rs[3] = RolesFacet.hasRole.selector;
        rs[4] = RolesFacet.getRoleMemberCount.selector;
        rs[5] = RolesFacet.getRoleMember.selector;

        bytes4[] memory cs = new bytes4[](5);
        cs[0] = ComplianceFacet.beforeUpdate.selector;
        cs[1] = ComplianceFacet.afterUpdate.selector;
        cs[2] = ComplianceFacet.whyBlocked.selector;
        cs[3] = ComplianceFacet.setIdentityRegistry.selector;
        cs[4] = ComplianceFacet.identityRegistry.selector;

        bytes4[] memory es = new bytes4[](2);
        es[0] = Erc1404Facet.detectTransferRestriction.selector;
        es[1] = Erc1404Facet.messageForTransferRestriction.selector;

        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](3);
        cuts[0] = IDiamond.FacetCut(address(r), IDiamond.FacetCutAction.Add, rs);
        cuts[1] = IDiamond.FacetCut(address(c), IDiamond.FacetCutAction.Add, cs);
        cuts[2] = IDiamond.FacetCut(address(e), IDiamond.FacetCutAction.Add, es);
        DiamondCutFacet(address(token)).diamondCut(cuts, address(0), "");
    }

    function _seedRole(bytes32 role, address who) internal {
        bytes32 rolesSlot = keccak256("urwa.storage.roles.v1");
        bytes32 inner = keccak256(abi.encode(role, uint256(rolesSlot)));
        vm.store(address(token), keccak256(abi.encode(who, uint256(inner))), bytes32(uint256(1)));
    }

    function _fund(address to, uint256 amount) internal {
        bytes32 slot = keccak256("urwa.storage.core.v1");
        vm.store(address(token), keccak256(abi.encode(to, uint256(slot))), bytes32(amount));
        vm.store(address(token), bytes32(uint256(slot) + 3), bytes32(amount));
    }
}
