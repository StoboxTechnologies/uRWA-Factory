// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title Per-token custody
/// @notice One treasury per token. A compromise reaches exactly one asset.
/// @dev The treasury holds tokens as an ordinary holder — the compliance
///      pipeline applies to it too, which is why the factory adds it to the
///      trust list explicitly rather than special-casing it in code.
interface ITreasury {
    function token() external view returns (address);
    function availableBalance() external view returns (uint256);

    function deposit(address asset, uint256 amount) external;
    function reserve(uint256 amount, uint256 offeringId) external;
    function release(uint256 amount, uint256 offeringId) external;
    function reservedOf(uint256 offeringId) external view returns (uint256);

    /// @notice Hold investor payment until the soft cap decides its fate
    function lockPayments(uint256 offeringId) external;
    function unlockPayments(uint256 offeringId) external;

    function withdrawERC20(address asset, address to, uint256 amount) external;
}

/// @notice Everything an investor must be able to read before subscribing
struct OfferingParams {
    address token;
    address[] paymentTokens;
    uint256 price; // per whole token, in payment-token units
    uint256 softCap;
    uint256 hardCap;
    uint256 minPerInvestor;
    uint256 maxPerInvestor;
    uint64 startAt;
    uint64 endAt;
    uint64 lockupUntil; // 0 = no lockup on distributed tokens
    bool preMint; // pre-mint to treasury, or mint on purchase
    bytes32 regime;
}

struct Purchase {
    uint256 offeringId;
    address investor;
    bytes32 subject;
    address paymentToken;
    uint256 paid;
    uint256 tokens;
    uint64 unlockAt;
    uint8 state;
}

/// @title Primary issuance
interface IOfferingRegistry {
    function createOffering(OfferingParams calldata params) external returns (uint256 id);
    function activate(uint256 id) external;
    function pause(uint256 id) external;
    function unpause(uint256 id) external;
    function close(uint256 id) external;
    function cancel(uint256 id, string calldata reason) external;

    /// @notice Subscribe
    /// @dev Reverts whole if `amount` exceeds what the hard cap still allows.
    ///      No partial fill: it would add a refund path to the money leg and
    ///      let a purchase succeed for an amount nobody agreed to.
    function purchase(uint256 id, uint256 amount) external;

    /// @notice Cost, tokens and unlock date before signing anything
    function previewPurchase(uint256 id, uint256 amount)
        external
        view
        returns (uint256 cost, uint256 tokens, uint64 unlockAt);

    /// @notice Release payment to the issuer once the soft cap is met
    /// @dev **Permissionless.** A mechanical consequence of facts already on
    ///      chain; requiring an operator would let an absent one hold investor
    ///      funds hostage.
    function settle(uint256 id) external;

    /// @notice Start refunds once the soft cap is missed — also permissionless
    function beginRefunding(uint256 id) external;
    function refundBatch(uint256 id, uint256 limit) external;

    /// @notice Refund yourself; the backstop that makes refunds a guarantee
    function claimRefund(uint256 purchaseId) external;

    function addRule(uint256 id, address rule) external;
    function removeRule(uint256 id, address rule) external;

    function offeringOf(uint256 id) external view returns (OfferingParams memory);
    function statusOf(uint256 id) external view returns (uint8);
    function raisedOf(uint256 id) external view returns (uint256);
    function purchaseOf(uint256 purchaseId) external view returns (Purchase memory);
    function purchasesOf(address investor) external view returns (uint256[] memory);

    function setDefaultPaymentTokens(address[] calldata tokens) external;
    function forceStatus(uint256 id, uint8 status, string calldata reason) external;
}
