# 35 — The auditor pack

What an external auditor, a transfer agent or a custodian receives when they ask "show me the
register at a date, and prove it". This document is the specification the pack is built to; the
pack itself is generated, never hand-written. First delivered in Phase 1a against Base Sepolia,
checked against the SPV register at the first mainnet close (Phase 3).

## What it contains

| Section | Content | Source |
|---|---|---|
| Register | Every holder (by subject, then by wallet) with balance, locked amount and lockup schedule at block `N` | `Transfer`, `LockupAdded`, `LockupCleared`, `ForcedTransfer`, `SubjectResynced` |
| Supply | `totalSupply`, `totalIssued`, `maxSupply`, `capLocked` at `N`, and the issue and redeem history | `Issued`, `Redeemed`, `CapLocked`, `ForcedOperation` |
| Controls | Every role grant and revoke, every scheduled and executed cut, every setter change, with timestamps and the delay they waited | `RoleGranted`, `RoleRevoked`, `UpgradeScheduled`, `UpgradeExecuted`, `DiamondCut`, `RoleTransferred` |
| Compliance | Every refused transfer with its stage and rule, every rule and group change, every trust and distrust | `TransferRefused`, `RuleFailed`, `RuleAdded`, `RuleRemoved`, `Trusted`, `Distrusted` |
| Identity | For each subject: wallets bound, claims in force at `N` and their issuers, without personal data | `WalletBound`, `WalletUnbound`, `SubjectChanged`, `ClaimSet` |
| Figures | Every oracle record consumed by the token in the period, with signer set and confirmation | `FigureRecorded`, `FigureConfirmed` |
| Reconciliation | The register above against the SPV's own share register: matched, unmatched, drift | `AccountingDrift`, the SPV register export |

## How it is built

1. Read every event of the token, its registry, its policy set and its oracle from `eth_getLogs`
   between the creation block and `N`, from a clean environment with no database and no cache.
2. Replay them into the tables above. Nothing in the pack comes from a `view` call; every view
   result is included only as a cross-check column.
3. Reconcile: `Σ balances == totalSupply`, `Σ locked ≤ Σ balances`, every holder with a balance has
   an accounted subject, every subject with a balance has a valid base claim at `N` or is trusted.
4. Sign the pack (SHA-256 of the archive, signed by the RELAY key) and anchor the hash in the
   decision log.

## What it never contains

- Names, documents, addresses or any personal data. Subjects are `keccak256(uDID)`; the key file
  that maps a subject to a person is released only under NDA, only for the subjects the requester
  is entitled to, and its release is itself logged.
- Any figure that was not signed on chain.
- Any claim the pack cannot rebuild from logs.

## Acceptance

- An outside engineer with the archive, a Base RPC and this document rebuilds the register and
  matches the pack's own tables byte for byte.
- The controls matrix (`docs/35-auditor-pack.md` appendix, one row per assertion: existence,
  completeness, rights, valuation, cut-off) names the event and the check that evidences each row.
- The first mainnet pack reconciles to the SPV register with zero unexplained drift.

## Appendix — controls matrix

| Assertion | Evidence | Check |
|---|---|---|
| Existence | `Issued` before any balance | no balance without an issue path |
| Completeness | `Transfer` set is closed under replay | replay balance equals ledger balance |
| Rights and obligations | claims and lockups at `N` | every holder admitted; every lockup has a basis |
| Valuation | `FigureRecorded` for `price.reference` at `N` | signer set and confirmation match the channel policy |
| Cut-off | block `N` and its timestamp | no event after `N` in the pack |

---

## Related

- [14 — Events and errors](14-events-errors.md) — every event the pack replays
- [17 — Security](17-security.md) — the invariants the reconciliation checks
- [26 — Handoff](26-handoff.md) — where the pack sits in the build
