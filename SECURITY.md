# Security policy

## Reporting a vulnerability

**Do not open a public issue.**

Email `security@stobox.io` with a description, affected versions, and a reproduction if you have one.

You will get an acknowledgement. Where a report leads to a fix, credit is offered in the release notes
unless you prefer otherwise.

## Scope

| In scope | Out of scope |
|---|---|
| Contracts in `src/` at a tagged release | Third-party forks |
| The compliance pipeline and rules | Deployment misconfiguration |
| Passport proof and snapshot format | Off-chain Stobox infrastructure |
| Agent authority and settlement | Issues in dependencies — report upstream |

## Status

This project is **specification stage — no implementation exists yet.** Audit and bug bounty follow
Phase 3 of the [development plan](docs/20-development-plan.md).

**No mainnet issuance until an audit clears.** Code and testnet deployments are public from the end of
Phase 1 precisely so that review can begin early.

## Known design constraints

These are deliberate and documented, not vulnerabilities:

- Attribute values in StoboxDID are world-readable by design; the pipeline must read them from a
  `view` context. Values must be hashes, never plaintext.
- Unchanged passport leaves keep the same commitment across snapshots, revealing which fields changed
  and when.
- A compromised `UPGRADE_ADMIN` can halt transfers. It cannot alter balances or supply.

See [docs/17-security.md](docs/17-security.md).
