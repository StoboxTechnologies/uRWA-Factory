# 13 — Treasury

## Purpose

One treasury per token. It holds issued supply before distribution and investor payments during an
offering. It is deployed as a minimal clone by the factory and is not upgradeable.

## Why one per token

| Property | Consequence |
|---|---|
| Isolation | A compromise reaches one asset, not an issuer's whole portfolio |
| Accounting | Per-asset balances need no attribution logic |
| Failure domain | One asset's offering cannot lock another's funds |
| Cost | A minimal clone on Base is negligible |

A shared multi-token vault was rejected: it saves a trivial amount of gas and concentrates every
asset's custody in one contract.

## What it holds

| Asset | Purpose |
|---|---|
| The security token | Issued supply awaiting distribution; returned tokens after refunds |
| Payment tokens (USDC and similar) | Investor payments during offerings |
| Any other ERC-20 | Rescue path for mistaken transfers |

## Trust status

The treasury is added to the token's trust list at deployment, with `trust(treasury, "treasury")`.
This lets it move supply without running the full rule set on both sides.

It does **not** bypass the pause check or the frozen-balance check. A compromised treasury cannot
drain locked supply and cannot move anything while the token is paused — this is precisely why those
two checks sit outside the trust bypass.

## Reservation accounting

During an offering the treasury tracks three quantities per asset:

| Quantity | Meaning |
|---|---|
| `balance` | Total held |
| `reserved` | Committed to active offerings |
| `available` | `balance − reserved`, the only part freely withdrawable |

`reserve` and `release` are callable only by the offering registry. `availableBalance()` is what
`withdrawERC20` checks against.

## Payment locking

`withdrawERC20` reverts while any offering holding that asset is in `Active` or `Closed` state with
its soft cap unmet.

This is enforced by the treasury itself, not by operator discipline. An operator who wants the funds
early cannot get them by calling in a different order, and an operator who forgets cannot accidentally
break refundability.

| Offering state | Payment tokens |
|---|---|
| Active | Locked |
| Closed, soft cap unmet | Locked |
| Settled | Available to `SUPPLY_OPERATOR` |
| Refunding / Cancelled | Reserved for refunds; not withdrawable |

## Distribution

`distributeFromTreasury(to, amount, unlockAt)` moves tokens to a holder and optionally applies a
lockup in the same transaction. It runs the full compliance pipeline on the receiving side — the
treasury being trusted does not make the recipient eligible.

Passing `unlockAt = 0` applies no lockup.

## Refund handling

On refund the treasury performs both legs:

1. Payment tokens return to the investor.
2. Security tokens return from the investor to the treasury.

The second leg is a compliance-checked transfer like any other. If the investor has since become
ineligible to send — a blocked DID, for example — the transfer would fail and strand the refund. The
registry therefore performs the token return leg through the trusted path, treating a refund as a
system operation rather than an investor transfer.

## Functions

See [07 — Function reference](07-functions.md#treasury) for the complete list. Summary:

| Group | Functions |
|---|---|
| Custody | `deposit`, `withdrawERC20` |
| Offering support | `reserve`, `release`, `lockPayments`, `unlockPayments` |
| Views | `token`, `reservedOf`, `availableBalance`, `paymentBalance` |

## Invariants

1. `availableBalance() == balance − reserved`, never negative.
2. `withdrawERC20` cannot reduce the balance below `reserved`.
3. Payment tokens for an unmet-soft-cap offering are never withdrawable.
4. Only the offering registry may call `reserve` and `release`.
5. Only `SUPPLY_OPERATOR` may call `withdrawERC20`.

## Related documents

- [12 — Offerings](12-offering.md)
- [07 — Function reference](07-functions.md)
