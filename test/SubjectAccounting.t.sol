// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {ComplianceFacet} from "../src/facets/ComplianceFacet.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {IIdentityRegistry, Claim} from "../src/interfaces/IIdentityRegistry.sol";
import {Roles} from "../src/interfaces/Roles.sol";

/// @dev A registry where one person may hold several wallets — the whole point
///      of subject accounting, and the thing an address-based cap misses.
contract SubjectRegistry is IIdentityRegistry {
    mapping(address => bytes32) public subject;
    mapping(address => bool) public active;

    function register(address wallet, bytes32 who) external {
        subject[wallet] = who;
        active[wallet] = true;
    }

    function subjectOf(address wallet) external view returns (bytes32) {
        return subject[wallet];
    }

    function isActive(address wallet) external view returns (bool) {
        return active[wallet];
    }

    function claim(bytes32, bytes32) external pure returns (Claim memory c) {
        return c;
    }

    function hasValidClaim(bytes32, bytes32) external pure returns (bool) {
        return true;
    }
}

/// @title L4.5 and L4.6 — counting people, not addresses
contract SubjectAccountingTest is Test {
    uRWAToken token;
    ComplianceFacet compliance;
    SubjectRegistry registry;

    bytes32 constant INVESTOR_ONE = keccak256("investor-one");
    bytes32 constant INVESTOR_TWO = keccak256("investor-two");

    // One person, three wallets.
    address w1 = address(0xA1);
    address w2 = address(0xA2);
    address w3 = address(0xA3);
    // A different person, one wallet.
    address other = address(0xB1);

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        token = new uRWAToken("Test", "TST", 18, 0, address(this), address(cutFacet), address(this), 0);
        compliance = new ComplianceFacet();
        registry = new SubjectRegistry();

        _install();
        _grant(Roles.UPGRADE_ADMIN);
        ComplianceFacet(address(token)).setIdentityRegistry(address(registry));

        registry.register(w1, INVESTOR_ONE);
        registry.register(w2, INVESTOR_ONE);
        registry.register(w3, INVESTOR_ONE);
        registry.register(other, INVESTOR_TWO);
    }

    /// @notice `L4.5` — one investor with three wallets is one holder
    /// @dev The evasion an address-based cap cannot see. Counting addresses
    ///      would report four holders here and refuse the honest second
    ///      investor under a cap of two.
    function test_oneInvestorWithThreeWalletsCountsOnce() public {
        _seedThrough(w1, 300e18);

        vm.prank(w1);
        token.transfer(w2, 100e18);
        vm.prank(w1);
        token.transfer(w3, 100e18);

        ComplianceFacet c = ComplianceFacet(address(token));
        assertEq(c.holderCount(), 3, "three addresses hold a balance");
        assertEq(c.subjectHolderCount(), 1, "but only one person does");
        assertEq(c.subjectBalanceOf(INVESTOR_ONE), 300e18, "the person's total is the sum of their wallets");
    }

    /// @notice A self-transfer changes no count, however many times it is done
    /// @dev `_increase` reads "was this balance zero?" as `balanceAfter ==
    ///      amount`. A self-transfer of the whole balance nets back to the same
    ///      figure, so that test is true even though the holder was never new —
    ///      it would add a phantom holder on every call. `holderCount` is a
    ///      permissionless reporting figure, so anyone could inflate it without
    ///      bound; the guard is that a self-transfer returns early.
    function test_aSelfTransferNeverChangesTheCounts() public {
        _seedThrough(w1, 100e18);
        ComplianceFacet c = ComplianceFacet(address(token));
        assertEq(c.holderCount(), 1);
        assertEq(c.subjectHolderCount(), 1);

        for (uint256 i = 0; i < 5; i++) {
            vm.prank(w1);
            token.transfer(w1, 100e18);
        }

        assertEq(c.holderCount(), 1, "self-transfers inflated the address register");
        assertEq(c.subjectHolderCount(), 1, "self-transfers inflated the subject register");
        assertEq(c.subjectBalanceOf(INVESTOR_ONE), 100e18, "the balance drifted");
    }

    /// @notice A second person moves the subject count, a second wallet does not
    function test_aSecondPersonIsASecondHolder() public {
        _seedThrough(w1, 200e18);
        ComplianceFacet c = ComplianceFacet(address(token));
        assertEq(c.subjectHolderCount(), 1);

        vm.prank(w1);
        token.transfer(other, 50e18);
        assertEq(c.subjectHolderCount(), 2, "a different person did not raise the count");

        vm.prank(w1);
        token.transfer(w2, 50e18);
        assertEq(c.subjectHolderCount(), 2, "a second wallet of the same person raised the count");
    }

    /// @notice Only the ledger may move the counters
    /// @dev `afterUpdate` writes the numbers every holder cap is decided on and
    ///      moves no balance, so an unguarded one would let a bystander make
    ///      `MaxHolders` refuse an honest investor — or admit a forbidden one —
    ///      without touching the ledger at all.
    function test_theSubjectCountersCannotBeMovedFromOutside() public {
        _seedThrough(w1, 100e18);
        ComplianceFacet c = ComplianceFacet(address(token));
        assertEq(c.subjectHolderCount(), 1);

        address bystander = address(0xB9);
        vm.prank(bystander);
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotAuthorized.selector, bystander, bytes32(0)));
        c.afterUpdate(address(0), other, 1_000_000e18);

        assertEq(c.subjectHolderCount(), 1, "the count moved without a balance moving");
        assertEq(c.subjectBalanceOf(INVESTOR_TWO), 0);
    }

    /// @notice Emptying every wallet of a person removes exactly one holder
    function test_leavingEntirelyRemovesTheHolder() public {
        _seedThrough(w1, 100e18);
        vm.prank(w1);
        token.transfer(w2, 40e18);

        ComplianceFacet c = ComplianceFacet(address(token));
        assertEq(c.subjectHolderCount(), 1);

        vm.prank(w1);
        token.transfer(other, 60e18);
        assertEq(c.subjectHolderCount(), 2, "still holds through the second wallet");

        vm.prank(w2);
        token.transfer(other, 40e18);
        assertEq(c.subjectHolderCount(), 1, "the person left and the count did not follow");
        assertEq(c.subjectBalanceOf(INVESTOR_ONE), 0);
    }

    /// @notice `L4.6` — the two totals agree with supply, after any sequence
    /// @dev Fuzzed over transfer amounts. Subject balances are maintained
    ///      incrementally, which is exactly the kind of bookkeeping that drifts,
    ///      so the invariant is asserted rather than assumed.
    function testFuzz_subjectBalancesSumToSupply(uint96 a, uint96 b, uint96 cAmt) public {
        uint256 total = 1000e18;
        _seedThrough(w1, total);

        // Bounds are computed before each prank: `bound` makes a call of its
        // own, which would consume the prank and send from the test contract.
        uint256 first = bound(a, 0, total);
        vm.prank(w1);
        token.transfer(w2, first);

        uint256 second = bound(b, 0, token.balanceOf(w2));
        vm.prank(w2);
        token.transfer(w3, second);

        uint256 third = bound(cAmt, 0, token.balanceOf(w1));
        vm.prank(w1);
        token.transfer(other, third);

        ComplianceFacet c = ComplianceFacet(address(token));
        uint256 addresses = token.balanceOf(w1) + token.balanceOf(w2) + token.balanceOf(w3) + token.balanceOf(other);
        uint256 subjects = c.subjectBalanceOf(INVESTOR_ONE) + c.subjectBalanceOf(INVESTOR_TWO);

        assertEq(addresses, total, "balances no longer sum to supply");
        assertEq(subjects, total, "subject balances no longer sum to supply");
    }

    /// @notice A wallet the registry does not know still counts
    /// @dev The synthetic subject. Skipping unknown wallets would let a cap be
    ///      evaded by holding through addresses nobody registered.
    function test_unknownWalletGetsASyntheticSubject() public {
        address stranger = address(0xDEAD);
        ComplianceFacet c = ComplianceFacet(address(token));

        assertEq(c.subjectOf(stranger), keccak256(abi.encodePacked(stranger)));

        _seedThrough(w1, 100e18);
        vm.prank(w1);
        vm.expectRevert(); // unverified recipient — the pipeline refuses first
        token.transfer(stranger, 1e18);
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    /// @dev Seeds through a transfer from a trusted source, so the accounting
    ///      runs rather than being written behind its back.
    function _seedThrough(address to, uint256 amount) internal {
        address source = address(0x5EED);
        registry.register(source, keccak256("source"));
        bytes32 slot = keccak256("urwa.storage.core.v1");
        vm.store(address(token), keccak256(abi.encode(source, uint256(slot))), bytes32(amount));
        vm.store(address(token), bytes32(uint256(slot) + 3), bytes32(amount));

        vm.prank(source);
        token.transfer(to, amount);
    }

    function _install() internal {
        bytes4[] memory sel = new bytes4[](10);
        sel[0] = ComplianceFacet.beforeUpdate.selector;
        sel[1] = ComplianceFacet.afterUpdate.selector;
        sel[2] = ComplianceFacet.setIdentityRegistry.selector;
        sel[3] = ComplianceFacet.holderCount.selector;
        sel[4] = ComplianceFacet.subjectHolderCount.selector;
        sel[5] = ComplianceFacet.subjectBalanceOf.selector;
        sel[6] = ComplianceFacet.subjectOf.selector;
        sel[7] = ComplianceFacet.canTransfer.selector;
        sel[8] = ComplianceFacet.whyBlocked.selector;
        sel[9] = ComplianceFacet.identityRegistry.selector;

        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(address(compliance), IDiamond.FacetCutAction.Add, sel);
        DiamondCutFacet(address(token)).diamondCut(cuts, address(0), "");
    }

    function _grant(bytes32 role) internal {
        bytes32 rolesSlot = keccak256("urwa.storage.roles.v1");
        bytes32 inner = keccak256(abi.encode(role, uint256(rolesSlot)));
        vm.store(address(token), keccak256(abi.encode(address(this), uint256(inner))), bytes32(uint256(1)));
    }
}
