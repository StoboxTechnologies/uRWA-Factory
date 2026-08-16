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

Investor payments are locked **by amount and asset**, not by a per-offering flag. As each purchase
lands, the registry calls `lockPayment(offeringId, asset, amount)`, adding to the locked total for
that asset. `unlockPayments(offeringId)` on settlement releases only that offering's total.

`freeBalance(asset)` is what a withdrawal may move: the held balance minus everything spoken for —
the security token's `reserved`, or a payment asset's locked total. **Both** withdrawal doors check
it: `withdrawERC20` (`SUPPLY_OPERATOR`) and `withdrawPayments` (`ISSUER_ADMIN`). Neither can reach
locked money, and no offering id a caller supplies can unlock it, because a lock is on an amount of an
asset and not on an id.

This is enforced by the treasury itself, not by operator discipline. An operator who wants the funds
early cannot get them by calling in a different order or through the other door, and one offering's
settlement never frees another's money.

| Offering state | Its payment tokens |
|---|---|
| Active, accumulating purchases | Locked as each arrives |
| Closed, soft cap unmet | Locked |
| Settled | Released; withdrawable |
| Refunding / Cancelled | Returned to investors; the lock falls as each refund goes out |

## Distribution

`distributeFromTreasury(to, amount, unlockAt)` moves tokens to a holder and optionally applies a
lockup in the same transaction. It runs the full compliance pipeline on the receiving side — the
treasury being trusted does not make the recipient eligible. It is callable by `SUPPLY_OPERATOR` or by
the offering registry the issuer wired in, which delivers tokens as offerings settle. It is bounded at
32 lockups per holder, the same bound `LockupFacet` enforces.

Passing `unlockAt = 0` applies no lockup.

## Refund handling

A refund is **cash only**. Because tokens are delivered at settlement rather than at purchase (see
[12 — Offerings](12-offering.md)), a failed offering never delivered any security tokens, so there is
nothing to return — only the payment to give back. `refund(offeringId, asset, investor, amount)`
transfers the payment and reduces the locked total by the same amount.

This is the symmetry the earlier design lacked: delivering at purchase meant a failed raise had to
claw tokens back out of investors' wallets, which needs a seizure power the design keeps opt-in.
Delivering at settlement needs none.

## Functions

See [07 — Function reference](07-functions.md#treasury) for the complete list. Summary:

| Group | Functions |
|---|---|
| Custody | `deposit`, `withdrawERC20`, `withdrawPayments` |
| Offering support | `reserve`, `release`, `lockPayment`, `unlockPayments`, `refund` |
| Views | `token`, `reservedOf`, `availableBalance`, `paymentBalance`, `freeBalance`, `lockedPayments` |

## Invariants

1. `availableBalance() == balance − reserved`, never negative.
2. `freeBalance(asset)` is the held balance minus what is reserved (for the security token) or locked
   (for a payment asset), never negative.
3. Neither `withdrawERC20` nor `withdrawPayments` can move more than `freeBalance(asset)`.
3. Payment tokens for an unmet-soft-cap offering are never withdrawable.
4. Only the offering registry may call `reserve` and `release`.
5. Only `SUPPLY_OPERATOR` may call `withdrawERC20`.

## Related documents

- [12 — Offerings](12-offering.md)
- [07 — Function reference](07-functions.md)
