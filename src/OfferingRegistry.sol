// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "./interfaces/IErrors.sol";
import {IEvents} from "./interfaces/IEvents.sol";
import {OfferingParams, Purchase, Tier} from "./interfaces/ITreasuryAndOfferings.sol";
import {Roles} from "./interfaces/Roles.sol";

interface IERC20Payment {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface ITokenSupply {
    function distributeFromTreasury(address to, uint256 amount, uint64 unlockAt) external;
}

interface ITreasuryCustody {
    function lockPayment(uint256 offeringId, address asset, uint256 amount) external;
    function unlockPayments(uint256 offeringId) external;
    function refund(uint256 offeringId, address asset, address investor, uint256 amount) external;
}

/// @title Primary issuance
/// @notice Subscription, allocation, settlement and refunds. The two calls that
///         decide an offering's fate — `settle` and `beginRefunding` — are
///         **permissionless**, because both are mechanical consequences of
///         facts already on chain and requiring an operator would let an absent
///         one hold investor funds hostage.
/// @dev Ships as one contract rather than the five facets in doc 03. The facet
///      split buys an upgradeable write path with a stable read path, which is
///      worth having and is not worth having *first*: the money paths need an
///      audit more than they need upgradeability, and a diamond is a larger
///      surface to audit. Recorded as `CU-07` rather than left as a silent
///      divergence.
contract OfferingRegistry is IErrors {
    enum Status {
        Draft,
        Active,
        Paused,
        Closed,
        Settled,
        Refunding,
        Cancelled
    }

    struct Offering {
        OfferingParams params;
        address treasury;
        Status status;
        uint256 raised;
        uint256 sold;
    }

    address public admin;
    uint256 public nextId = 1;

    mapping(uint256 => Offering) private _offerings;
    mapping(uint256 => address) public operatorOf;
    mapping(uint256 => address[]) private _rules;

    Purchase[] private _purchases;
    mapping(address => uint256[]) private _byInvestor;
    mapping(uint256 => uint256[]) private _byOffering;
    mapping(uint256 => uint256) public paidBySubject;

    /// @dev Purchase states. `Refunded` is terminal and checked on both refund
    ///      paths, which is the whole of `L4.10`.
    uint8 constant PURCHASE_ACTIVE = 0;
    uint8 constant PURCHASE_REFUNDED = 1;
    uint8 constant PURCHASE_SETTLED = 2;

    constructor(address admin_) {
        admin = admin_;
    }

    // ── lifecycle ───────────────────────────────────────────────────────────

    function createOffering(OfferingParams calldata params, address treasury) external returns (uint256 id) {
        id = nextId++;
        Offering storage o = _offerings[id];
        o.params = params;
        o.treasury = treasury;
        o.status = Status.Draft;
        operatorOf[id] = msg.sender;
        emit IEvents.OfferingCreated(id, params.token, params.regime);
    }

    function activate(uint256 id) external {
        _onlyOperator(id);
        _move(id, Status.Active);
        // Payments are locked as each one arrives, not in one flag here: the
        // lock has to track an amount and an asset, and at activation there is
        // nothing yet to lock.
    }

    function pause(uint256 id) external {
        _onlyOperator(id);
        _move(id, Status.Paused);
    }

    function unpause(uint256 id) external {
        _onlyOperator(id);
        _move(id, Status.Active);
    }

    function close(uint256 id) external {
        _onlyOperator(id);
        _move(id, Status.Closed);
    }

    function cancel(uint256 id, string calldata reason) external {
        _onlyOperator(id);
        reason;
        // A settled or already-refunding offering is finished. Cancelling one
        // reopened refunds on money that had been released to the issuer or
        // belonged to another offering sharing the treasury — the state machine
        // must only run forward from a live state.
        Status s = _offerings[id].status;
        if (s != Status.Draft && s != Status.Active && s != Status.Paused && s != Status.Closed) {
            revert OfferingNotActive(id, uint8(s));
        }
        _move(id, Status.Cancelled);
    }

    // ── subscription ────────────────────────────────────────────────────────

    /// @notice Subscribe
    /// @dev A request larger than the hard cap still allows **reverts whole**.
    ///      Filling what is left and refunding the difference would add a
    ///      partial-refund path to the money leg — the most sensitive code
    ///      here — and would let a purchase succeed for an amount nobody
    ///      agreed to.
    function purchase(uint256 id, uint256 amount, address paymentToken) external {
        Offering storage o = _offerings[id];
        if (o.status != Status.Active) revert OfferingNotActive(id, uint8(o.status));
        if (block.timestamp < o.params.startAt || block.timestamp >= o.params.endAt) {
            revert OfferingNotActive(id, uint8(o.status));
        }

        (uint256 cost, uint256 tokens,) = _quote(o, amount);

        if (o.params.minPerInvestor != 0 && tokens < o.params.minPerInvestor) {
            revert BelowMinimum(tokens, o.params.minPerInvestor);
        }
        if (o.params.maxPerInvestor != 0 && tokens > o.params.maxPerInvestor) {
            revert AboveMaximum(tokens, o.params.maxPerInvestor);
        }
        if (o.sold + tokens > o.params.hardCap) {
            revert HardCapExceeded(tokens, o.params.hardCap - o.sold);
        }

        // The buyer names which of the offering's accepted currencies to pay in.
        // All are priced equally, so the same cost is charged whichever is used;
        // paying in a currency the offering does not list is refused rather than
        // silently retargeted to the first one.
        if (!_accepts(o, paymentToken)) revert PaymentTokenNotAccepted(paymentToken);
        if (!IERC20Payment(paymentToken).transferFrom(msg.sender, o.treasury, cost)) {
            revert InsufficientAvailable(cost, 0);
        }
        address payment = paymentToken;
        // Lock the money the instant it lands. Until the offering settles it is
        // the investor's, refundable and unreachable by the issuer.
        ITreasuryCustody(o.treasury).lockPayment(id, payment, cost);

        o.raised += cost;
        o.sold += tokens;

        _purchases.push(
            Purchase({
                offeringId: id,
                investor: msg.sender,
                subject: bytes32(0),
                paymentToken: payment,
                paid: cost,
                tokens: tokens,
                unlockAt: o.params.lockupUntil,
                state: PURCHASE_ACTIVE
            })
        );
        uint256 pid = _purchases.length - 1;
        _byInvestor[msg.sender].push(pid);
        _byOffering[id].push(pid);

        // Tokens are **not** delivered here. A purchase during the raise is a
        // claim on tokens, settled only if the offering does. Delivering now
        // and clawing back on failure would need a seizure primitive the design
        // deliberately keeps opt-in; delivering at settlement needs none,
        // because a failed offering delivered nothing.
        emit IEvents.PurchaseRecorded(id, pid, msg.sender, cost, tokens);
    }

    /// @notice Cost, tokens and unlock date before signing anything
    /// @dev So the refusal above is never a surprise — it is reachable only by
    ///      racing another buyer in the same block.
    function previewPurchase(uint256 id, uint256 amount)
        external
        view
        returns (uint256 cost, uint256 tokens, uint64 unlockAt)
    {
        return _quote(_offerings[id], amount);
    }

    /// @dev Cost is priced from where the offering has already sold, so tiers
    ///      are consumed in order across the whole raise and a buyer pays the
    ///      band their tokens actually fall in — not one flat price for
    ///      everybody. With no tiers, the flat `price` applies. The last band's
    ///      price continues past its ceiling, so a purchase is never priced at
    ///      zero — the silent-zero failure mode an unpriced remainder would open.
    function _quote(Offering storage o, uint256 amount)
        private
        view
        returns (uint256 cost, uint256 tokens, uint64 unlockAt)
    {
        tokens = amount;
        unlockAt = o.params.lockupUntil;

        Tier[] storage tiers = o.params.tiers;
        if (tiers.length == 0) {
            cost = (amount * o.params.price) / 1e18;
            return (cost, tokens, unlockAt);
        }

        uint256 cursor = o.sold;
        uint256 remaining = amount;
        for (uint256 i = 0; i < tiers.length && remaining > 0; i++) {
            if (cursor >= tiers[i].upToAmount) continue; // an already-filled band
            uint256 take = tiers[i].upToAmount - cursor;
            if (take > remaining) take = remaining;
            cost += (take * tiers[i].price) / 1e18;
            cursor += take;
            remaining -= take;
        }
        // Anything above the final band is priced at that band, never free.
        if (remaining > 0) {
            cost += (remaining * tiers[tiers.length - 1].price) / 1e18;
        }
    }

    // ── the two permissionless calls ────────────────────────────────────────

    /// @notice Release payment to the issuer once the soft cap is met
    /// @dev **Anyone may call it.** The soft cap was met or it was not; that is
    ///      already on chain, and an operator who is absent, unwilling or
    ///      insolvent must not be able to sit on the answer.
    function settle(uint256 id) external {
        Offering storage o = _offerings[id];
        if (o.status != Status.Closed && o.status != Status.Active) {
            revert OfferingNotActive(id, uint8(o.status));
        }
        if (o.raised < o.params.softCap) revert SoftCapNotMet();

        o.status = Status.Settled;
        ITreasuryCustody(o.treasury).unlockPayments(id);
        emit IEvents.PaymentsUnlocked(id);
        emit IEvents.OfferingSettled(id, o.raised);
    }

    /// @notice Start refunds once the soft cap is missed — also permissionless
    function beginRefunding(uint256 id) external {
        Offering storage o = _offerings[id];
        if (o.status != Status.Closed && o.status != Status.Cancelled) {
            if (block.timestamp < o.params.endAt) revert OfferingNotActive(id, uint8(o.status));
        }
        if (o.raised >= o.params.softCap && o.status != Status.Cancelled) revert SoftCapMet();

        o.status = Status.Refunding;
        emit IEvents.OfferingRefundingBegan(id, o.raised, o.params.softCap);
    }

    // ── delivery, once the offering settles ─────────────────────────────────

    /// @notice Claim the tokens a settled offering owes you
    /// @dev Pull-based, because a settled offering may have thousands of
    ///      purchasers and pushing to all of them in one transaction cannot be
    ///      bounded. The distribution leg runs the token's full pipeline, so
    ///      passing the offering still never implies the right to hold.
    function claimTokens(uint256 purchaseId) external {
        Purchase storage p = _purchases[purchaseId];
        if (p.investor != msg.sender) revert NotAuthorized(msg.sender, bytes32(0));
        _deliver(purchaseId);
    }

    /// @notice Operator-pushed delivery for a batch of settled purchases
    function deliverBatch(uint256 id, uint256 limit) external {
        _onlyOperator(id);
        uint256[] storage ids = _byOffering[id];
        uint256 done;
        for (uint256 i = 0; i < ids.length && done < limit; i++) {
            if (_purchases[ids[i]].state == PURCHASE_ACTIVE) {
                _deliver(ids[i]);
                done++;
            }
        }
    }

    function _deliver(uint256 purchaseId) private {
        Purchase storage p = _purchases[purchaseId];
        if (p.state != PURCHASE_ACTIVE) revert AlreadyRefunded(purchaseId);

        Offering storage o = _offerings[p.offeringId];
        if (o.status != Status.Settled) revert OfferingNotActive(p.offeringId, uint8(o.status));

        p.state = PURCHASE_SETTLED;
        ITokenSupply(o.params.token).distributeFromTreasury(p.investor, p.tokens, p.unlockAt);
        emit IEvents.PurchaseRecorded(p.offeringId, purchaseId, p.investor, p.paid, p.tokens);
    }

    // ── refunds, both paths ─────────────────────────────────────────────────

    /// @notice Refund yourself
    /// @dev The backstop that makes refunds a guarantee rather than a service.
    function claimRefund(uint256 purchaseId) external {
        Purchase storage p = _purchases[purchaseId];
        if (p.investor != msg.sender) revert NotAuthorized(msg.sender, bytes32(0));
        _refund(purchaseId);
    }

    /// @notice Operator-pushed refund of a single purchase
    function refundPurchase(uint256 purchaseId) external {
        _onlyOperator(_purchases[purchaseId].offeringId);
        _refund(purchaseId);
    }

    function refundBatch(uint256 id, uint256 limit) external {
        _onlyOperator(id);
        uint256[] storage ids = _byOffering[id];
        uint256 done;
        for (uint256 i = 0; i < ids.length && done < limit; i++) {
            if (_purchases[ids[i]].state == PURCHASE_ACTIVE) {
                _refund(ids[i]);
                done++;
            }
        }
    }

    /// @dev **Idempotent.** `L4.10`: the state check is here, on the one path
    ///      both public entry points funnel through, so a second refund cannot
    ///      be obtained by using the other door.
    function _refund(uint256 purchaseId) private {
        Purchase storage p = _purchases[purchaseId];
        // Only an active purchase refunds. A delivered one (state Settled) is
        // finished, and a twice-refunded one is the `L4.10` case — the single
        // state check both public doors funnel through.
        if (p.state != PURCHASE_ACTIVE) revert AlreadyRefunded(purchaseId);

        Offering storage o = _offerings[p.offeringId];
        if (o.status != Status.Refunding) revert OfferingNotActive(p.offeringId, uint8(o.status));

        p.state = PURCHASE_REFUNDED;
        o.raised -= p.paid;

        // The money is in the treasury, not here. The registry can only send
        // it back to the person who paid it, and the issuer cannot reach it at
        // all while the offering is unsettled.
        ITreasuryCustody(o.treasury).refund(p.offeringId, p.paymentToken, p.investor, p.paid);
        emit IEvents.PurchaseRefunded(purchaseId, p.investor, p.paid);
    }

    // ── rules and reads ─────────────────────────────────────────────────────

    function addRule(uint256 id, address rule) external {
        _onlyOperator(id);
        _rules[id].push(rule);
    }

    function removeRule(uint256 id, address rule) external {
        _onlyOperator(id);
        address[] storage rules = _rules[id];
        for (uint256 i = 0; i < rules.length; i++) {
            if (rules[i] == rule) {
                rules[i] = rules[rules.length - 1];
                rules.pop();
                return;
            }
        }
    }

    function offeringOf(uint256 id) external view returns (OfferingParams memory) {
        return _offerings[id].params;
    }

    function statusOf(uint256 id) external view returns (uint8) {
        return uint8(_offerings[id].status);
    }

    function raisedOf(uint256 id) external view returns (uint256) {
        return _offerings[id].raised;
    }

    function purchaseOf(uint256 purchaseId) external view returns (Purchase memory) {
        return _purchases[purchaseId];
    }

    function purchasesOf(address investor) external view returns (uint256[] memory) {
        return _byInvestor[investor];
    }

    function setDefaultPaymentTokens(address[] calldata) external view {
        _onlyAdmin();
    }

    /// @notice Override a stuck offering
    /// @dev Recovery of last resort. The reason is mandatory and evented, so
    ///      an override is never indistinguishable from ordinary operation.
    function forceStatus(uint256 id, uint8 status, string calldata reason) external {
        _onlyAdmin();
        if (bytes(reason).length == 0) revert ReasonRequired();
        uint8 previous = uint8(_offerings[id].status);
        _offerings[id].status = Status(status);
        emit IEvents.OfferingStatusChanged(id, previous, status);
    }

    function _move(uint256 id, Status to) private {
        Offering storage o = _offerings[id];
        uint8 previous = uint8(o.status);
        o.status = to;
        emit IEvents.OfferingStatusChanged(id, previous, uint8(to));
    }

    /// @dev The operator is bound per offering, at creation, rather than being
    ///      a role on the registry: one registry serves every issuer on the
    ///      chain, and a chain-wide operator role would let one issuer's
    ///      operator touch another issuer's raise. The error names the
    ///      authority that was missing, so an integrator reading a revert
    ///      learns which one.
    function _onlyOperator(uint256 id) private view {
        if (msg.sender != operatorOf[id]) revert NotAuthorized(msg.sender, Roles.OFFERING_OPERATOR);
    }

    function _onlyAdmin() private view {
        if (msg.sender != admin) revert NotAuthorized(msg.sender, Roles.REGISTRY_ADMIN);
    }

    /// @dev Whether an offering lists this payment currency. A short linear
    ///      scan: the accepted set is a handful of stablecoins, not an open
    ///      market.
    function _accepts(Offering storage o, address paymentToken) private view returns (bool) {
        address[] storage accepted = o.params.paymentTokens;
        for (uint256 i = 0; i < accepted.length; i++) {
            if (accepted[i] == paymentToken) return true;
        }
        return false;
    }
}
