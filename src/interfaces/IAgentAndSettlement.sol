// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @notice What an agent is permitted to do, and no more
/// @dev `expiresAt` is a required field, not an option. There is no perpetual
///      mandate in the type.
struct Mandate {
    address principal;
    address agent;
    bytes32[] scopes;
    address[] tokens;
    address[] counterparties; // empty = any
    uint256 maxPerAction;
    uint256 maxPerEpoch;
    uint64 epochLength;
    uint64 expiresAt;
    bool revoked;
}

/// @title Bounded automation
/// @notice The agent is not trusted to respect its mandate. It is **unable to
///         exceed it** — every scoped action consumes against the limit before
///         any state changes, and reverts if it would go over.
/// @dev No scope grants minting, role changes, upgrades, freezing, seizure or
///      pause. Those are absent from the type, not merely unset by default.
interface IAgentAuthority {
    function grant(Mandate calldata mandate) external returns (bytes32 mandateId);
    function revoke(bytes32 mandateId) external;

    /// @notice Would this action be permitted — free, never reverts
    function check(bytes32 mandateId, bytes32 scope, address token, address counterparty, uint256 amount)
        external
        view
        returns (bool ok, string memory reason);

    /// @notice Consume against the mandate's limits, or revert
    function consume(bytes32 mandateId, bytes32 scope, address token, address counterparty, uint256 amount) external;

    function mandateOf(bytes32 mandateId) external view returns (Mandate memory);
    function consumed(bytes32 mandateId) external view returns (uint256 thisEpoch, uint64 epochEnds);

    /// @notice Every mandate a principal has granted
    function mandatesOf(address principal) external view returns (bytes32[] memory);
}

/// @notice A trade both sides have signed, off chain
struct Instruction {
    address securityToken;
    address paymentToken;
    address seller;
    address buyer;
    uint256 securityAmount;
    uint256 paymentAmount;
    uint64 validUntil;
    bytes32 nonce;
    bytes32 tradeRef; // reporting reference, opaque to the contract
}

/// @title Delivery versus payment, atomically
/// @notice Both legs in one transaction, with compliance checked **inside**
///         settlement rather than before it — where the answer could go stale
///         in between.
/// @dev There is no block in which one leg has moved and the other has not.
///      Settlement risk cannot occur here, rather than being managed.
interface IAtomicDvP {
    function settle(Instruction calldata instruction, bytes calldata sellerSig, bytes calldata buyerSig)
        external
        returns (bytes32 settlementId);

    /// @notice Would this settle — free, and names the rule that would refuse
    function previewSettle(Instruction calldata instruction) external view returns (bool ok, string memory reason);

    /// @notice Withdraw a signed instruction before it settles — either party
    function cancel(Instruction calldata instruction) external;

    /// @notice The digest keying an instruction's settlement state
    function digestOf(Instruction calldata instruction) external view returns (bytes32);

    /// @notice Whether the instruction with this digest has settled
    /// @dev Keyed by digest — pass an instruction through `digestOf` first.
    function isSettled(bytes32 digest) external view returns (bool);
}
