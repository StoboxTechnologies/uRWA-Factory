# 12 — Offerings

## Purpose

The offering registry runs primary sales: pricing, caps, allocations, eligibility and refunds. It is
optional — a token functions without it, and private placements often skip it entirely.

## Parameters

```solidity
struct OfferingParams {
    address token;
    address[] paymentTokens;     // USDC, USDT, … — any one may be paid in
    uint256 price;               // flat price per whole token; ignored when tiers is non-empty
    Tier[]  tiers;               // optional ascending price bands
    uint256 softCap;
    uint256 hardCap;
    uint256 minPerInvestor;
    uint256 maxPerInvestor;
    uint64  startAt;
    uint64  endAt;
    uint64  lockupUntil;         // applied to purchased tokens
    bool    preMint;             // reserve from treasury vs mint on purchase
    bytes32 regime;              // RegD506c, RegS, MiCA-ART, …
}

struct Tier {
    uint256 upToAmount;          // cumulative across the raise, not per investor
    uint256 price;
}
```

## Supply path — issuer chooses per offering

| Mode | Behaviour | Suits |
|---|---|---|
| **Pre-mint and reserve** | Supply minted to treasury and reserved when the offering is created | Pre-sold allocations; buyers see availability up front |
| **Mint on purchase** | Tokens created as each investor buys | Open-ended raises; supply always equals what was actually sold |

**Multi-currency.** The buyer names which listed currency to pay in — `purchase(id, amount,
paymentToken)` — and an unlisted one is refused rather than silently retargeted. All accepted
currencies are priced equally, which is the stablecoin assumption: list only currencies you are
willing to treat as interchangeable at face value. The refund returns exactly the currency each
purchase paid.

**Tiered pricing.** Bands are consumed in order across the whole raise, from where it has already
sold: the early-bird price is gone once its band is full, a purchase crossing a boundary pays each
band's price for the tokens that fall in it, and anything past the final band is priced at that
band — never at zero. `previewPurchase` returns the same blended cost `purchase` will charge.

Both are supported and selected with the `preMint` flag. **There is no default** — the console
requires a choice, because the two produce different `totalSupply` readings for the same raise and
an issuer who did not choose will be surprised by whichever they got.

## Purchase flow

```
  Investor        OfferingRegistry      IdentityRegistry       Treasury
     │                   │                     │                  │
     │─ purchase(id,amt)▶│                     │                  │
     │                   │─ claim(subject,key)▶│                  │
     │                   │◀──── claim set ─────│                  │
     │                   │  evaluate offering rules               │
     │                   │  check allocation, min/max, caps       │
     │                   │──── pull payment · lock it ───────────▶│
     │                   │                     │   payment locked │
     │◀── recorded; tokens owed, not yet delivered ────────────── │
     │                   │                     │   until soft cap │
     ⋮  offering reaches its soft cap and someone calls settle    ⋮
     │─ claimTokens(pid)▶│                     │                  │
     │◀── tokens + lockup applied (full pipeline) ─────────────── │
```

**Tokens are delivered at settlement, not at purchase.** A purchase during the raise records a claim
and locks the money; the security tokens are pulled by the investor — `claimTokens` — only once the
offering settles. This is why a failed offering unwinds cleanly: it delivered nothing, so a refund is
the only leg to reverse. Delivering at purchase would leave a failed offering having to claw tokens
back out of investors' wallets, which needs a seizure power the design deliberately keeps opt-in.

![An offering reaches exactly one terminal state. Both `settle` and `beginRefunding` are permissionless, so an absent operator cannot strand investor funds.](diagrams/offering-lifecycle.svg)

The registry evaluates **offering-level** rules before value moves. The token's own pipeline still
runs on the distribution leg. The two checks are independent by design: **passing an offering never
implies the right to hold.** An investor who satisfies the offering but fails the token's rules cannot
receive tokens.

### A purchase larger than the remaining cap is refused outright

No partial fill. If an investor asks for more than the hard cap still allows, the whole call reverts
with the remaining amount in the error, and they submit a smaller one.

The alternative — fill what is left and refund the difference — is friendlier for one transaction and
worse everywhere else. It creates a partial-refund path on the money leg, which is the most sensitive
code in the system and the place where a second refund route is most likely to be exploitable. It
also means a purchase can succeed for an amount the investor never agreed to, which is a poor
property for a regulated instrument.

`previewPurchase` tells the investor the exact fillable amount before they sign, so the refusal is
never a surprise — it is only reachable by racing another buyer in the same block.

## Payment locking

| Offering state | Payments |
|---|---|
| Active | Locked in treasury |
| Closed, soft cap unmet | Locked |
| Settled | Released to issuer |
| Refunding / Cancelled | Returning to investors |

`Treasury.withdrawERC20` reverts while any offering holding that asset is Active or Closed with its
soft cap unmet. The lock is enforced by the treasury, not by operator discipline.

## Refunds — dual path

| Path | Trigger | Who calls |
|---|---|---|
| **Operator push** | `refundBatch(id, limit)` | `OFFERING_OPERATOR` |
| **Investor pull** | `claimRefund(purchaseId)` | The purchaser |

Both exist because each covers the other's failure mode. Push gives investors a good experience and
scales; pull guarantees that an absent, unwilling or insolvent operator cannot strand funds.

**Idempotency is the invariant that makes this safe:** a purchase already in `Refunded` cannot be
refunded again by either path. Assert it in tests.

`beginRefunding` and `settle` are **permissionless** once their conditions are met — closed, and soft
cap missed or met respectively. No operator action is required to reach either terminal state.

## Allocations and whitelists

| Feature | Mechanism |
|---|---|
| Per-investor allocation | Pre-committed amount per subject, checked at purchase |
| Reserved tranches | A portion of the offering restricted to an allocation list |
| Min / max investment | Per offering, overridable per investor by rule `bounds` |
| Tiered pricing | `Tier[]` — price varies by cumulative amount sold |

Allocations are keyed to **subjects**, not addresses, for the same reason holder caps are.

## Offering-level rules versus token-level rules

| Level | Governs | Typical rules |
|---|---|---|
| **Token** | Every transfer, forever | identity, jurisdiction, holder caps, hold period |
| **Offering** | Primary purchase only | accreditation, minimum investment, allocation, regime-specific attestations |

A token-level jurisdiction ban cannot be relaxed by an offering. An offering may only be **more**
restrictive than the token, never less.

## Hold periods

| Source | Applies |
|---|---|
| Token-level baseline | Every acquisition, regardless of route |
| Offering `lockupUntil` | Tokens purchased in that offering |

Both apply; the longer wins. An offering may lengthen a hold period, never shorten it. The lockup is
created at distribution and surfaces through `getFrozenTokens`, so it is visible to any ERC-7943
integrator without offering-specific knowledge.

## Regimes

The regime selected at offering creation determines the rule preset applied and the evidence fields
the passport expects.

| Regime | Preset | Extra passport evidence |
|---|---|---|
| Reg D 506(c) | `RegD506c` | Form D reference, accreditation verification method |
| Reg S | `RegS` | Distribution compliance period, US-person exclusion method |
| EU prospectus or exemption | `MiFID2-*` | Prospectus approval or exemption basis |
| MiCA — ART | `MiCA-ART` | Reserve composition, reserve custody, redemption-at-par terms, white paper |
| MiCA — EMT | `MiCA-EMT` | 1:1 backing attestation, redemption at par at any time |
| MiCA — other | `Open` | White paper reference |

## Related documents

- [06 — States](06-states.md#7-offering-state)
- [10 — Rules](10-rules.md)
- [13 — Treasury](13-treasury.md)
