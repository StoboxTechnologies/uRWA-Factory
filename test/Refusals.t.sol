// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {uRWAToken} from "../src/uRWAToken.sol";
import {AtomicDvP} from "../src/AtomicDvP.sol";
import {DiamondCutFacet} from "../src/facets/DiamondCutFacet.sol";
import {RolesFacet} from "../src/facets/RolesFacet.sol";
import {IDiamond} from "../src/interfaces/IDiamond.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {Instruction} from "../src/interfaces/IAgentAndSettlement.sol";
import {Roles} from "../src/interfaces/Roles.sol";

/// @dev Allows everything, so the ledger's own guards are what refuses.
contract Permissive {
    function beforeUpdate(address, address, uint256) external pure {}
}

/// @dev Refuses with **empty** revert data — the shape `_bubble` must not
///      swallow into a success or re-raise as garbage.
contract EmptyRevert {
    function beforeUpdate(address, address, uint256) external pure {
        revert();
    }
}

/// @title The refusal branches, each walked once
/// @notice Coverage found the guard paths nobody had exercised: the wrong-key
///         permit, the empty revert, the stale role member, the malleable
///         signature, the payment leg that fails after compliance passed. A
///         branch never taken is a branch nobody has observed — this suite
///         takes them, so the next regression in any of them is a red test
///         rather than a first-ever execution in production.
contract LedgerRefusalsTest is Test {
    uRWAToken token;
    DiamondCutFacet cutFacet;
    Permissive permissive;

    uint256 holderKey = 0xA11CE;
    address holder;
    address bob = address(0xB0B);

    bytes32 constant PERMIT_TYPEHASH =
        keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");

    function setUp() public {
        cutFacet = new DiamondCutFacet();
        token = new uRWAToken("Test", "TST", 18, 0, address(this), address(cutFacet), address(this), 0);
        permissive = new Permissive();
        _install(address(permissive));
        holder = vm.addr(holderKey);
        _seed(holder, 1000e18);
    }

    // ── ERC-20 guards ───────────────────────────────────────────────────────

    /// @notice The zero address can be neither spender nor recipient
    function test_zeroAddressIsRefusedEverywhere() public {
        vm.expectRevert(abi.encodeWithSelector(IErrors.ERC20InvalidSpender.selector, address(0)));
        token.approve(address(0), 1e18);

        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ERC20InvalidReceiver.selector, address(0)));
        token.transfer(address(0), 1e18);
    }

    /// @notice More than the balance does not move
    function test_anOverdraftIsRefusedWithTheShortfall() public {
        vm.prank(holder);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ERC20InsufficientBalance.selector, holder, 1000e18, 1001e18));
        token.transfer(bob, 1001e18);
    }

    /// @notice An allowance is spent exactly, and the infinite one never is
    /// @dev Both branches of `_spendAllowance`: the finite path refuses beyond
    ///      the approval and decrements inside it; `type(uint256).max` is the
    ///      standard's "never decrement" sentinel and must survive spending.
    function test_allowancesSpendFinitelyAndInfinitelyCorrectly() public {
        vm.prank(holder);
        token.approve(bob, 100e18);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IErrors.ERC20InsufficientAllowance.selector, bob, 100e18, 101e18));
        token.transferFrom(holder, bob, 101e18);

        vm.prank(bob);
        token.transferFrom(holder, bob, 40e18);
        assertEq(token.allowance(holder, bob), 60e18, "the finite allowance must decrement");

        vm.prank(holder);
        token.approve(bob, type(uint256).max);
        vm.prank(bob);
        token.transferFrom(holder, bob, 10e18);
        assertEq(token.allowance(holder, bob), type(uint256).max, "the infinite allowance must not decrement");
    }

    // ── permit ──────────────────────────────────────────────────────────────

    /// @notice A valid permit sets the allowance without the holder paying gas
    function test_aValidPermitSetsTheAllowance() public {
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(holderKey, bob, 50e18, 0, block.timestamp + 1 hours);
        token.permit(holder, bob, 50e18, block.timestamp + 1 hours, v, r, s);
        assertEq(token.allowance(holder, bob), 50e18);
    }

    /// @notice Misdirected, forged and expired permits are each refused
    function test_badPermitsAreRefusedForTheirOwnReasons() public {
        uint256 deadline = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) = _signPermit(holderKey, bob, 50e18, 0, deadline);

        // To the zero spender.
        vm.expectRevert(abi.encodeWithSelector(IErrors.ERC20InvalidSpender.selector, address(0)));
        token.permit(holder, address(0), 50e18, deadline, v, r, s);

        // Signed by the wrong key: the signature recovers, but not to the holder.
        (uint8 v2, bytes32 r2, bytes32 s2) = _signPermit(0xBEEF, bob, 50e18, 0, deadline);
        vm.expectRevert(abi.encodeWithSelector(IErrors.BadSignature.selector, holder));
        token.permit(holder, bob, 50e18, deadline, v2, r2, s2);

        // Past its deadline — checked last, so the clock only moves forward.
        vm.warp(deadline + 1);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InstructionExpired.selector, uint64(deadline)));
        token.permit(holder, bob, 50e18, deadline, v, r, s);

        assertEq(token.allowance(holder, bob), 0, "no refused permit may leave an allowance behind");
    }

    /// @notice A compliance facet that reverts with nothing still names a reason
    /// @dev Empty revert data must not bubble as empty: the holder gets the
    ///      canonical ERC-7943 error rather than a silent failure.
    function test_anEmptyRevertStillCarriesTheStandardError() public {
        EmptyRevert muted = new EmptyRevert();
        _replace(address(muted));

        vm.prank(holder);
        vm.expectRevert(
            abi.encodeWithSelector(IErrors.ERC7943CannotTransfer.selector, address(0), address(0), uint256(0))
        );
        token.transfer(bob, 1e18);
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _signPermit(uint256 key, address spender, uint256 value, uint256 nonce, uint256 deadline)
        internal
        view
        returns (uint8 v, bytes32 r, bytes32 s)
    {
        bytes32 structHash = keccak256(abi.encode(PERMIT_TYPEHASH, vm.addr(key), spender, value, nonce, deadline));
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", token.DOMAIN_SEPARATOR(), structHash));
        return vm.sign(key, digest);
    }

    function _install(address facet) internal {
        _cut(facet, IDiamond.FacetCutAction.Add);
    }

    function _replace(address facet) internal {
        _cut(facet, IDiamond.FacetCutAction.Replace);
    }

    function _cut(address facet, IDiamond.FacetCutAction action) internal {
        bytes4[] memory sel = new bytes4[](1);
        sel[0] = Permissive.beforeUpdate.selector;
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(facet, action, sel);
        DiamondCutFacet(address(token)).diamondCut(cuts, address(0), "");
    }

    function _seed(address to, uint256 amount) internal {
        bytes32 slot = keccak256("urwa.storage.core.v1");
        vm.store(address(token), keccak256(abi.encode(to, uint256(slot))), bytes32(amount));
        vm.store(address(token), bytes32(uint256(slot) + 3), bytes32(amount));
    }
}

/// @title The role register's quiet branches
contract RoleRefusalsTest is Test {
    uRWAToken token;
    RolesFacet roles;

    address officerA = address(0xC0);
    address officerB = address(0xC1);

    function setUp() public {
        DiamondCutFacet cutFacet = new DiamondCutFacet();
        token = new uRWAToken("Test", "TST", 18, 0, address(this), address(cutFacet), address(this), 0);
        roles = new RolesFacet();

        bytes4[] memory sel = new bytes4[](7);
        sel[0] = RolesFacet.grantRole.selector;
        sel[1] = RolesFacet.revokeRole.selector;
        sel[2] = RolesFacet.renounceRole.selector;
        sel[3] = RolesFacet.hasRole.selector;
        sel[4] = RolesFacet.roleAdmin.selector;
        sel[5] = RolesFacet.getRoleMemberCount.selector;
        sel[6] = RolesFacet.getRoleMember.selector;
        IDiamond.FacetCut[] memory cuts = new IDiamond.FacetCut[](1);
        cuts[0] = IDiamond.FacetCut(address(roles), IDiamond.FacetCutAction.Add, sel);
        DiamondCutFacet(address(token)).diamondCut(cuts, address(0), "");
    }

    function _r() private view returns (RolesFacet) {
        return RolesFacet(address(token));
    }

    /// @notice The zero address cannot hold a role, and a re-grant is a no-op
    /// @dev The silent-return branch matters: a repeated grant must not push a
    ///      duplicate member row that the enumeration would count twice.
    function test_grantRefusesZeroAndAbsorbsRepeats() public {
        vm.expectRevert(IErrors.ZeroAddress.selector);
        _r().grantRole(Roles.COMPLIANCE_OFFICER, address(0));

        _r().grantRole(Roles.COMPLIANCE_OFFICER, officerA);
        _r().grantRole(Roles.COMPLIANCE_OFFICER, officerA);
        assertEq(_r().getRoleMemberCount(Roles.COMPLIANCE_OFFICER), 1, "a repeated grant duplicated the member");
    }

    /// @notice Revoking a role nobody holds changes nothing
    function test_revokingANonHolderIsANoOp() public {
        _r().grantRole(Roles.COMPLIANCE_OFFICER, officerA);
        _r().revokeRole(Roles.COMPLIANCE_OFFICER, officerB); // never held it
        assertTrue(_r().hasRole(Roles.COMPLIANCE_OFFICER, officerA), "an unrelated revoke reached the holder");
    }

    /// @notice Enumeration skips revoked members and answers zero past the end
    /// @dev The member array keeps history; the enumeration must not. A revoked
    ///      officer showing up in `getRoleMember` would put a departed employee
    ///      on every compliance report that lists the register.
    function test_enumerationSkipsTheRevokedAndEndsAtZero() public {
        _r().grantRole(Roles.COMPLIANCE_OFFICER, officerA);
        _r().grantRole(Roles.COMPLIANCE_OFFICER, officerB);
        _r().revokeRole(Roles.COMPLIANCE_OFFICER, officerA);

        assertEq(_r().getRoleMemberCount(Roles.COMPLIANCE_OFFICER), 1);
        assertEq(_r().getRoleMember(Roles.COMPLIANCE_OFFICER, 0), officerB, "enumeration returned a revoked member");
        assertEq(_r().getRoleMember(Roles.COMPLIANCE_OFFICER, 1), address(0), "past the end must be zero, not revert");
        assertEq(_r().roleAdmin(Roles.COMPLIANCE_OFFICER), Roles.ISSUER_ADMIN);
    }
}

/// @dev A payment leg whose success is a switch.
contract PayLeg {
    bool public good = true;
    mapping(address => uint256) public balanceOf;

    function setGood(bool v) external {
        good = v;
    }

    function transferFrom(address, address, uint256) external view returns (bool) {
        return good;
    }
}

/// @dev A security leg that passes compliance and then fails to move — the
///      shape `settle` must refuse whole, never half.
contract SecLeg {
    bool public canMove = true;
    bool public compliant = true;
    bool public readable = true;

    function set(bool compliant_, bool canMove_, bool readable_) external {
        compliant = compliant_;
        canMove = canMove_;
        readable = readable_;
    }

    function canTransfer(address, address, uint256) external view returns (bool) {
        require(readable, "unreadable");
        return compliant;
    }

    function whyBlocked(address, address, uint256) external view returns (uint8, address, string memory) {
        require(readable, "unreadable");
        return (6, address(0), "a compliance rule refused");
    }

    function transferFrom(address, address, uint256) external view returns (bool) {
        return canMove;
    }
}

/// @title Settlement's refusal branches
contract SettlementRefusalsTest is Test {
    AtomicDvP dvp;
    PayLeg pay;
    SecLeg sec;

    uint256 sellerKey = 0x5E11;
    uint256 buyerKey = 0xB417;
    address seller;
    address buyer;

    function setUp() public {
        vm.warp(1_000_000);
        dvp = new AtomicDvP();
        pay = new PayLeg();
        sec = new SecLeg();
        seller = vm.addr(sellerKey);
        buyer = vm.addr(buyerKey);
    }

    /// @notice A malformed or malleable signature is a bad signature, not a wildcard
    /// @dev `_recover` returns zero for both; the party check must then refuse.
    ///      The malleable form is the same signature with `s` flipped over the
    ///      curve order — valid to a naive verifier, rejected here.
    function test_malformedAndMalleableSignaturesAreRefused() public {
        Instruction memory i = _instruction();
        bytes memory good = _sign(sellerKey, i);
        bytes memory byBuyer = _sign(buyerKey, i);

        // Wrong length.
        vm.expectRevert(abi.encodeWithSelector(IErrors.BadSignature.selector, seller));
        dvp.settle(i, hex"1234", byBuyer);

        // Malleable: s' = N - s, v' flipped. Same maths, other half of the curve.
        (bytes32 r, bytes32 s, uint8 v) = _split(good);
        uint256 N = 0xFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFFEBAAEDCE6AF48A03BBFD25E8CD0364141;
        bytes memory malleable = abi.encodePacked(r, bytes32(N - uint256(s)), v == 27 ? uint8(28) : uint8(27));
        vm.expectRevert(abi.encodeWithSelector(IErrors.BadSignature.selector, seller));
        dvp.settle(i, malleable, byBuyer);
    }

    /// @notice A payment leg that fails after compliance passed reverts the trade whole
    /// @dev Compliance said yes; the buyer's funds did not arrive. Nothing may
    ///      have moved — and the same for a security leg that fails after the
    ///      payment moved.
    function test_aHalfDeadLegRevertsTheWholeTrade() public {
        Instruction memory i = _instruction();
        bytes memory bySeller = _sign(sellerKey, i);
        bytes memory byBuyer = _sign(buyerKey, i);

        pay.setGood(false);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientAvailable.selector, 500e18, 0));
        dvp.settle(i, bySeller, byBuyer);

        pay.setGood(true);
        sec.set(true, false, true);
        vm.expectRevert(abi.encodeWithSelector(IErrors.InsufficientAvailable.selector, 100e18, 0));
        dvp.settle(i, bySeller, byBuyer);

        assertFalse(dvp.isSettled(dvp.digestOf(i)), "a failed trade must not be marked settled");
    }

    /// @notice A settled digest cannot settle again
    function test_aSettledTradeCannotReplay() public {
        Instruction memory i = _instruction();
        bytes memory bySeller = _sign(sellerKey, i);
        bytes memory byBuyer = _sign(buyerKey, i);
        dvp.settle(i, bySeller, byBuyer);

        vm.expectRevert(abi.encodeWithSelector(IErrors.NonceAlreadySettled.selector, i.nonce));
        dvp.settle(i, bySeller, byBuyer);
    }

    /// @notice The preview names every refusal it can see
    /// @dev Each branch of `previewSettle`, in order: expiry, the zero party,
    ///      the settled digest, the unreadable token, the named rule.
    function test_thePreviewNamesEachRefusal() public {
        Instruction memory i = _instruction();

        i.validUntil = uint64(block.timestamp - 1);
        (bool ok, string memory why) = dvp.previewSettle(i);
        assertFalse(ok);
        assertEq(why, "instruction expired");
        i.validUntil = uint64(block.timestamp + 1 days);

        address realSeller = i.seller;
        i.seller = address(0);
        (, why) = dvp.previewSettle(i);
        assertEq(why, "a party is the zero address");
        i.seller = realSeller;

        bytes memory bySeller = _sign(sellerKey, i);
        bytes memory byBuyer = _sign(buyerKey, i);
        dvp.settle(i, bySeller, byBuyer);
        (, why) = dvp.previewSettle(i);
        assertEq(why, "already settled");

        Instruction memory j = _instruction();
        j.nonce = keccak256("second");
        sec.set(true, true, false);
        (, why) = dvp.previewSettle(j);
        assertEq(why, "the security token could not be read");

        sec.set(false, true, true);
        (, why) = dvp.previewSettle(j);
        assertEq(why, "a compliance rule refused");
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _instruction() internal view returns (Instruction memory i) {
        i.securityToken = address(sec);
        i.paymentToken = address(pay);
        i.seller = seller;
        i.buyer = buyer;
        i.securityAmount = 100e18;
        i.paymentAmount = 500e18;
        i.validUntil = uint64(block.timestamp + 1 days);
        i.nonce = keccak256("trade-1");
        i.tradeRef = keccak256("ref");
    }

    function _sign(uint256 key, Instruction memory i) internal view returns (bytes memory) {
        bytes32 digest = dvp.digestOf(i);
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }

    function _split(bytes memory sig) internal pure returns (bytes32 r, bytes32 s, uint8 v) {
        assembly {
            r := mload(add(sig, 0x20))
            s := mload(add(sig, 0x40))
            v := byte(0, mload(add(sig, 0x60)))
        }
    }
}
