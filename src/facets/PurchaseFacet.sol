// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "../interfaces/IErrors.sol";
import {Layout} from "../storage/Layout.sol";

/// @dev The slice of the offering registry this facet forwards to.
interface IRegistryDoor {
    function purchaseFor(uint256 id, uint256 amount, address paymentToken, address investor) external;
    function claimRefundFor(uint256 purchaseId, address investor) external;
    function previewPurchase(uint256 id, uint256 amount)
        external
        view
        returns (uint256 cost, uint256 tokens, uint64 unlockAt);
}

/// @title The offering entry point on the token side
/// @notice Optional. A wallet that knows the token's address can subscribe,
///         preview and claim a refund without ever learning the registry's —
///         one address for everything an investor does.
/// @dev A thin door, deliberately: it forwards the caller as the investor and
///      holds neither leg of the money. Every check — bounds, rules, currency,
///      caps — lives in the registry's single `_purchase` path, so this facet
///      cannot be a way around any of it. The registry accepts the call only
///      from the token whose offering it is, which is what makes forwarding
///      the investor's identity safe.
contract PurchaseFacet is IErrors {
    function purchase(uint256 offeringId, uint256 amount, address paymentToken) external {
        IRegistryDoor(_registry()).purchaseFor(offeringId, amount, paymentToken, msg.sender);
    }

    function previewPurchase(uint256 offeringId, uint256 amount)
        external
        view
        returns (uint256 cost, uint256 tokens, uint64 unlockAt)
    {
        return IRegistryDoor(_registry()).previewPurchase(offeringId, amount);
    }

    /// @notice Claim your refund through the token
    /// @dev The same guarantee as the registry's own door: soft cap missed, the
    ///      investor gets their money back without anyone's permission.
    function refundPurchase(uint256 purchaseId) external {
        IRegistryDoor(_registry()).claimRefundFor(purchaseId, msg.sender);
    }

    function _registry() private view returns (address registry) {
        registry = Layout.monetary().offeringRegistry;
        if (registry == address(0)) revert OfferingRegistryNotSet();
    }
}
