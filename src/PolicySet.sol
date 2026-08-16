// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import {IErrors} from "./interfaces/IErrors.sol";
import {IEvents} from "./interfaces/IEvents.sol";
import {IRule, RuleContext} from "./interfaces/IPolicy.sol";

/// @dev The token views the policy set needs. Reading them keeps rules pure:
///      a holder cap is a fact the token already maintains, not state a rule has
///      to keep for itself.
interface ITokenView {
    function subjectOf(address wallet) external view returns (bytes32);
    function subjectHolderCount() external view returns (uint256);
}

/// @title A composed rule set
/// @notice **Groups AND together; rules within a group OR.** That covers every
///         real jurisdictional case — "professional in the EU or accredited in
///         the US" being the canonical one — without a general boolean engine,
///         which is the easiest place in the system to misconfigure a live
///         compliance policy and the hardest thing to audit.
contract PolicySet is IErrors {
    /// @dev Identical for every token. A configurable ceiling turns a working
    ///      rule into a silent refusal that reads as a compliance decision.
    uint256 public constant RULE_GAS_CEILING = 100_000;

    /// @dev Bounded so an admin cannot attach rules until a transfer no longer
    ///      fits in a block. Griefing by configuration is still griefing.
    uint256 public constant MAX_RULES = 24;

    address public owner;
    bytes32[] private _groups;
    mapping(bytes32 => address[]) private _rules;
    uint256 public ruleCount;

    constructor(address owner_) {
        owner = owner_;
    }

    /// @notice Would this transfer pass every group
    /// @dev Never reverts. A rule that reverts or exhausts its ceiling counts
    ///      as a refusal — a broken rule never opens the gate.
    function evaluate(address from, address to, uint256 amount)
        external
        view
        returns (bool ok, address failingRule, string memory reason)
    {
        RuleContext memory ctx = _context(from, to);

        for (uint256 g = 0; g < _groups.length; g++) {
            address[] storage rules = _rules[_groups[g]];
            if (rules.length == 0) continue;

            bool groupPassed;
            address firstFailure;
            string memory firstReason;

            for (uint256 i = 0; i < rules.length; i++) {
                (bool passed, string memory why) = _check(rules[i], from, to, amount, ctx);
                if (passed) {
                    groupPassed = true;
                    break;
                }
                if (firstFailure == address(0)) {
                    firstFailure = rules[i];
                    firstReason = why;
                }
            }

            if (!groupPassed) return (false, firstFailure, firstReason);
        }
        return (true, address(0), "");
    }

    /// @dev The `try` is the whole point. A third-party rule is untrusted code
    ///      running inside a transfer, and the only safe reading of its failure
    ///      is refusal.
    function _check(address rule, address from, address to, uint256 amount, RuleContext memory ctx)
        private
        view
        returns (bool, string memory)
    {
        try IRule(rule).check{gas: RULE_GAS_CEILING}(from, to, amount, ctx) returns (bool ok, string memory reason) {
            return (ok, reason);
        } catch {
            return (false, "rule reverted or exceeded its gas ceiling");
        }
    }

    /// @dev Reads are wrapped too: the policy set must answer even when
    ///      attached to a token that does not serve these views.
    function _context(address from, address to) private view returns (RuleContext memory ctx) {
        ctx.token = msg.sender;
        try ITokenView(msg.sender).subjectOf(from) returns (bytes32 s) {
            ctx.fromSubject = s;
        } catch {
            ctx.fromSubject = keccak256(abi.encodePacked(from));
        }
        try ITokenView(msg.sender).subjectOf(to) returns (bytes32 s) {
            ctx.toSubject = s;
        } catch {
            ctx.toSubject = keccak256(abi.encodePacked(to));
        }
        try ITokenView(msg.sender).subjectHolderCount() returns (uint256 n) {
            ctx.subjectHolderCount = n;
        } catch {}
    }

    // ── composition ─────────────────────────────────────────────────────────

    function groups() external view returns (bytes32[] memory) {
        return _groups;
    }

    function rulesOf(bytes32 group) external view returns (address[] memory) {
        return _rules[group];
    }

    function maxRules() external pure returns (uint256) {
        return MAX_RULES;
    }

    function addGroup(bytes32 group) external {
        _onlyOwner();
        for (uint256 i = 0; i < _groups.length; i++) {
            if (_groups[i] == group) return;
        }
        _groups.push(group);
    }

    function removeGroup(bytes32 group) external {
        _onlyOwner();
        ruleCount -= _rules[group].length;
        delete _rules[group];
        for (uint256 i = 0; i < _groups.length; i++) {
            if (_groups[i] == group) {
                _groups[i] = _groups[_groups.length - 1];
                _groups.pop();
                return;
            }
        }
    }

    function addRule(bytes32 group, address rule) external {
        _onlyOwner();
        if (rule == address(0)) revert ZeroAddress();
        if (ruleCount >= MAX_RULES) revert RuleLimitExceeded(ruleCount, MAX_RULES);
        _rules[group].push(rule);
        ruleCount++;
    }

    function removeRule(bytes32 group, address rule) external {
        _onlyOwner();
        address[] storage rules = _rules[group];
        for (uint256 i = 0; i < rules.length; i++) {
            if (rules[i] == rule) {
                rules[i] = rules[rules.length - 1];
                rules.pop();
                ruleCount--;
                return;
            }
        }
    }

    function _onlyOwner() private view {
        if (msg.sender != owner) revert NotAuthorized(msg.sender, bytes32(0));
    }
}
