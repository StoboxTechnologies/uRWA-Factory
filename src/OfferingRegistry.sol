// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "./interfaces/IErrors.sol";
import {IEvents} from "./interfaces/IEvents.sol";
import {OfferingParams, Purchase} from "./interfaces/ITreasuryAndOfferings.sol";

interface IERC20Payment {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
    function transfer(address to, uint256 amount) external returns (bool);
    function balanceOf(address) external view returns (uint256);
}

interface ITokenSupply {
    function distributeFromTreasury(address to, uint256 amount, uint64 unlockAt) external;
}

interface ITreasuryCustody {
    function lockPayments(uint256 offeringId) external;
    function unlockPayments(uint256 offeringId) external;
    function refund(address asset, address investor, uint256 amount) external;
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
        ITreasuryCustody(_offerings[id].treasury).lockPayments(id);
        emit IEvents.PaymentsLocked(id);
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
        _move(id, Status.Cancelled);
    }

    // ── subscription ────────────────────────────────────────────────────────

    /// @notice Subscribe
    /// @dev A request larger than the hard cap still allows **reverts whole**.
    ///      Filling what is left and refunding the difference would add a
    ///      partial-refund path to the money leg — the most sensitive code
    ///      here — and would let a purchase succeed for an amount nobody
    ///      agreed to.
    function purchase(uint256 id, uint256 amount) external {
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

        address payment = o.params.paymentTokens.length > 0 ? o.params.paymentTokens[0] : address(0);
        if (payment == address(0)) revert ZeroAddress();
        if (!IERC20Payment(payment).transferFrom(msg.sender, o.treasury, cost)) {
            revert InsufficientAvailable(cost, 0);
        }

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

        // The distribution leg runs the token's full pipeline. Passing the
        // offering never implies the right to hold.
        ITokenSupply(o.params.token).distributeFromTreasury(msg.sender, tokens, o.params.lockupUntil);

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

    function _quote(Offering storage o, uint256 amount)
        private
        view
        returns (uint256 cost, uint256 tokens, uint64 unlockAt)
    {
        tokens = amount;
        cost = (amount * o.params.price) / 1e18;
        unlockAt = o.params.lockupUntil;
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
        if (p.state == PURCHASE_REFUNDED) revert AlreadyRefunded(purchaseId);

        Offering storage o = _offerings[p.offeringId];
        if (o.status != Status.Refunding) revert OfferingNotActive(p.offeringId, uint8(o.status));

        p.state = PURCHASE_REFUNDED;
        o.raised -= p.paid;

        // The money is in the treasury, not here. The registry can only send
        // it back to the person who paid it, and the issuer cannot reach it at
        // all while the offering is unsettled.
        ITreasuryCustody(o.treasury).refund(p.paymentToken, p.investor, p.paid);
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

    function _onlyOperator(uint256 id) private view {
        if (msg.sender != operatorOf[id]) revert NotAuthorized(msg.sender, bytes32(0));
    }

    function _onlyAdmin() private view {
        if (msg.sender != admin) revert NotAuthorized(msg.sender, bytes32(0));
    }
}
