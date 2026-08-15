# 02 — Architecture

## The three planes

The system is split into three planes with different mutability rules. Every requirement maps onto
exactly one plane.

| Plane | Contains | Mutability | Delivers |
|---|---|---|---|
| **Ledger** | Balances, supply, ERC-20 entry points | **Immutable** — enforced by code | Resilience |
| **Policy** | Compliance facet, policy set, rules | **Replaceable** — one transaction | Agility, upgradeability |
| **Claims** | Identity claims, namespaced keys, adapters | **Extensible** — no upgrade needed | Customization, openness |

Queries flow downward only. The ledger never learns *why* a transfer was refused. The policy layer
never touches a balance. The claims layer does not know what a token is.

```
  LEDGER PLANE          balances · supply · ERC-20 entry points
  immutable             cannot be replaced — enforced by LibDiamond
        │
        │ asks: may this move?
        ▼
  POLICY PLANE          ComplianceFacet · PolicySet · rules
  replaceable           swapped by one transaction, no migration
        │
        │ asks: what is true of this wallet?
        ▼
  CLAIMS PLANE          identity claims · namespaced keys · adapters
  extensible            new keys added by anyone, no upgrade
```

## Why the boundary is there

Almost every compliance token fuses accounting and policy into one upgradeable contract. That single
decision is what makes such systems hard to audit, what turns a rule change into a governance event,
and what forces token migrations when a regulator moves.

Separating them yields four properties that are otherwise unobtainable:

1. **A policy bug cannot corrupt supply.** The worst outcome of any compliance failure is "transfers
   stop", never "balances are wrong".
2. **A rule change is not a migration.** Swapping the entire compliance regime is one
   `setPolicySet` call. Holders do not move; nothing is re-minted.
3. **Audit scope shrinks.** An auditor can be told the accounting is immutable and out of scope.
   Every future rule change is a scoped review of one external contract, not a re-audit of the token.
4. **New jurisdictions need no core upgrade.** A third party writes a rule and a claim key without
   asking permission.

## The boundary already exists in STV3

This is not a theory imposed on the existing code. The public STV3 base enforces the ledger boundary
today, and the compliance seam is already cut.

- `LibDiamond.replaceFunctions` reverts with `CannotReplaceImmutableFunction` for any selector whose
  registered facet address is the diamond itself. `removeFunctions` reverts with
  `CannotRemoveImmutableFunction`.
- The deploy script registers `transfer`, `transferFrom`, `approve`, `balanceOf`, `totalSupply`,
  `maxSupply`, `allowance` and the metadata getters against the diamond's own address. **The ERC-20
  ledger is therefore immutable by construction, not by policy.**
- `LibERC20._update` — the function every mint, burn and transfer passes through — calls out to
  `ITransferValidation(address(this)).beforeUpdateValidation(...)`. Routed through the fallback, that
  lands on a facet which *is* replaceable. The public repo ships that facet empty.
- The diamond's fallback reverts `FunctionNotFound` when no facet is registered for a selector.
  Remove the compliance facet and every transfer reverts: **the system fails closed by default.**

## Component map

```
   Factory ──deploys──▶ Treasury
      │                    ▲
      │ deploys            │ supply
      ▼                    │
   uRWAToken ──evaluate──▶ PolicySet ──claims──▶ IdentityRegistry
      ▲   │
      │   └──handshake──▶ AssetPassport
      │
   OfferingRegistry ──sells──┘
```

## Design principles

| Principle | Consequence |
|---|---|
| Immutable ledger, replaceable policy | Section above |
| The socket is sacred | Canonical selectors, canonical errors, correct ERC-165. No gratuitous signature changes. |
| Refusal must be legible | `whyBlocked` names the failing stage and rule, using the same code path as enforcement |
| Minimise the trusted surface, narrate what remains | Every privileged action carries a mandatory reason and a distinct event |
| No vendor lock-in in the core | A fork must run with zero Stobox contracts |
| Cheap enough to be the default | Minimal proxies on Base; target under one dollar per deployment |
| The chain is the report | Cap table and audit trail reconstructible from logs alone |
| Ship the tests, not only the code | A public conformance kit any implementer can run |

## Failure direction

Every ambiguous failure resolves toward **stopping**, never toward **permitting**.

| Failure | Result |
|---|---|
| Policy set reverts or is misconfigured | Transfers blocked |
| Identity registry unavailable | Transfers blocked |
| Compliance facet removed | Transfers blocked (`FunctionNotFound`) |
| A single rule reverts or exceeds its gas ceiling | That rule counts as reject; `RuleFailed` emitted |
| Upgrade key compromised | Balances and supply unaffected |

Fail-closed without a recovery path would be a liveness bug, so recovery is explicit: the compliance
officer swaps the policy set in one transaction, and the upgrade admin can install a known-good preset.

## Related documents

- [03 — Contracts](03-contracts.md)
- [08 — Compliance pipeline](08-compliance-pipeline.md)
- [17 — Security](17-security.md)
