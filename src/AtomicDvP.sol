// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "./interfaces/IErrors.sol";
import {IEvents} from "./interfaces/IEvents.sol";
import {Instruction} from "./interfaces/IAgentAndSettlement.sol";

interface IERC20Leg {
    function transferFrom(address from, address to, uint256 amount) external returns (bool);
}

interface ICompliantToken {
    function canTransfer(address from, address to, uint256 amount) external view returns (bool);
    function whyBlocked(address from, address to, uint256 amount)
        external
        view
        returns (uint8 stage, address rule, string memory reason);
}

/// @title Delivery versus payment, atomically
/// @notice Both legs in one transaction, with compliance checked **inside**
///         settlement rather than before it — where the answer could go stale
///         between the check and the move.
/// @dev There is no block in which one leg has moved and the other has not.
///      Settlement risk cannot occur here, rather than being managed.
contract AtomicDvP is IErrors {
    bytes32 public immutable DOMAIN_SEPARATOR;

    bytes32 private constant INSTRUCTION_TYPEHASH = keccak256(
        "Instruction(address securityToken,address paymentToken,address seller,address buyer,uint256 securityAmount,uint256 paymentAmount,uint64 validUntil,bytes32 nonce,bytes32 tradeRef)"
    );

    // Keyed by the instruction digest, not the bare nonce. The nonce alone
    // does not name the parties, so a state keyed on it conflates two different
    // trades that happen to share one — which is exactly how a bystander was
    // able to cancel a trade they were not part of. The digest binds every
    // term, so a forged instruction cannot reach a genuine one's state.
    mapping(bytes32 => bool) public isSettled;
    mapping(bytes32 => bool) public isCancelled;

    constructor() {
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256("EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"),
                keccak256("uRWA AtomicDvP"),
                keccak256("1"),
                block.chainid,
                address(this)
            )
        );
    }

    /// @notice Settle a trade both parties have signed
    /// @dev Either party or their agent may submit it. The signatures are the
    ///      authority; the submitter is only paying the gas.
    function settle(Instruction calldata i, bytes calldata sellerSig, bytes calldata buyerSig)
        external
        returns (bytes32 settlementId)
    {
        if (block.timestamp > i.validUntil) revert InstructionExpired(i.validUntil);
        // A zero-address party would be satisfied by a garbage signature, since
        // `_recover` returns the zero address for one — so the signature check
        // below would pass without any real signature existing.
        if (i.seller == address(0) || i.buyer == address(0)) revert ZeroAddress();

        bytes32 digest = _digest(i);
        if (isSettled[digest]) revert NonceAlreadySettled(i.nonce);
        if (isCancelled[digest]) revert NonceAlreadySettled(i.nonce);

        if (_recover(digest, sellerSig) != i.seller) revert BadSignature(i.seller);
        if (_recover(digest, buyerSig) != i.buyer) revert BadSignature(i.buyer);

        // Checked here, not earlier: an answer obtained before the payment leg
        // could be stale by the time the security leg runs.
        if (!ICompliantToken(i.securityToken).canTransfer(i.seller, i.buyer, i.securityAmount)) {
            // The error keeps the signature ERC-7943 fixes; the refusing rule's
            // reason is available through `previewSettle`, which a caller should
            // have asked first and which costs nothing.
            revert ERC7943CannotTransfer(i.seller, i.buyer, i.securityAmount);
        }

        isSettled[digest] = true;

        // Payment first, then delivery. Either both move or the transaction
        // reverts and neither did.
        if (!IERC20Leg(i.paymentToken).transferFrom(i.buyer, i.seller, i.paymentAmount)) {
            revert InsufficientAvailable(i.paymentAmount, 0);
        }
        if (!IERC20Leg(i.securityToken).transferFrom(i.seller, i.buyer, i.securityAmount)) {
            revert InsufficientAvailable(i.securityAmount, 0);
        }

        settlementId = keccak256(abi.encode(i.nonce, block.number));
        emit IEvents.Settled(settlementId, i.seller, i.buyer, i.tradeRef);
    }

    /// @notice Would this settle — free, and names the rule that would refuse
    function previewSettle(Instruction calldata i) external view returns (bool ok, string memory reason) {
        if (block.timestamp > i.validUntil) return (false, "instruction expired");
        if (i.seller == address(0) || i.buyer == address(0)) return (false, "a party is the zero address");
        bytes32 digest = _digest(i);
        if (isSettled[digest]) return (false, "already settled");
        if (isCancelled[digest]) return (false, "cancelled");

        try ICompliantToken(i.securityToken).canTransfer(i.seller, i.buyer, i.securityAmount) returns (bool allowed) {
            if (allowed) return (true, "");
        } catch {
            return (false, "the security token could not be read");
        }

        try ICompliantToken(i.securityToken).whyBlocked(i.seller, i.buyer, i.securityAmount) returns (
            uint8, address, string memory why
        ) {
            return (false, why);
        } catch {
            return (false, "the security leg would be refused");
        }
    }

    /// @notice Withdraw a signed instruction before it settles
    /// @dev Either party may cancel. A trade one side has repudiated should not
    ///      remain settleable by the other until it expires.
    ///
    ///      Cancellation is recorded against the instruction **digest**, not the
    ///      nonce. That is what makes the party check meaningful: an attacker
    ///      can forge an instruction naming themselves as both parties and any
    ///      nonce they like, and it passes the check below — but its digest is
    ///      its own, so it cancels only that forgery, never the genuine trade
    ///      whose digest binds the real seller, buyer and terms.
    function cancel(Instruction calldata i) external {
        if (msg.sender != i.seller && msg.sender != i.buyer) {
            revert NotAuthorized(msg.sender, i.nonce);
        }
        isCancelled[_digest(i)] = true;
    }

    /// @notice The digest under which an instruction's settlement state is kept
    /// @dev `isSettled` and `isCancelled` are keyed by this, not the nonce. A
    ///      caller asking "did this settle?" passes the instruction through here
    ///      first.
    function digestOf(Instruction calldata i) external view returns (bytes32) {
        return _digest(i);
    }

    function _digest(Instruction calldata i) private view returns (bytes32) {
        bytes32 structHash = keccak256(
            abi.encode(
                INSTRUCTION_TYPEHASH,
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
        return keccak256(abi.encodePacked("\x19\x01", DOMAIN_SEPARATOR, structHash));
    }

    function _recover(bytes32 digest, bytes calldata sig) private pure returns (address) {
        if (sig.length != 65) return address(0);
        bytes32 r = bytes32(sig[0:32]);
        bytes32 s = bytes32(sig[32:64]);
        uint8 v = uint8(sig[64]);
        // Reject the malleable upper half of the curve order, so one signature
        // cannot be replayed in a second, equally valid form.
        if (uint256(s) > 0x7FFFFFFFFFFFFFFFFFFFFFFFFFFFFFFF5D576E7357A4501DDFE92F46681B20A0) {
            return address(0);
        }
        return ecrecover(digest, v, r, s);
    }
}
