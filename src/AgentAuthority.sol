// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "./interfaces/IErrors.sol";
import {IEvents} from "./interfaces/IEvents.sol";
import {Mandate} from "./interfaces/IAgentAndSettlement.sol";

/// @title Bounded automation
/// @notice The agent is **not trusted** to respect its mandate. It is unable to
///         exceed it: every scoped action consumes against the limits before
///         any state changes, and reverts if it would go over.
/// @dev No scope grants minting, role changes, upgrades, freezing, seizure or
///      pause. Those are absent from what this contract can express, not merely
///      unset by default — a configurable list would eventually be configured.
contract AgentAuthority is IErrors {
    struct Consumption {
        uint256 spent;
        uint64 epochEnds;
    }

    mapping(bytes32 => Mandate) private _mandates;
    mapping(bytes32 => Consumption) private _consumed;
    mapping(address => bytes32[]) private _byPrincipal;

    /// @dev Scopes an agent may hold. Deliberately short, and deliberately
    ///      without an "admin" or "any" entry.
    bytes32 public constant SCOPE_TRANSFER = keccak256("agent.scope.transfer");
    bytes32 public constant SCOPE_SETTLE = keccak256("agent.scope.settle");
    bytes32 public constant SCOPE_READ = keccak256("agent.scope.read");

    function grant(Mandate calldata mandate) external returns (bytes32 mandateId) {
        if (mandate.agent == address(0)) revert ZeroAddress();
        if (mandate.expiresAt <= block.timestamp) revert MandateExpired(bytes32(0), mandate.expiresAt);
        // A per-epoch cap with a zero-length epoch is a cap that never binds:
        // every `consume` would find the window already over and reset the
        // spend to zero before adding to it. Reject the misconfiguration at the
        // grant rather than let the agent draw without limit believing one held.
        if (mandate.maxPerEpoch != 0 && mandate.epochLength == 0) revert EpochlessCap();

        mandateId = keccak256(abi.encode(msg.sender, mandate.agent, mandate.expiresAt, _byPrincipal[msg.sender].length));
        Mandate storage m = _mandates[mandateId];
        m.principal = msg.sender;
        m.agent = mandate.agent;
        m.scopes = mandate.scopes;
        m.tokens = mandate.tokens;
        m.counterparties = mandate.counterparties;
        m.maxPerAction = mandate.maxPerAction;
        m.maxPerEpoch = mandate.maxPerEpoch;
        m.epochLength = mandate.epochLength;
        m.expiresAt = mandate.expiresAt;

        _byPrincipal[msg.sender].push(mandateId);
        emit IEvents.MandateGranted(mandateId, msg.sender, mandate.agent);
    }

    /// @notice End a mandate
    /// @dev Takes effect on the next action, with no timelock. An agent
    ///      misbehaving at three in the morning is stopped at three in the
    ///      morning.
    function revoke(bytes32 mandateId) external {
        Mandate storage m = _mandates[mandateId];
        if (msg.sender != m.principal) revert NotAuthorized(msg.sender, bytes32(0));
        m.revoked = true;
        emit IEvents.MandateRevoked(mandateId);
    }

    /// @notice Would this action be permitted — free, and never reverts
    /// @dev So an agent can decide not to try, rather than learning by failing
    ///      and paying for it.
    function check(bytes32 mandateId, bytes32 scope, address token, address counterparty, uint256 amount)
        external
        view
        returns (bool ok, string memory reason)
    {
        Mandate storage m = _mandates[mandateId];

        if (m.agent == address(0)) return (false, "no such mandate");
        if (m.revoked) return (false, "mandate revoked");
        if (m.expiresAt <= block.timestamp) return (false, "mandate expired");
        if (!_listed(m.scopes, scope)) return (false, "action outside the mandate's scopes");
        if (m.tokens.length != 0 && !_listedAddress(m.tokens, token)) return (false, "token not in the mandate");
        if (m.counterparties.length != 0 && !_listedAddress(m.counterparties, counterparty)) {
            return (false, "counterparty not in the mandate");
        }
        if (m.maxPerAction != 0 && amount > m.maxPerAction) return (false, "over the per-action limit");

        if (m.maxPerEpoch != 0) {
            Consumption storage c = _consumed[mandateId];
            uint256 spent = block.timestamp >= c.epochEnds ? 0 : c.spent;
            if (spent + amount > m.maxPerEpoch) return (false, "over the limit for this epoch");
        }
        return (true, "");
    }

    /// @notice Draw against the mandate, or revert
    /// @dev Called by the scoped function **before** it changes anything, so a
    ///      refusal leaves no partial effect behind. It enforces **every**
    ///      dimension of the mandate — scope, token, counterparty and the
    ///      limits — not just the amounts. `check` is the free advisory mirror
    ///      of this; an agent that skips it and calls `consume` directly is
    ///      still unable to act outside its scope, spend on the wrong token or
    ///      trade with the wrong counterparty, because this is the path that
    ///      actually authorises the action.
    function consume(bytes32 mandateId, bytes32 scope, address token, address counterparty, uint256 amount) external {
        Mandate storage m = _mandates[mandateId];
        if (msg.sender != m.agent) revert NotAuthorized(msg.sender, bytes32(0));
        if (m.revoked) revert MandateIsRevoked(mandateId);
        if (m.expiresAt <= block.timestamp) revert MandateExpired(mandateId, m.expiresAt);
        if (!_listed(m.scopes, scope)) revert OutOfScope(mandateId, scope);
        if (m.tokens.length != 0 && !_listedAddress(m.tokens, token)) revert TokenNotInMandate(token);
        if (m.counterparties.length != 0 && !_listedAddress(m.counterparties, counterparty)) {
            revert CounterpartyNotInMandate(counterparty);
        }
        if (m.maxPerAction != 0 && amount > m.maxPerAction) {
            revert PerActionLimitExceeded(amount, m.maxPerAction);
        }

        if (m.maxPerEpoch != 0) {
            Consumption storage c = _consumed[mandateId];
            if (block.timestamp >= c.epochEnds) {
                c.spent = 0;
                c.epochEnds = uint64(block.timestamp) + m.epochLength;
            }
            if (c.spent + amount > m.maxPerEpoch) {
                revert PerEpochLimitExceeded(amount, m.maxPerEpoch - c.spent);
            }
            c.spent += amount;
        }

        emit IEvents.AgentActed(mandateId, msg.sender, m.principal, msg.sig, amount);
    }

    function mandateOf(bytes32 mandateId) external view returns (Mandate memory) {
        return _mandates[mandateId];
    }

    function mandatesOf(address principal) external view returns (bytes32[] memory) {
        return _byPrincipal[principal];
    }

    function consumed(bytes32 mandateId) external view returns (uint256 thisEpoch, uint64 epochEnds) {
        Consumption storage c = _consumed[mandateId];
        if (block.timestamp >= c.epochEnds) return (0, c.epochEnds);
        return (c.spent, c.epochEnds);
    }

    function _listed(bytes32[] storage set, bytes32 v) private view returns (bool) {
        for (uint256 i = 0; i < set.length; i++) {
            if (set[i] == v) return true;
        }
        return false;
    }

    function _listedAddress(address[] storage set, address v) private view returns (bool) {
        for (uint256 i = 0; i < set.length; i++) {
            if (set[i] == v) return true;
        }
        return false;
    }
}
