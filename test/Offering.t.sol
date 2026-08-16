// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {OfferingRegistry} from "../src/OfferingRegistry.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {RuleContext} from "../src/interfaces/IPolicy.sol";
import {OfferingParams, Purchase, Tier} from "../src/interfaces/ITreasuryAndOfferings.sol";

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

/// @dev The token's supply side. Faithful to the real `MonetaryFacet`: only the
///      offering registry (or a supply operator) may distribute. A permissive
///      stub is what hid, before the audit, that a real purchase reverts because
///      the registry is not an authorised caller.
contract TokenStub {
    mapping(address => uint256) public delivered;
    address public registry;

    function setRegistry(address r) external {
        registry = r;
    }

    function distributeFromTreasury(address to, uint256 amount, uint64) external {
        require(msg.sender == registry, "not the registry");
        delivered[to] += amount;
    }
}

/// @dev The treasury's custody side, tracking the payment lock by amount so the
///      registry's raised/refund accounting is exercised against real numbers.
contract TreasuryStub {
    mapping(address => uint256) public lockedPayments;
    mapping(uint256 => uint256) public lockedOf;
    mapping(uint256 => address) public assetOf;

    function lockPayment(uint256 offeringId, address asset, uint256 amount) external {
        lockedPayments[asset] += amount;
        lockedOf[offeringId] += amount;
        assetOf[offeringId] = asset;
    }

    function unlockPayments(uint256 offeringId) external {
        lockedPayments[assetOf[offeringId]] -= lockedOf[offeringId];
        lockedOf[offeringId] = 0;
    }

    /// @dev Refunds leave the treasury even while payments are locked — that is
    ///      what the lock is for — and reduce the locked total as they go.
    function refund(uint256 offeringId, address asset, address investor, uint256 amount) external {
        uint256 locked = lockedOf[offeringId];
        uint256 dec = amount > locked ? locked : amount;
        lockedOf[offeringId] = locked - dec;
        lockedPayments[asset] -= dec;
        Cash(asset).transfer(investor, amount);
    }
}

/// @dev Offering-level rules for the CU-05 tests: one of each temperament.
contract AdmittingRule {
    function check(address, address, uint256, RuleContext calldata) external pure returns (bool, string memory) {
        return (true, "");
    }

    function bounds(address) external pure returns (uint256, uint256) {
        return (0, type(uint256).max);
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("Admitting");
    }
}

contract RefusingRule {
    function check(address, address, uint256, RuleContext calldata) external pure returns (bool, string memory) {
        return (false, "not accredited for this offering");
    }

    function bounds(address) external pure returns (uint256, uint256) {
        return (0, type(uint256).max);
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("Refusing");
    }
}

contract BrokenRule {
    function check(address, address, uint256, RuleContext calldata) external pure returns (bool, string memory) {
        revert("boom");
    }

    function bounds(address) external pure returns (uint256, uint256) {
        return (0, type(uint256).max);
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("Broken");
    }
}

/// @dev A regulatory minimum, the `RequiresClaim.bounds` shape: this rule
///      admits anyone but demands they invest at least `floor`.
contract MinimumRule {
    uint256 public immutable floor;

    constructor(uint256 floor_) {
        floor = floor_;
    }

    function check(address, address, uint256, RuleContext calldata) external pure returns (bool, string memory) {
        return (true, "");
    }

    function bounds(address) external view returns (uint256, uint256) {
        return (floor, type(uint256).max);
    }

    function ruleId() external pure returns (bytes32) {
        return keccak256("Minimum");
    }
}

/// @title Primary issuance — and the guarantee investors are owed
contract OfferingTest is Test {
    OfferingRegistry registry;
    Cash cash;
    Cash cash2; // a second accepted stablecoin, for the multi-currency path
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
        cash2 = new Cash();
        token = new TokenStub();
        token.setRegistry(address(registry));
        treasury = new TreasuryStub();

        cash.mint(alice, 1_000_000e18);
        cash.mint(bob, 1_000_000e18);
        cash2.mint(alice, 1_000_000e18);
        cash2.mint(bob, 1_000_000e18);

        id = _create(500e18, 1000e18);
        registry.activate(id);
    }

    // ── subscription ────────────────────────────────────────────────────────

    /// @notice A purchase takes payment and locks it, but delivers nothing yet
    /// @dev Delivery waits for settlement, so a failed offering never delivered
    ///      tokens it would have to claw back. The money is locked the instant
    ///      it lands.
    function test_aPurchaseTakesPaymentAndLocksItWithoutDelivering() public {
        vm.prank(alice);
        registry.purchase(id, 100e18, address(cash));

        assertEq(token.delivered(alice), 0, "tokens were delivered before settlement");
        assertEq(cash.balanceOf(address(treasury)), 100e18);
        assertEq(treasury.lockedPayments(address(cash)), 100e18, "the payment was not locked");
        assertEq(registry.raisedOf(id), 100e18);
    }

    /// @notice Tokens are delivered when the buyer claims a settled offering
    /// @dev The other half: once the soft cap is met and the offering settles,
    ///      the buyer pulls their tokens, and the distribution runs the token's
    ///      full pipeline. This is also the end-to-end proof that the registry
    ///      is an authorised caller of the distribution leg — the stub refuses
    ///      any other caller, exactly as the real facet does.
    function test_aBuyerClaimsTokensFromASettledOffering() public {
        vm.prank(alice);
        registry.purchase(id, 600e18, address(cash)); // meets the 500e18 soft cap
        vm.warp(registry.offeringOf(id).endAt + 1);
        registry.settle(id);

        assertEq(token.delivered(alice), 0, "delivered before the claim");
        vm.prank(alice);
        registry.claimTokens(0);
        assertEq(token.delivered(alice), 600e18, "the claim did not deliver");

        // And it cannot be claimed twice.
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.AlreadyRefunded.selector, uint256(0)));
        registry.claimTokens(0);
    }

    /// @notice A failed offering delivers no tokens and refunds every cent
    /// @dev The symmetry the old flow broke: it delivered at purchase, so a
    ///      failed raise left investors holding tokens for free while their cash
    ///      came back. Now the money is the only leg, and it unwinds cleanly.
    function test_aFailedOfferingRefundsCashAndDeliversNoTokens() public {
        vm.prank(alice);
        registry.purchase(id, 100e18, address(cash)); // below the 500e18 soft cap
        uint256 before = cash.balanceOf(alice);

        vm.warp(registry.offeringOf(id).endAt + 1);
        registry.beginRefunding(id);
        vm.prank(alice);
        registry.claimRefund(0);

        assertEq(cash.balanceOf(alice), before + 100e18, "cash not returned");
        assertEq(token.delivered(alice), 0, "tokens were delivered on a failed offering");
        assertEq(treasury.lockedPayments(address(cash)), 0, "the lock was not released");
    }

    /// @notice A request over the remaining cap reverts whole
    /// @dev No partial fill. Filling what is left and refunding the difference
    ///      would add a partial-refund path to the money leg and let a purchase
    ///      succeed for an amount nobody agreed to.
    function test_overTheHardCapRevertsWholeAndSaysWhatWouldFit() public {
        vm.prank(alice);
        registry.purchase(id, 900e18, address(cash));

        vm.prank(bob);
        vm.expectRevert(abi.encodeWithSelector(IErrors.HardCapExceeded.selector, 200e18, 100e18));
        registry.purchase(id, 200e18, address(cash));

        // And the amount the error named does fit.
        vm.prank(bob);
        registry.purchase(id, 100e18, address(cash));
        assertEq(registry.raisedOf(id), 1000e18);
    }

    /// @notice The preview tells an investor the answer before they sign
    function test_previewMatchesWhatHappens() public {
        (uint256 cost, uint256 tokens,) = registry.previewPurchase(id, 250e18);
        assertEq(tokens, 250e18);

        vm.prank(alice);
        registry.purchase(id, 250e18, address(cash));
        assertEq(cash.balanceOf(address(treasury)), cost);
    }

    function test_minimumAndMaximumAreEnforced() public {
        uint256 bounded = _create(0, 10_000e18, 100e18, 500e18);
        registry.activate(bounded);

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.BelowMinimum.selector, 50e18, 100e18));
        registry.purchase(bounded, 50e18, address(cash));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.AboveMaximum.selector, 600e18, 500e18));
        registry.purchase(bounded, 600e18, address(cash));
    }

    function test_aPausedOfferingTakesNoMoney() public {
        registry.pause(id);
        vm.prank(alice);
        vm.expectRevert();
        registry.purchase(id, 1e18, address(cash));
    }

    // ── the two permissionless calls ────────────────────────────────────────

    /// @notice Anyone may settle once the soft cap is met
    /// @dev An operator who is absent, unwilling or insolvent must not be able
    ///      to sit on an answer the chain already contains.
    function test_anyoneMaySettleOnceTheSoftCapIsMet() public {
        vm.prank(alice);
        registry.purchase(id, 600e18, address(cash));

        assertEq(treasury.lockedPayments(address(cash)), 600e18, "payments should be held until settlement");

        vm.prank(stranger);
        registry.settle(id);

        assertEq(registry.statusOf(id), 4, "not settled");
        assertEq(treasury.lockedPayments(address(cash)), 0, "payments were not released to the issuer");
    }

    /// @notice And anyone may start refunds once it is missed
    function test_anyoneMayBeginRefundingOnceTheSoftCapIsMissed() public {
        vm.prank(alice);
        registry.purchase(id, 100e18, address(cash));

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
        registry.purchase(id, 100e18, address(cash));
        vm.expectRevert(IErrors.SoftCapNotMet.selector);
        registry.settle(id);

        // Over-subscribed cannot refund. Warp to an absolute time past the
        // offering's own end, so the assertion does not depend on how much time
        // earlier statements happened to advance.
        uint256 met = _create(100e18, 1000e18);
        registry.activate(met);
        vm.prank(bob);
        registry.purchase(met, 200e18, address(cash));
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
        registry.purchase(met, 200e18, address(cash));
        vm.warp(block.timestamp + 40 days);
        registry.settle(met);

        vm.expectRevert(abi.encodeWithSelector(IErrors.OfferingNotActive.selector, met, uint8(4)));
        registry.cancel(met, "too late");
    }

    // ── refunds ─────────────────────────────────────────────────────────────

    /// @notice An investor refunds themselves without anyone's permission
    function test_anInvestorCanRefundThemselves() public {
        vm.prank(alice);
        registry.purchase(id, 100e18, address(cash));
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
        registry.purchase(id, 100e18, address(cash));
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
        registry.purchase(id, 100e18, address(cash));
        vm.prank(bob);
        registry.purchase(id, 50e18, address(cash));
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
        registry.purchase(id, 100e18, address(cash));
        vm.warp(block.timestamp + 40 days);
        registry.beginRefunding(id);

        vm.prank(stranger);
        vm.expectRevert();
        registry.claimRefund(0);
    }

    /// @notice Refunds are impossible before refunding begins
    function test_noRefundBeforeRefundingBegins() public {
        vm.prank(alice);
        registry.purchase(id, 100e18, address(cash));

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

    // ── CU-03 · tiered pricing ──────────────────────────────────────────────

    /// @notice A purchase crossing a tier boundary pays each band's price
    /// @dev The first 100 tokens are priced at band one, the next at band two.
    ///      A buyer taking 150 across the boundary pays 100 at the low price and
    ///      50 at the high one — not 150 at either. The preview agrees with what
    ///      the purchase charges, so the blended cost is never a surprise.
    function test_tieredPricingChargesEachBandInOrder() public {
        Tier[] memory tiers = new Tier[](2);
        tiers[0] = Tier({upToAmount: 100e18, price: 1e18}); // 1.0 each
        tiers[1] = Tier({upToAmount: 1000e18, price: 2e18}); // 2.0 each
        uint256 offering = _createWith(_one(address(cash)), 0, tiers, 0, 1000e18, 0, 0);
        registry.activate(offering);

        (uint256 preview,,) = registry.previewPurchase(offering, 150e18);
        assertEq(preview, 100e18 + 100e18, "100 at 1.0 plus 50 at 2.0");

        uint256 before = cash.balanceOf(alice);
        vm.prank(alice);
        registry.purchase(offering, 150e18, address(cash));
        assertEq(before - cash.balanceOf(alice), 200e18, "the buyer paid the blended cost");
    }

    /// @notice A later buyer pays the higher band the earlier one exhausted
    /// @dev Tiers are consumed across the whole raise, from where it has already
    ///      sold — the early-bird price is gone once its band is full.
    function test_aLaterBuyerPaysTheHigherBand() public {
        Tier[] memory tiers = new Tier[](2);
        tiers[0] = Tier({upToAmount: 100e18, price: 1e18});
        tiers[1] = Tier({upToAmount: 1000e18, price: 2e18});
        uint256 offering = _createWith(_one(address(cash)), 0, tiers, 0, 1000e18, 0, 0);
        registry.activate(offering);

        vm.prank(alice);
        registry.purchase(offering, 100e18, address(cash)); // takes the whole first band

        (uint256 preview,,) = registry.previewPurchase(offering, 50e18);
        assertEq(preview, 100e18, "the first band is spent; 50 at 2.0");
        vm.prank(bob);
        registry.purchase(offering, 50e18, address(cash));
        assertEq(registry.raisedOf(offering), 100e18 + 100e18);
    }

    /// @notice Buying past the final band is priced at it, never at zero
    /// @dev The silent-zero failure mode: a purchase above the last tier's
    ///      ceiling must not cost nothing. The final band's price continues.
    function test_pricingPastTheLastBandIsNeverFree() public {
        Tier[] memory tiers = new Tier[](1);
        tiers[0] = Tier({upToAmount: 100e18, price: 3e18});
        uint256 offering = _createWith(_one(address(cash)), 0, tiers, 0, 1000e18, 0, 0);
        registry.activate(offering);

        (uint256 preview,,) = registry.previewPurchase(offering, 200e18);
        assertEq(preview, 600e18, "200 tokens at the final 3.0, not 100 free");
    }

    // ── CU-03 · multi-currency ──────────────────────────────────────────────

    /// @notice Any listed currency is accepted, at the same price
    /// @dev The offering lists two stablecoins; a buyer pays in the second. The
    ///      cost is identical, and the money lands and locks under the currency
    ///      actually paid.
    function test_multiCurrencyAcceptsAnyListedToken() public {
        address[] memory pay = new address[](2);
        pay[0] = address(cash);
        pay[1] = address(cash2);
        uint256 offering = _createWith(pay, 1e18, new Tier[](0), 0, 1000e18, 0, 0);
        registry.activate(offering);

        vm.prank(alice);
        registry.purchase(offering, 100e18, address(cash2));

        assertEq(cash2.balanceOf(address(treasury)), 100e18, "the second currency did not land");
        assertEq(cash.balanceOf(address(treasury)), 0, "nothing should have moved in the first");
        assertEq(treasury.lockedPayments(address(cash2)), 100e18, "the paid currency was not locked");
    }

    /// @notice A currency the offering does not list is refused
    /// @dev Not silently retargeted to the first accepted token — the buyer pays
    ///      in what they chose or not at all.
    function test_anUnlistedPaymentTokenIsRefused() public {
        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.PaymentTokenNotAccepted.selector, address(cash2)));
        registry.purchase(id, 100e18, address(cash2));
    }

    // ── CU-05 · offering-level rules ────────────────────────────────────────

    /// @notice An attached rule that refuses stops the purchase, by name
    /// @dev The error carries the rule and its reason, so the investor learns
    ///      which requirement they missed rather than that "it failed".
    function test_anOfferingRuleRefusesAPurchase() public {
        RefusingRule refusing = new RefusingRule();
        registry.addRule(id, address(refusing));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IErrors.PurchaseRefused.selector, address(refusing), "not accredited for this offering"
            )
        );
        registry.purchase(id, 100e18, address(cash));
    }

    /// @notice Rules AND: one refusal among admissions still refuses
    /// @dev An offering may only be more restrictive than its token, never
    ///      less — so there are no OR groups at this level.
    function test_offeringRulesAllMustPass() public {
        registry.addRule(id, address(new AdmittingRule()));
        RefusingRule refusing = new RefusingRule();
        registry.addRule(id, address(refusing));

        vm.prank(alice);
        vm.expectRevert();
        registry.purchase(id, 100e18, address(cash));

        registry.removeRule(id, address(refusing));
        vm.prank(alice);
        registry.purchase(id, 100e18, address(cash));
        assertEq(registry.raisedOf(id), 100e18, "admitting rules alone should admit");
    }

    /// @notice A rule that reverts counts as a refusal, not an exemption
    /// @dev The same reading the policy plane gives a broken rule: it never
    ///      admits a buyer it can no longer judge.
    function test_aBrokenOfferingRuleRefuses() public {
        BrokenRule broken = new BrokenRule();
        registry.addRule(id, address(broken));

        vm.prank(alice);
        vm.expectRevert(
            abi.encodeWithSelector(
                IErrors.PurchaseRefused.selector, address(broken), "rule reverted or exceeded its gas ceiling"
            )
        );
        registry.purchase(id, 100e18, address(cash));
    }

    /// @notice A rule's bounds tighten the offering's floor, never loosen it
    /// @dev The `RequiresClaim.bounds` route: a regulatory minimum reaches the
    ///      registry without the rule mutating anything.
    function test_ruleBoundsRaiseTheMinimum() public {
        registry.addRule(id, address(new MinimumRule(50e18)));

        vm.prank(alice);
        vm.expectRevert(abi.encodeWithSelector(IErrors.BelowMinimum.selector, 40e18, 50e18));
        registry.purchase(id, 40e18, address(cash));

        vm.prank(alice);
        registry.purchase(id, 50e18, address(cash));
        assertEq(registry.raisedOf(id), 50e18);
    }

    /// @notice The rule list is capped, like the policy plane's
    /// @dev Griefing by configuration is still griefing: an operator cannot
    ///      attach rules until a purchase no longer fits in a block.
    function test_offeringRulesAreBounded() public {
        AdmittingRule fine = new AdmittingRule();
        for (uint256 i = 0; i < registry.MAX_RULES(); i++) {
            registry.addRule(id, address(fine));
        }
        vm.expectRevert(
            abi.encodeWithSelector(IErrors.RuleLimitExceeded.selector, registry.MAX_RULES(), registry.MAX_RULES())
        );
        registry.addRule(id, address(fine));
    }

    // ── CU-06 · the token-facet door ────────────────────────────────────────

    /// @notice Only the offering's own token may buy on an investor's behalf
    /// @dev The forwarding door is safe because the registry checks the caller
    ///      is the token the offering sells — a stranger naming somebody else
    ///      as investor is refused before anything is quoted.
    function test_onlyTheOfferingsTokenMayPurchaseFor() public {
        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotAuthorized.selector, stranger, bytes32(0)));
        registry.purchaseFor(id, 100e18, address(cash), alice);
    }

    /// @notice The token door buys for the investor, on the investor's money
    function test_theTokenDoorPurchasesForTheInvestor() public {
        vm.prank(address(token));
        registry.purchaseFor(id, 100e18, address(cash), alice);

        Purchase memory p = registry.purchaseOf(0);
        assertEq(p.investor, alice, "the investor of record must be the forwarded caller");
        assertEq(cash.balanceOf(address(treasury)), 100e18, "paid from the investor's balance");
    }

    /// @notice And the refund door refuses everyone but that token
    function test_onlyTheOfferingsTokenMayRefundFor() public {
        vm.prank(alice);
        registry.purchase(id, 100e18, address(cash));

        vm.prank(stranger);
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotAuthorized.selector, stranger, bytes32(0)));
        registry.claimRefundFor(0, alice);

        // The token door cannot refund one investor's purchase to another.
        vm.prank(address(token));
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotAuthorized.selector, bob, bytes32(0)));
        registry.claimRefundFor(0, bob);
    }

    function _one(address a) internal pure returns (address[] memory out) {
        out = new address[](1);
        out[0] = a;
    }

    /// @dev Offerings are not editable once created, so a test that needs
    ///      different bounds creates a different offering rather than reaching
    ///      into storage.
    function _create(uint256 softCap, uint256 hardCap, uint256 min, uint256 max) internal returns (uint256) {
        address[] memory pay = new address[](1);
        pay[0] = address(cash);
        return _createWith(pay, 1e18, new Tier[](0), softCap, hardCap, min, max);
    }

    function _createWith(
        address[] memory pay,
        uint256 price,
        Tier[] memory tiers,
        uint256 softCap,
        uint256 hardCap,
        uint256 min,
        uint256 max
    ) internal returns (uint256) {
        OfferingParams memory p = OfferingParams({
            token: address(token),
            paymentTokens: pay,
            price: price,
            tiers: tiers,
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
