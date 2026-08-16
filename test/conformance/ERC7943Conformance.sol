// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";

/// @dev The surface under test, declared locally so this folder is liftable
///      into its own repository unchanged. Nothing here imports the
///      implementation it judges.
interface IERC7943Surface {
    function canSend(address account) external view returns (bool);
    function canReceive(address account) external view returns (bool);
    function canTransfer(address from, address to, uint256 amount) external view returns (bool);
    function getFrozenTokens(address account) external view returns (uint256);
    function setFrozenTokens(address account, uint256 amount) external returns (bool);
    function forcedTransfer(address from, address to, uint256 amount) external returns (bool);
    function supportsInterface(bytes4 interfaceId) external view returns (bool);
    function balanceOf(address account) external view returns (uint256);
    function transfer(address to, uint256 amount) external returns (bool);
}

/// @title The ERC-7943 conformance kit
/// @notice Runnable against **any** implementation, not only this repository's:
///         inherit, answer the six hooks, and every test below judges your
///         token. Nothing else needs to be adopted.
/// @dev What conformance means here, and what it deliberately does not:
///
///      - The four views must answer for any input — an unknown wallet is the
///        most common thing an integrator supplies, and a revert there turns a
///        pre-flight into a failure. This is the exact failure mode found live
///        in a deployed registry, so the kit fuzzes it rather than trusting it.
///      - `canTransfer` answers "would this exact transfer succeed, right now",
///        which includes frozen balances. It does **not** consider allowances:
///        eligibility is about the parties and the amount, not approvals.
///      - `forcedTransfer` is judged only when the implementation declares an
///        authority for it. A token that deliberately does not install seizure
///        is not non-conformant — its absence is checkable on chain — but one
///        that has it must respect `canReceive` even under compulsion.
abstract contract ERC7943Conformance is Test {
    /// @dev The canonical freeze event; the kit asserts it by signature.
    event Frozen(address indexed account, uint256 amount);

    // ── what the implementer provides ───────────────────────────────────────

    /// @notice The token under test
    function token() internal view virtual returns (address);

    /// @notice An eligible account holding at least two whole tokens
    function eligibleHolder() internal view virtual returns (address);

    /// @notice An eligible account that may receive
    function eligibleReceiver() internal view virtual returns (address);

    /// @notice An account the token refuses in both directions
    function ineligibleAccount() internal view virtual returns (address);

    /// @notice Whoever may call `setFrozenTokens`
    function freezeAuthority() internal view virtual returns (address);

    /// @notice Whoever may call `forcedTransfer` — zero if seizure is not installed
    function forceAuthority() internal view virtual returns (address) {
        return address(0);
    }

    function _t() private view returns (IERC7943Surface) {
        return IERC7943Surface(token());
    }

    // ── interface ───────────────────────────────────────────────────────────

    /// @notice The token claims ERC-7943 and ERC-165, and denies the sentinel
    function test_conformance_interfaceIsClaimed() public view {
        assertTrue(_t().supportsInterface(0x3edbb4c4), "ERC-7943 (0x3edbb4c4) not claimed");
        assertTrue(_t().supportsInterface(0x01ffc9a7), "ERC-165 not claimed");
        assertFalse(_t().supportsInterface(0xffffffff), "the ERC-165 sentinel must be false");
    }

    // ── purity: the views answer for anything, and write nothing ────────────

    /// @notice The four views never revert, whatever they are asked about
    /// @dev Fuzzed, and called through `staticcall` so a write would fail too.
    ///      Unknown wallets, the zero address, the token itself — all of it is
    ///      a question, never an error.
    function testFuzz_conformance_viewsNeverRevertOrWrite(address a, address b, uint256 amount) public view {
        (bool ok,) = token().staticcall(abi.encodeWithSelector(IERC7943Surface.canSend.selector, a));
        assertTrue(ok, "canSend reverted");
        (ok,) = token().staticcall(abi.encodeWithSelector(IERC7943Surface.canReceive.selector, a));
        assertTrue(ok, "canReceive reverted");
        (ok,) = token().staticcall(abi.encodeWithSelector(IERC7943Surface.canTransfer.selector, a, b, amount));
        assertTrue(ok, "canTransfer reverted");
        (ok,) = token().staticcall(abi.encodeWithSelector(IERC7943Surface.getFrozenTokens.selector, a));
        assertTrue(ok, "getFrozenTokens reverted");
    }

    // ── semantics ───────────────────────────────────────────────────────────

    /// @notice A permitted transfer implies both parties are permitted
    function test_conformance_canTransferImpliesBothParties() public view {
        address from = eligibleHolder();
        address to = eligibleReceiver();
        assertTrue(_t().canTransfer(from, to, 1), "the eligible pair must be transferable");
        assertTrue(_t().canSend(from), "canTransfer true while canSend false");
        assertTrue(_t().canReceive(to), "canTransfer true while canReceive false");
    }

    /// @notice An ineligible party fails the pair, whichever side it stands on
    function test_conformance_anIneligiblePartyFailsThePair() public view {
        address outsider = ineligibleAccount();
        assertFalse(_t().canSend(outsider), "the ineligible account may send");
        assertFalse(_t().canReceive(outsider), "the ineligible account may receive");
        assertFalse(_t().canTransfer(outsider, eligibleReceiver(), 1), "ineligible sender passed canTransfer");
        assertFalse(_t().canTransfer(eligibleHolder(), outsider, 1), "ineligible recipient passed canTransfer");
    }

    /// @notice Allowances are not `canTransfer`'s business
    /// @dev Eligibility must answer identically with and without an approval in
    ///      place — approvals are ERC-20 mechanics, not compliance.
    function test_conformance_allowanceDoesNotChangeTheAnswer() public {
        address from = eligibleHolder();
        address to = eligibleReceiver();
        bool before = _t().canTransfer(from, to, 1);
        vm.prank(from);
        (bool ok,) = token().call(abi.encodeWithSignature("approve(address,uint256)", to, type(uint256).max));
        ok;
        assertEq(_t().canTransfer(from, to, 1), before, "an approval changed a compliance answer");
    }

    /// @notice And the refusal is enforced, not advisory
    function test_conformance_theAnswerBindsTheTransfer() public {
        address from = eligibleHolder();
        address outsider = ineligibleAccount();
        assertFalse(_t().canTransfer(from, outsider, 1));
        vm.prank(from);
        (bool ok,) = token().call(abi.encodeWithSelector(IERC7943Surface.transfer.selector, outsider, 1));
        assertFalse(ok, "a transfer canTransfer refused went through");
    }

    // ── freeze ──────────────────────────────────────────────────────────────

    /// @notice The frozen total may exceed the balance, and still answers
    /// @dev A freeze set before a redemption can outlive the balance it froze.
    function test_conformance_frozenMayExceedBalanceWithoutReverting() public {
        address holder = eligibleHolder();
        uint256 balance = _t().balanceOf(holder);

        vm.prank(freezeAuthority());
        _t().setFrozenTokens(holder, balance + 1e30);
        assertGe(_t().getFrozenTokens(holder), balance, "the over-freeze did not register");
        assertFalse(_t().canTransfer(holder, eligibleReceiver(), 1), "a fully frozen holder can still transfer");

        vm.prank(freezeAuthority());
        _t().setFrozenTokens(holder, 0);
        assertTrue(_t().canTransfer(holder, eligibleReceiver(), 1), "the unfreeze did not restore transfer");
    }

    /// @notice Freezing announces itself with the canonical event
    function test_conformance_freezingEmitsFrozen() public {
        address holder = eligibleHolder();
        vm.expectEmit(true, false, false, false, token());
        emit Frozen(holder, 0);
        vm.prank(freezeAuthority());
        _t().setFrozenTokens(holder, 1);

        vm.prank(freezeAuthority());
        _t().setFrozenTokens(holder, 0);
    }

    /// @notice A frozen holder's actual transfer fails, not only the preview
    function test_conformance_theFreezeBindsTheLedger() public {
        address holder = eligibleHolder();
        vm.prank(freezeAuthority());
        _t().setFrozenTokens(holder, type(uint256).max);

        vm.prank(holder);
        (bool ok,) = token().call(abi.encodeWithSelector(IERC7943Surface.transfer.selector, eligibleReceiver(), 1));
        assertFalse(ok, "a frozen balance moved");

        vm.prank(freezeAuthority());
        _t().setFrozenTokens(holder, 0);
    }

    // ── forced transfer — judged only where it exists ───────────────────────

    /// @notice Compulsion bypasses the freeze, never the recipient's eligibility
    /// @dev A forced transfer to an ineligible recipient is still an illegal
    ///      transfer; a court order names a destination that was onboarded.
    function test_conformance_forceRespectsTheRecipient() public {
        address authority = forceAuthority();
        if (authority == address(0)) return; // seizure not installed — provably, on chain

        address holder = eligibleHolder();
        vm.prank(freezeAuthority());
        _t().setFrozenTokens(holder, type(uint256).max);

        vm.prank(authority);
        (bool ok,) = token()
            .call(abi.encodeWithSelector(IERC7943Surface.forcedTransfer.selector, holder, ineligibleAccount(), 1));
        assertFalse(ok, "a forced transfer reached an ineligible recipient");

        vm.prank(authority);
        assertTrue(_t().forcedTransfer(holder, eligibleReceiver(), 1), "compulsion did not override the freeze");

        vm.prank(freezeAuthority());
        _t().setFrozenTokens(holder, 0);
    }
}
