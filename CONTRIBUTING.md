# Contributing

## The model, stated plainly

Development is done by Stobox. Releases are published here. **Forks are welcome and expected.**

There is no roadmap vote, and pull requests are not guaranteed review. This is a source release rather
than a community-governed project. Saying so is more honest than implying participation that will not
happen — and the complaint about "open source in name only" comes from unstated expectations, not from
their absence.

## What is likely to be merged

| Likely | Unlikely |
|---|---|
| Bug fixes with a failing test | Architectural redesigns |
| Additional rules in `src/rules/` | Changes to the three-plane boundary |
| New identity adapters | Anything adding a Stobox dependency |
| Test coverage, especially invariants | Changes to storage layout |
| Documentation corrections | Feature requests without an implementation |
| Gas improvements with a snapshot | Dependency additions |

## Requirements for any pull request

1. `forge test` passes, including invariant tests.
2. New behaviour has tests. Compliance-path changes need branch coverage.
3. Documentation updated **in the same pull request** as the code.
4. `python3 build-docs.py` run and the output committed.
5. `forge snapshot` updated if gas changed.
6. No new dependency without discussion first.
7. No reference to any Stobox address, to STBU, or to any datapoint schema. This is enforced by a CI
   scan — see [docs/19-open-boundary.md](docs/19-open-boundary.md).

## Writing a rule

Rules are the intended extension point and need no permission.

1. Implement `IRule`. Keep `check` pure and cheap — it runs on every transfer.
2. Read only from `IIdentityRegistry`, token views and `Context`.
3. Return a short, specific `reason`; it surfaces directly in `whyBlocked`.
4. Never revert for an ordinary "no" — return `(false, reason)`.
5. Add tests for both the passing and the failing case.

A new claim key plus a new rule adds a jurisdiction to the system without touching any core contract.

## Style

Solidity 0.8.28, `forge fmt`, NatSpec on every external function. Prose in documentation uses full
sentences and avoids marketing language.
