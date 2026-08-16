// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {OfferingRegistry} from "../src/OfferingRegistry.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {OfferingParams, Purchase} from "../src/interfaces/ITreasuryAndOfferings.sol";

/// @dev A payment currency.
contract Cash {
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 v) external {
        balanceOf[to] += v;
    }

    function approve(address s, uint256 v) external returns (bool) {
        allowance[msg.sender][s] = v;
        return true;
    }

    function transfer(address to, uint256 v) external returns (bool) {
        if (balanceOf[msg.sender] < v) return false;
        balanceOf[msg.sender] -= v;
        balanceOf[to] += v;
        return true;
    }

    function transferFrom(address f, address to, uint256 v) external returns (bool) {
        if (balanceOf[f] < v) return false;
        balanceOf[f] -= v;
        balanceOf[to] += v;
        return true;
    }
}

/// @dev The token's supply side, and the treasury's custody side.
contract TokenStub {
    mapping(address => uint256) public delivered;

    function distributeFromTreasury(address to, uint256 amount, uint64) external {
        delivered[to] += amount;
    }
}

contract TreasuryStub {
    bool public locked;

    function lockPayments(uint256) external {
        locked = true;
    }

    function unlockPayments(uint256) external {
        locked = false;
    }

    /// @dev Refunds leave the treasury even while payments are locked — that is
    ///      what the lock is for.
    function refund(address asset, address investor, uint256 amount) external {
        Cash(asset).transfer(investor, amount);
    }
}

/// @title Primary issuance — and the guarantee investors are owed
contract OfferingTest is Test {
    OfferingRegistry registry;
    Cash cash;
    TokenStub token;
    TreasuryStub treasury;

    address operator = address(this);
    address alice = address(0xA1);
    address bob = address(0xB1);
    address stranger = address(0x5A);

    uint256 id;

    function setUp() public {
        vm.warp(1_000_000);
        registry = new OfferingRegistry(address(this));
        cash = new Cash();
        token = new TokenStub();
        treasury = new TreasuryStub();

        cash.mint(alice, 1_000_000e18);
        cash.mint(bob, 1_000_000e18);

        id = _create(500e18, 1000e18);
        registry.activate(id);
    }

    // ── subscription ────────────────────────────────────────────────────────

    function test_aPurchaseDeliversTokensAndTakesPayment() public {
        vm.prank(alice);
        registry.purchase(id, 100e18);

        assertEq(token.delivered(alice), 100e18);
        assertEq(cash.balanceOf(address(treasury)), 100e18);
        assertEq(registry.raisedOf(id), 100e18);
    }

    /// @notice A request over the remaining cap reverts whole
    /// @dev No partial fill. Filling what is left and refunding the difference
    ///      would add a partial-refund path to the money leg and let a purchase
    ///      succeed for an amount nobody agreed to.
    function test_overTheHardCapRevertsWholeAndSaysWhatWouldFit() public {
        vm.prank(alice);
        registry.purchase(id, 900e18);

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IErrors.HardCapExceeded.selector, 200e18, 100e18));
        registry.purchase(id, 200e18);

        // And the amount the error named does fit.
        vm.prank(bob);
        registry.purchase(id, 100e18);
        assertEq(registry.raisedOf(id), 1000e18);
    }

    /// @notice The preview tells an investor the answer before they sign
    function test_previewMatchesWhatHappens() public {
        (uint256 cost, uint256 tokens,) = registry.previewPurchase(id, 250e18);
        assertEq(tokens, 250e18);

        vm.prank(alice);
        registry.purchase(id, 250e18);
        assertEq(cash.balanceOf(address(treasury)), cost);
    }

    function test_minimumAndMaximumAreEnforced() public {
        uint256 bounded = _create(0, 10_000e18, 100e18, 500e18);
        registry.activate(bounded);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.BelowMinimum.selector, 50e18, 100e18));
        registry.purchase(bounded, 50e18);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.AboveMaximum.selector, 600e18, 500e18));
        registry.purchase(bounded, 600e18);
    }

    function test_aPausedOfferingTakesNoMoney() public {
        registry.pause(id);
        vm.prank(alice);
        vm.expectRevert();
        registry.purchase(id, 1e18);
    }

    // ── the two permissionless calls ────────────────────────────────────────

    /// @notice Anyone may settle once the soft cap is met
    /// @dev An operator who is absent, unwilling or insolvent must not be able
    ///      to sit on an answer the chain already contains.
    function test_anyoneMaySettleOnceTheSoftCapIsMet() public {
        vm.prank(alice);
        registry.purchase(id, 600e18);

        assertTrue(treasury.locked(), "payments should be held until settlement");

        vm.prank(stranger);
        registry.settle(id);

        assertEq(registry.statusOf(id), 4, "not settled");
        assertFalse(treasury.locked(), "payments were not released to the issuer");
    }

    /// @notice And anyone may start refunds once it is missed
    function test_anyoneMayBeginRefundingOnceTheSoftCapIsMissed() public {
        vm.prank(alice);
        registry.purchase(id, 100e18);

        vm.warp(block.timestamp + 40 days);
        vm.prank(stranger);
        registry.beginRefunding(id);
        assertEq(registry.statusOf(id), 5, "not refunding");
    }

    /// @notice Neither can be used to reverse the other's outcome
    function test_settleAndRefundCannotBeSwapped() public {
        // Under-subscribed cannot settle. `settle` gates on the soft cap, not
        // the clock, so no warp is needed — and warping here across an
        // `expectRevert` made the test depend on accumulated block time.
        vm.prank(alice);
        registry.purchase(id, 100e18);
        vm.expectRevert(IErrors.SoftCapNotMet.selector);
        registry.settle(id);

        // Over-subscribed cannot refund. Warp to an absolute time past the
        // offering's own end, so the assertion does not depend on how much time
        // earlier statements happened to advance.
        uint256 met = _create(100e18, 1000e18);
        registry.activate(met);
        vm.prank(bob);
        registry.purchase(met, 200e18);
        vm.warp(registry.offeringOf(met).endAt + 1);

        vm.expectRevert(IErrors.SoftCapMet.selector);
        registry.beginRefunding(met);
    }

    /// @notice A settled offering cannot be cancelled back into refunding
    /// @dev The drain the state machine has to refuse: settle releases payments
    ///      to the issuer, and `Cancelled` bypasses the soft-cap guard in
    ///      `beginRefunding`. Without a state guard on `cancel`, the chain
    ///      settle → cancel → beginRefunding reopens refunds on money already
    ///      released — drawn from whatever shares the treasury, including other
    ///      offerings' locked funds.
    function test_aSettledOfferingCannotBeCancelled() public {
        uint256 met = _create(100e18, 1000e18);
        registry.activate(met);
        vm.prank(bob);
        registry.purchase(met, 200e18);
        vm.warp(block.timestamp + 40 days);
        registry.settle(met);

        vm.expectRevert(abi.encodeWithSelector(IErrors.OfferingNotActive.selector, met, uint8(4)));
        registry.cancel(met, "too late");
    }

    // ── refunds ─────────────────────────────────────────────────────────────

    /// @notice An investor refunds themselves without anyone's permission
    function test_anInvestorCanRefundThemselves() public {
        vm.prank(alice);
        registry.purchase(id, 100e18);
        uint256 before = cash.balanceOf(alice);

        vm.warp(block.timestamp + 40 days);
        registry.beginRefunding(id);

        vm.prank(alice);
        registry.claimRefund(0);
        assertEq(cash.balanceOf(alice), before + 100e18);
    }

    /// @notice `L4.10` — a purchase cannot be refunded twice, by either path
    /// @dev Two public doors lead to one private function, and the state check
    ///      lives there. Putting it on each door would be two chances to forget.
    function test_aPurchaseCannotBeRefundedTwiceByEitherPath() public {
        vm.prank(alice);
        registry.purchase(id, 100e18);
        vm.warp(block.timestamp + 40 days);
        registry.beginRefunding(id);

        vm.prank(alice);
        registry.claimRefund(0);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.AlreadyRefunded.selector, uint256(0)));
        registry.claimRefund(0);

        // The operator path is not a second chance.
        vm.expectRevert(abi.encodeWithSelector(IErrors.AlreadyRefunded.selector, uint256(0)));
        registry.refundPurchase(0);
    }

    /// @notice The operator path and the investor path agree
    function test_theOperatorPathRefundsTheSameAmount() public {
        vm.prank(alice);
        registry.purchase(id, 100e18);
        vm.prank(bob);
        registry.purchase(id, 50e18);
        vm.warp(block.timestamp + 40 days);
        registry.beginRefunding(id);

        uint256 aliceBefore = cash.balanceOf(alice);
        uint256 bobBefore = cash.balanceOf(bob);
        registry.refundBatch(id, 10);

        assertEq(cash.balanceOf(alice), aliceBefore + 100e18);
        assertEq(cash.balanceOf(bob), bobBefore + 50e18);
    }

    /// @notice Only the investor may claim their own refund
    function test_onlyTheInvestorMayClaimTheirRefund() public {
        vm.prank(alice);
        registry.purchase(id, 100e18);
        vm.warp(block.timestamp + 40 days);
        registry.beginRefunding(id);

        vm.prank(stranger);
        vm.expectRevert();
        registry.claimRefund(0);
    }

    /// @notice Refunds are impossible before refunding begins
    function test_noRefundBeforeRefundingBegins() public {
        vm.prank(alice);
        registry.purchase(id, 100e18);

        vm.prank(alice);
        vm.expectRevert();
        registry.claimRefund(0);
    }

    // ── recovery ────────────────────────────────────────────────────────────

    /// @notice The override demands a reason
    /// @dev Recovery of last resort must never be indistinguishable from
    ///      ordinary operation in the log.
    function test_forceStatusRequiresAReason() public {
        vm.expectRevert(IErrors.ReasonRequired.selector);
        registry.forceStatus(id, 6, "");

        registry.forceStatus(id, 6, "offering abandoned by the issuer");
        assertEq(registry.statusOf(id), 6);
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _create(uint256 softCap, uint256 hardCap) internal returns (uint256) {
        return _create(softCap, hardCap, 0, 0);
    }

    /// @dev Offerings are not editable once created, so a test that needs
    ///      different bounds creates a different offering rather than reaching
    ///      into storage.
    function _create(uint256 softCap, uint256 hardCap, uint256 min, uint256 max) internal returns (uint256) {
        address[] memory pay = new address[](1);
        pay[0] = address(cash);
        OfferingParams memory p = OfferingParams({
            token: address(token),
            paymentTokens: pay,
            price: 1e18,
            softCap: softCap,
            hardCap: hardCap,
            minPerInvestor: min,
            maxPerInvestor: max,
            startAt: uint64(block.timestamp),
            endAt: uint64(block.timestamp + 30 days),
            lockupUntil: 0,
            preMint: true,
            regime: keccak256("Open")
        });
        return registry.createOffering(p, address(treasury));
    }
}
