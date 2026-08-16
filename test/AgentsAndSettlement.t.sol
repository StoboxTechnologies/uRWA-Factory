// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {Test} from "forge-std/Test.sol";
import {AgentAuthority} from "../src/AgentAuthority.sol";
import {AtomicDvP} from "../src/AtomicDvP.sol";
import {IErrors} from "../src/interfaces/IErrors.sol";
import {Instruction, Mandate} from "../src/interfaces/IAgentAndSettlement.sol";

contract Token {
    mapping(address => uint256) public balanceOf;
    bool public allowTransfers = true;
    string public refusal = "a compliance rule refused";

    function mint(address to, uint256 v) external {
        balanceOf[to] += v;
    }

    function setAllowed(bool v) external {
        allowTransfers = v;
    }

    function transferFrom(address f, address t, uint256 v) external returns (bool) {
        if (!allowTransfers) return false;
        if (balanceOf[f] < v) return false;
        balanceOf[f] -= v;
        balanceOf[t] += v;
        return true;
    }

    function canTransfer(address, address, uint256) external view returns (bool) {
        return allowTransfers;
    }

    function whyBlocked(address, address, uint256) external view returns (uint8, address, string memory) {
        return (allowTransfers ? 0 : 6, address(0), allowTransfers ? "" : refusal);
    }
}

/// @dev A payment leg that fails, to prove neither leg survives alone.
contract FailingCash {
    function transferFrom(address, address, uint256) external pure returns (bool) {
        return false;
    }
}

contract AgentsAndSettlementTest is Test {
    AgentAuthority authority;
    AtomicDvP dvp;
    Token security;
    Token cash;

    address principal = address(0xB055);
    address agent;
    uint256 agentKey;
    address seller;
    uint256 sellerKey;
    address buyer;
    uint256 buyerKey;
    address venue = address(0x1EE);

    bytes32 mandateId;

    function setUp() public {
        vm.warp(1_000_000);
        (agent, agentKey) = makeAddrAndKey("agent");
        (seller, sellerKey) = makeAddrAndKey("seller");
        (buyer, buyerKey) = makeAddrAndKey("buyer");

        authority = new AgentAuthority();
        dvp = new AtomicDvP();
        security = new Token();
        cash = new Token();

        security.mint(seller, 1000e18);
        cash.mint(buyer, 1000e18);

        mandateId = _grant(100e18, 250e18, 1 days);
    }

    // ── mandates ────────────────────────────────────────────────────────────

    /// @notice Inside the mandate, the action proceeds
    function test_anActionInsideTheMandateIsPermitted() public {
        (bool ok,) = authority.check(mandateId, authority.SCOPE_TRANSFER(), address(security), venue, 50e18);
        assertTrue(ok);

        vm.prank(agent);
        authority.consume(mandateId, 50e18);
        (uint256 spent,) = authority.consumed(mandateId);
        assertEq(spent, 50e18);
    }

    /// @notice `L4.15` — no agent action exceeds its mandate
    /// @dev The agent is not trusted to stay inside the limit; it is unable
    ///      to leave it. Both the free check and the state-changing path are
    ///      asserted, because an agent that ignores the former still meets
    ///      the latter.
    function test_theAgentCannotExceedThePerActionLimit() public {
        (bool ok, string memory why) =
            authority.check(mandateId, authority.SCOPE_TRANSFER(), address(security), venue, 150e18);
        assertFalse(ok);
        assertEq(why, "over the per-action limit");

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IErrors.PerActionLimitExceeded.selector, 150e18, 100e18));
        authority.consume(mandateId, 150e18);
    }

    /// @notice And so does the epoch limit, until the epoch turns
    function test_theEpochLimitBindsAndThenResets() public {
        // The mandate must outlive the epoch it is being tested across.
        mandateId = _grantFor(100e18, 250e18, 1 days, 30 days);

        vm.startPrank(agent);
        authority.consume(mandateId, 100e18);
        authority.consume(mandateId, 100e18);

        vm.expectRevert(abi.encodeWithSelector(IErrors.PerEpochLimitExceeded.selector, 100e18, 50e18));
        authority.consume(mandateId, 100e18);
        vm.stopPrank();

        vm.warp(block.timestamp + 1 days + 1);
        vm.prank(agent);
        authority.consume(mandateId, 100e18);

        (uint256 spent,) = authority.consumed(mandateId);
        assertEq(spent, 100e18, "the epoch did not reset");
    }

    /// @notice A scope the mandate does not carry is refused
    function test_anUnscopedActionIsRefused() public view {
        (bool ok, string memory why) =
            authority.check(mandateId, authority.SCOPE_SETTLE(), address(security), venue, 1e18);
        assertFalse(ok);
        assertEq(why, "action outside the mandate's scopes");
    }

    /// @notice A token or counterparty outside the mandate is refused
    function test_anUnlistedTokenOrCounterpartyIsRefused() public view {
        (bool ok, string memory why) =
            authority.check(mandateId, authority.SCOPE_TRANSFER(), address(0xBAD), venue, 1e18);
        assertFalse(ok);
        assertEq(why, "token not in the mandate");

        (ok, why) = authority.check(mandateId, authority.SCOPE_TRANSFER(), address(security), address(0xBAD), 1e18);
        assertFalse(ok);
        assertEq(why, "counterparty not in the mandate");
    }

    /// @notice Revocation takes effect on the next action, with no timelock
    /// @dev An agent misbehaving at three in the morning is stopped at three in
    ///      the morning.
    function test_revocationIsImmediate() public {
        vm.prank(principal);
        authority.revoke(mandateId);

        (bool ok, string memory why) =
            authority.check(mandateId, authority.SCOPE_TRANSFER(), address(security), venue, 1e18);
        assertFalse(ok);
        assertEq(why, "mandate revoked");

        vm.prank(agent);
        vm.expectRevert(abi.encodeWithSelector(IErrors.MandateIsRevoked.selector, mandateId));
        authority.consume(mandateId, 1e18);
    }

    /// @notice Every mandate expires
    /// @dev There is no perpetual mandate in the type — `expiresAt` is required,
    ///      and a grant in the past is refused outright.
    function test_everyMandateExpires() public {
        vm.warp(block.timestamp + 2 days);
        (bool ok, string memory why) =
            authority.check(mandateId, authority.SCOPE_TRANSFER(), address(security), venue, 1e18);
        assertFalse(ok);
        assertEq(why, "mandate expired");
    }

    function test_aMandateCannotBeGrantedAlreadyExpired() public {
        Mandate memory m = _template(1e18, 1e18, 1 days);
        m.expiresAt = uint64(block.timestamp);
        vm.prank(principal);
        vm.expectRevert();
        authority.grant(m);
    }

    /// @notice Only the principal may revoke
    function test_onlyThePrincipalMayRevoke() public {
        vm.prank(agent);
        vm.expectRevert();
        authority.revoke(mandateId);
    }

    // ── settlement ──────────────────────────────────────────────────────────

    /// @notice Both legs move in one transaction
    function test_bothLegsSettleTogether() public {
        Instruction memory i = _instruction(100e18, 500e18);
        dvp.settle(i, _sign(sellerKey, i), _sign(buyerKey, i));

        assertEq(security.balanceOf(buyer), 100e18);
        assertEq(cash.balanceOf(seller), 500e18);
    }

    /// @notice `L4.14` — a payment leg cannot settle without its security leg
    /// @dev The failing leg reverts the whole transaction, so the balance that
    ///      *did* move is rolled back with it. There is no block in which one
    ///      side has been paid and the other has not delivered.
    function test_neitherLegSurvivesAlone() public {
        FailingCash broken = new FailingCash();
        Instruction memory i = _instruction(100e18, 500e18);
        i.paymentToken = address(broken);

        uint256 sellerBefore = security.balanceOf(seller);
        bytes memory s1 = _sign(sellerKey, i);
        bytes memory s2 = _sign(buyerKey, i);

        vm.expectRevert();
        dvp.settle(i, s1, s2);

        assertEq(security.balanceOf(seller), sellerBefore, "the security leg moved without payment");
        assertEq(security.balanceOf(buyer), 0);
    }

    /// @notice Compliance is checked inside settlement
    /// @dev Not before it, where the answer could go stale between the check
    ///      and the move.
    function test_aRefusedSecurityLegStopsTheTrade() public {
        Instruction memory i = _instruction(100e18, 500e18);
        bytes memory s1 = _sign(sellerKey, i);
        bytes memory s2 = _sign(buyerKey, i);
        security.setAllowed(false);

        vm.expectRevert();
        dvp.settle(i, s1, s2);
        assertEq(cash.balanceOf(seller), 0, "the buyer paid for a trade that could not settle");
    }

    /// @notice A nonce settles at most once
    function test_aNonceCannotBeReplayed() public {
        Instruction memory i = _instruction(100e18, 500e18);
        bytes memory s1 = _sign(sellerKey, i);
        bytes memory s2 = _sign(buyerKey, i);
        dvp.settle(i, s1, s2);

        vm.expectRevert(abi.encodeWithSelector(IErrors.NonceAlreadySettled.selector, i.nonce));
        dvp.settle(i, s1, s2);
    }

    /// @notice An expired instruction cannot settle, however valid the signatures
    function test_anExpiredInstructionCannotSettle() public {
        Instruction memory i = _instruction(100e18, 500e18);
        bytes memory s1 = _sign(sellerKey, i);
        bytes memory s2 = _sign(buyerKey, i);
        vm.warp(uint256(i.validUntil) + 1);

        vm.expectRevert(abi.encodeWithSelector(IErrors.InstructionExpired.selector, i.validUntil));
        dvp.settle(i, s1, s2);
    }

    /// @notice Both signatures are required, and must be the right people's
    function test_bothSignaturesAreRequired() public {
        Instruction memory i = _instruction(100e18, 500e18);
        bytes memory bySeller = _sign(sellerKey, i);
        bytes memory byBuyer = _sign(buyerKey, i);

        vm.expectRevert(abi.encodeWithSelector(IErrors.BadSignature.selector, seller));
        dvp.settle(i, byBuyer, byBuyer);

        vm.expectRevert(abi.encodeWithSelector(IErrors.BadSignature.selector, buyer));
        dvp.settle(i, bySeller, bySeller);
    }

    /// @notice A cancelled instruction is dead
    /// @dev A trade one side has repudiated should not remain settleable by the
    ///      other until it expires.
    function test_aCancelledInstructionCannotSettle() public {
        Instruction memory i = _instruction(100e18, 500e18);
        bytes memory s1 = _sign(sellerKey, i);
        bytes memory s2 = _sign(buyerKey, i);
        vm.prank(seller);
        dvp.cancel(i);

        vm.expectRevert();
        dvp.settle(i, s1, s2);
    }

    /// @notice A bystander cannot cancel somebody else's trade
    /// @dev The nonce is public the moment the instruction reaches a relayer.
    ///      If cancelling took only the nonce, anyone watching could kill every
    ///      pending trade on the contract for the price of the gas.
    function test_onlyAPartyMayCancel() public {
        Instruction memory i = _instruction(100e18, 500e18);
        bytes memory s1 = _sign(sellerKey, i);
        bytes memory s2 = _sign(buyerKey, i);

        address bystander = address(0xB9);
        vm.prank(bystander);
        vm.expectRevert(abi.encodeWithSelector(IErrors.NotAuthorized.selector, bystander, i.nonce));
        dvp.cancel(i);

        // And the trade it tried to kill still settles.
        dvp.settle(i, s1, s2);
        assertTrue(dvp.isSettled(dvp.digestOf(i)));
    }

    /// @notice A forged instruction cannot cancel a genuine trade's nonce
    /// @dev The attack the party check alone did not stop: the attacker names
    ///      themselves as both parties and borrows the victim's nonce, so the
    ///      party check passes. It fails anyway, because cancellation is keyed
    ///      on the digest — which binds the real parties and terms — and the
    ///      forgery's digest is its own.
    function test_aForgedInstructionCannotCancelARealTrade() public {
        Instruction memory real = _instruction(100e18, 500e18);
        bytes memory s1 = _sign(sellerKey, real);
        bytes memory s2 = _sign(buyerKey, real);

        // A fresh allocation, not `= real`: assigning one memory struct to
        // another aliases it in Solidity, and mutating the alias would rewrite
        // the genuine instruction under the test's feet.
        address attacker = address(0xBAD);
        Instruction memory forged = _instruction(100e18, 500e18); // same nonce…
        forged.seller = attacker; // …but the attacker's own parties
        forged.buyer = attacker;

        vm.prank(attacker);
        dvp.cancel(forged); // passes the party check, cancels only its own digest

        // The genuine trade is untouched and still settles.
        dvp.settle(real, s1, s2);
        assertTrue(dvp.isSettled(dvp.digestOf(real)));
    }

    /// @notice A per-epoch cap with a zero-length epoch is rejected at the grant
    /// @dev Otherwise the cap never binds: every consume finds the window over
    ///      and resets the spend before adding to it.
    function test_anEpochlessCapIsRejected() public {
        Mandate memory m = _template(100e18, 250e18, 0);
        vm.prank(principal);
        vm.expectRevert(IErrors.EpochlessCap.selector);
        authority.grant(m);
    }

    /// @notice The preview names the reason before anyone signs anything
    function test_previewNamesTheRefusal() public {
        security.setAllowed(false);
        Instruction memory i = _instruction(100e18, 500e18);

        (bool ok, string memory reason) = dvp.previewSettle(i);
        assertFalse(ok);
        assertEq(reason, "a compliance rule refused");
    }

    // ── helpers ─────────────────────────────────────────────────────────────

    function _template(uint256 perAction, uint256 perEpoch, uint64 epoch) internal view returns (Mandate memory m) {
        bytes32[] memory scopes = new bytes32[](1);
        scopes[0] = authority.SCOPE_TRANSFER();
        address[] memory tokens = new address[](1);
        tokens[0] = address(security);
        address[] memory parties = new address[](1);
        parties[0] = venue;

        m = Mandate({
            principal: principal,
            agent: agent,
            scopes: scopes,
            tokens: tokens,
            counterparties: parties,
            maxPerAction: perAction,
            maxPerEpoch: perEpoch,
            epochLength: epoch,
            expiresAt: uint64(block.timestamp + 1 days),
            revoked: false
        });
    }

    /// @dev The template is built first: it reads from `authority`, and a call
    ///      inside the argument list consumes the prank.
    function _grantFor(uint256 perAction, uint256 perEpoch, uint64 epoch, uint64 lifetime) internal returns (bytes32) {
        Mandate memory m = _template(perAction, perEpoch, epoch);
        m.expiresAt = uint64(block.timestamp) + lifetime;
        vm.prank(principal);
        return authority.grant(m);
    }

    function _grant(uint256 perAction, uint256 perEpoch, uint64 epoch) internal returns (bytes32) {
        Mandate memory m = _template(perAction, perEpoch, epoch);
        vm.prank(principal);
        return authority.grant(m);
    }

    function _instruction(uint256 securityAmount, uint256 paymentAmount) internal view returns (Instruction memory) {
        return Instruction({
            securityToken: address(security),
            paymentToken: address(cash),
            seller: seller,
            buyer: buyer,
            securityAmount: securityAmount,
            paymentAmount: paymentAmount,
            validUntil: uint64(block.timestamp + 1 hours),
            nonce: keccak256("trade-1"),
            tradeRef: keccak256("ref-1")
        });
    }

    function _sign(uint256 key, Instruction memory i) internal view returns (bytes memory) {
        bytes32 typehash = keccak256(
            "Instruction(address securityToken,address paymentToken,address seller,address buyer,uint256 securityAmount,uint256 paymentAmount,uint64 validUntil,bytes32 nonce,bytes32 tradeRef)"
        );
        bytes32 structHash = keccak256(
            abi.encode(
                typehash,
                i.securityToken,
                i.paymentToken,
                i.seller,
                i.buyer,
                i.securityAmount,
                i.paymentAmount,
                i.validUntil,
                i.nonce,
                i.tradeRef
            )
        );
        bytes32 digest = keccak256(abi.encodePacked("\x19\x01", dvp.DOMAIN_SEPARATOR(), structHash));
        (uint8 v, bytes32 r, bytes32 s) = vm.sign(key, digest);
        return abi.encodePacked(r, s, v);
    }
}
