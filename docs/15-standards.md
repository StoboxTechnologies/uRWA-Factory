# 15 — Standards

## Implemented standards

| Standard | Role | Where |
|---|---|---|
| **ERC-7943 (uRWA)** | Primary compliance interface | `ComplianceFacet`, `FreezeFacet`, `EmergencyFacet` |
| **ERC-20** | Token base | Diamond core, immutable |
| **EIP-2535** | Modularity and upgrade | Diamond |
| **ERC-165** | Interface discovery | `DiamondLoupeFacet` |
| **ERC-173** | Ownership | Diamond core |
| **ERC-1404** | Legacy restriction reporting | `ComplianceFacet` — integrator compatibility |
| **ERC-2612** | Gasless approval | Diamond core |
| **EIP-712** | Typed signatures | Permit; off-chain subscription signing |
| **ERC-677** | `transferAndCall` | Retained from the STV3 base |
| **ERC-721 + ERC-5192** | Locked non-transferable token | Asset Passport |
| **ERC-4337** | Account abstraction | Investor onboarding path |
| **EAS** | Attestations | Identity adapter tier 1; passport data points |
| **W3C DID / VC** | Identity model alignment | Claim struct mirrors issuer / subject / expiry / revocation |

## ERC-7943 conformance

Interface id **`0x3edbb4c4`** — `IERC7943Fungible`. Reported through `supportsInterface`.

| Requirement | Implementation |
|---|---|
| `canSend`, `canReceive`, `canTransfer` MUST NOT revert | Enforced by test invariant; identity adapter wraps every external call in `try/catch` |
| MUST NOT change storage | All three are `view` |
| `canTransfer` MUST validate amount against unfrozen balance | Step 5 of the pipeline |
| `canTransfer` MUST call `canSend`(from) and `canReceive`(to) | Steps 3 and 4 |
| MUST NOT return false for balance or allowance reasons | Those are checked by the ERC-20 core, outside the compliance result |
| `getFrozenTokens` MAY exceed balance | Permitted and never reverts |
| `forcedTransfer` MUST manipulate balances directly | Bypasses the policy set |
| `forcedTransfer` MUST be access-restricted | `COMPLIANCE_OFFICER` |
| `forcedTransfer` MUST emit canonical transfer events plus `ForcedTransfer` | Both, in order |
| Where frozen assets are involved, MUST unfreeze first and emit `Frozen` before the transfer event | Implemented in that order |
| SHOULD perform `canReceive` on the destination | Enforced |
| `setFrozenTokens` MUST emit `Frozen`, MUST be restricted, MUST allow freezing more than held | All three |
| Public transfers MUST NOT succeed where `canTransfer` is false | Single pipeline; no bypass path |
| Minting MUST reject recipients failing `canReceive` | Step 4 applies to mint |
| Burning MUST respect `canSend` | Step 3 applies to burn |

### Deviations

None in the canonical surface. Two **additive** extensions, neither replacing a standard signature:

| Extension | Reason |
|---|---|
| `forcedTransfer(from, to, amount, string reason)` | Regulators and auditors want the justification on chain. The canonical three-argument form is also present and is what `supportsInterface` covers. |
| `whyBlocked(from, to, amount)` | Diagnostics. Not part of any standard; purely additive. |

## Registry alignment

The Compass Datapoint Registry already lists **ERC-7943 (uRWA)** in its `TOKEN_STANDARD` enum and
**ERC-7943 identity** in `IDENTITY_FRAMEWORK`, so no registry change is needed to record tokens issued
by this factory.

## Regulatory regimes

Regime is orthogonal to asset class. A commodity token and a money-market fund can each fall under
either securities law or MiCA depending on the rights attached.

| Regime | Applies to | Rule preset |
|---|---|---|
| **MiFID II** | EU security tokens — equity, debt, fund units | `MiFID2-Professional` / `MiFID2-Retail` |
| **Reg D 506(c)** | US private placement | `RegD506c` |
| **Reg S** | Offshore, US persons excluded | `RegS` |
| **MiCA — ART** | Asset-referenced tokens: commodity-backed, basket-referenced | `MiCA-ART` |
| **MiCA — EMT** | E-money tokens: single-fiat stablecoins | `MiCA-EMT` |
| **MiCA — other** | Utility and other non-security crypto-assets | `Open` |

### The MiFID II / MiCA boundary

In the EU a tokenized security is a **MiFID II financial instrument**, not a MiCA crypto-asset. MiCA
governs non-security crypto-assets and their service providers. Rights and obligations decide the
classification, not the technology.

This matters for the design because MiCA regimes require evidence fields securities regimes do not —
reserve composition and redemption-at-par terms above all — and both map onto passport attestations
rather than onto token configuration.

**MiCA is in scope**, not as an afterthought: commodity-backed tokens and stablecoins are a real part
of the addressable market and they are governed by it.

## Code standards

| Standard | Use |
|---|---|
| **ISO 3166-1 alpha-2** | Country codes in `urwa.jurisdiction.country`, hashed |
| **ISO 4217** | Currency codes in offering pricing and reporting |
| **ISO 17442 (LEI)** | Legal Entity Identifier in `iso17442.lei`, hashed |
| **FATF Travel Rule / IVMS101** | Counterparty data for `TravelRuleThreshold` |

## Conformance kit

A standalone Foundry test suite, published as its own repository so competitors can adopt it without
adopting anything else of ours. It checks:

- Selector coverage and correct `supportsInterface`
- The must-not-revert guarantee on all three view functions, including for unknown wallets
- Canonical error decoding
- Freeze accounting, including totals exceeding balance
- Forced-transfer event ordering, including the unfreeze-first case
- Mint and burn respecting `canReceive` and `canSend`

Test suites define standards in practice. Whoever maintains the tests becomes the reference point.

## Related documents

- [07 — Function reference](07-functions.md)
- [10 — Rules](10-rules.md)
- [12 — Offerings](12-offering.md)
