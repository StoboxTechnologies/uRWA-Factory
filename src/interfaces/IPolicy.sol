// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

/// @title What a rule is told about a transfer
/// @dev Subject identifiers rather than addresses, because a holder cap that
///      counts addresses is defeated by one investor with several wallets.
struct RuleContext {
    address token;
    bytes32 fromSubject;
    bytes32 toSubject;
    uint256 subjectHolderCount;
}

/// @title A single compliance rule
/// @notice **Pure predicates.** A rule never writes. Where one appears to need
///         state — a holder cap — the token maintains the counter in transfer
///         accounting and the rule reads it through `RuleContext`. That is what
///         keeps every rule replaceable without a data migration.
interface IRule {
    /// @notice May this transfer proceed under this rule
    /// @dev Called under a gas ceiling of 100,000. Exceeding it, or reverting,
    ///      counts as a **refusal** — a broken rule never opens the gate.
    function check(address from, address to, uint256 amount, RuleContext calldata ctx)
        external
        view
        returns (bool ok, string memory reason);

    /// @notice Investment bounds this rule implies for an account
    /// @dev How accreditation-linked minimums reach the offering registry
    ///      without any rule mutating anything.
    function bounds(address account) external view returns (uint256 min, uint256 max);

    function ruleId() external view returns (bytes32);
}

/// @title A composed rule set
/// @notice **Groups AND together; rules within a group OR.** That covers every
///         real jurisdictional case — "professional in the EU or accredited in
///         the US" being the canonical one — without a general boolean engine,
///         which is the easiest place in the system to misconfigure a live
///         compliance policy and the hardest thing to audit.
interface IPolicySet {
    function evaluate(address from, address to, uint256 amount)
        external
        view
        returns (bool ok, address failingRule, string memory reason);

    function groups() external view returns (bytes32[] memory);
    function rulesOf(bytes32 group) external view returns (address[] memory);
    function ruleCount() external view returns (uint256);

    function addGroup(bytes32 group) external;
    function removeGroup(bytes32 group) external;
    function addRule(bytes32 group, address rule) external;
    function removeRule(bytes32 group, address rule) external;
}
