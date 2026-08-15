# 21 — Interface specification

Four surfaces, one shared connection layer. Wireframes are deliberately low-fidelity: this specifies
structure, data and state, not visual design.

## Surfaces

| Surface | Audience | Auth | Public |
|---|---|---|---|
| **Public verifier** | Anyone — exchanges, custodians, journalists, agents | None | ✅ |
| **Investor page** | Holders and prospective investors | Wallet | ✅ per token |
| **Issuer console** | The issuing company | Wallet + role | ❌ |
| **Compliance console** | Compliance officer | Wallet + role | ❌ |

All four read the same contracts. None require a Stobox account — a fork's operators use the same
interfaces against their own deployment.

---

## The connection layer

Wallet connection is not enough. In this system a wallet must resolve to an **identity subject** with
valid claims. The interface must make that distinction visible at all times, because it is the single
thing users misunderstand.

### Connection states

| State | Shown as | Primary action |
|---|---|---|
| **Disconnected** | Neutral | Connect wallet |
| **Wrong network** | Warning | Switch to Base |
| **Connected, no identity** | Warning | "This wallet is not verified" → how to get verified |
| **Connected, identity expired** | Warning | "Verification expired on {date}" → renew |
| **Connected, identity blocked** | Critical | "This wallet is blocked" → contact issuer |
| **Connected, wallet deactivated** | Warning | "This wallet was deactivated. Your other wallets still work." |
| **Connected, verified** | Positive | Proceed |

```
┌──────────────────────────────────────────────────────────┐
│  ●  0x4b2f…9c1a          Verified · Base                 │
│     Subject 0x8e…42 · 3 wallets · expires 12 Mar 2027    │
└──────────────────────────────────────────────────────────┘

┌──────────────────────────────────────────────────────────┐
│  ▲  0x4b2f…9c1a          Not verified · Base             │
│     This wallet has no identity record. You can view     │
│     everything here, but cannot hold or receive tokens.  │
│     [ How to get verified ]                              │
└──────────────────────────────────────────────────────────┘
```

**Rule:** never block reading. An unverified wallet sees everything a verified one sees; only actions
are gated. Hiding information from unverified users teaches them nothing and looks like a failure.

### Contract calls

| State resolved from | Call |
|---|---|
| Subject | `identityRegistry.subjectOf(wallet)` |
| Active | `identityRegistry.isActive(wallet)` |
| Claims | `identityRegistry.claim(subject, key)` per displayed key |
| Wallets | `getLinker` / adapter-specific |

---

## Surface 1 — Public verifier

No wallet required. The surface that makes the system credible to people who do not trust us.

```
┌────────────────────────────────────────────────────────────────┐
│  Verify a uRWA token                                           │
│  ┌──────────────────────────────────────────────┐  ┌────────┐  │
│  │ 0x…  token address                           │  │ Check  │  │
│  └──────────────────────────────────────────────┘  └────────┘  │
├────────────────────────────────────────────────────────────────┤
│  MANHATTAN OFFICE TOWER · MOTT                Base · verified  │
│                                                                │
│  Standard      ERC-20 · ERC-7943  0x3edbb4c4        ✔ conforms │
│  Supply        2,400,000 / 10,000,000 max                      │
│  Holders       412 subjects · term top-10 34%                  │
│  Status        Active · not paused                             │
│                                                                │
│  COMPLIANCE RULES                                              │
│  ├ Valid identity required                                     │
│  ├ Jurisdiction: US excluded                                   │
│  ├ Accredited or professional investors only                   │
│  ├ Maximum 2,000 holders                                       │
│  └ 12-month hold period                                        │
│                                                                │
│  ISSUANCE                                                      │
│  Factory        Stobox canonical      ✔ isFactoryIssued        │
│  Passport       0x9f3c…a71e           ✔ confirmed both sides   │
│  Last snapshot  11 days ago · v14                    ✔ current │
│                                                                │
│  ATTESTATIONS                          values not disclosed    │
│  ├ Reserves      Deloitte      11 d ago   valid 90 d           │
│  ├ Valuation     CBRE          34 d ago   valid 12 mo          │
│  └ Audit         Hacken        6 mo ago   valid 18 mo          │
│                                                                │
│  ┌──────────────────────┐  ┌──────────────────────┐            │
│  │ Simulate a transfer  │  │ Verify a proof       │            │
│  └──────────────────────┘  └──────────────────────┘            │
└────────────────────────────────────────────────────────────────┘
```

### Transfer simulator

The most useful thing on the page. Enter two addresses and an amount; get the answer before anyone
signs anything.

```
┌────────────────────────────────────────────────────────────────┐
│  From  0x4b2f…9c1a      To  0x77a0…2b31      Amount  5,000     │
│                                                                │
│  ✕  This transfer would fail                                   │
│                                                                │
│     Stage 6 — compliance rules                                 │
│     Rule    JurisdictionDeny  0x5c…d9                          │
│     Reason  "jurisdiction excluded"                            │
│                                                                │
│     ✔ not paused   ✔ sender may send   ✔ recipient may receive │
│     ✔ 5,000 of 8,200 unfrozen           ✕ rules                │
└────────────────────────────────────────────────────────────────┘
```

Backed by `whyBlocked(from, to, amount)` — one call returns stage, rule and reason. The stage list is
rendered from [06](06-states.md#2-transfer-outcome-state).

### Proof verifier

Paste a disclosed value, its salt and Merkle path; the page verifies against the anchored root using
the same library a contract would. No account, no Stobox call.

---

## Surface 2 — Investor page

Public per token, personalised when a wallet connects.

```
┌────────────────────────────────────────────────────────────────┐
│  MANHATTAN OFFICE TOWER              [ ● 0x4b2f…  Verified ]   │
├────────────────────────────────────────────────────────────────┤
│  YOUR POSITION                                                 │
│                                                                │
│      8,200 MOTT                                                │
│      ├────────────────────────────┬──────────┬──────────┐      │
│      │  transferable 5,300        │ Jun 1,900│ Dec 1,000│      │
│      └────────────────────────────┴──────────┴──────────┘      │
│      Locked amounts unlock automatically on the dates shown.   │
│                                                                │
│  ┌──────────┐ ┌──────────┐ ┌──────────────┐                    │
│  │ Transfer │ │  Buy     │ │ View passport│                    │
│  └──────────┘ └──────────┘ └──────────────┘                    │
├────────────────────────────────────────────────────────────────┤
│  ELIGIBILITY                                                   │
│  ✔ Identity verified        expires 12 Mar 2027                │
│  ✔ Jurisdiction  Germany    permitted                          │
│  ✔ Professional client      MiFID II                           │
│  ✔ Sanctions screening      cleared 3 days ago                 │
├────────────────────────────────────────────────────────────────┤
│  THE ASSET                                                     │
│  Class    Real estate · commercial                             │
│  Regime   MiFID II · professional investors                    │
│  Passport 0x9f3c…a71e   snapshot 11 days ago                   │
│  Reserves attested by Deloitte, 11 days ago                    │
└────────────────────────────────────────────────────────────────┘
```

### Transfer flow — pre-flight is mandatory

```
  amount + recipient
        │
        ▼
  canTransfer() ── false ──▶ show whyBlocked reason, no signature requested
        │ true
        ▼
  confirm ──▶ sign ──▶ pending ──▶ confirmed
```

**Never request a signature for a transaction that will revert.** The contract can answer the question
for free; asking the user to pay gas to discover a compliance failure is a design defect.

### Buy flow

```
  1. Eligibility     rules evaluated, result shown before anything else
  2. Amount          min / max, allocation remaining, tier price
  3. Payment         choose token, approve or permit
  4. Review          cost, tokens, lockup end date, fees
  5. Sign
  6. Confirmation    tokens received, lockup shown on the position bar
```

Step 1 comes first deliberately. An investor who cannot participate learns it before entering an
amount, not after approving a payment token.

---

## Surface 3 — Issuer console

```
┌──────────┬─────────────────────────────────────────────────────┐
│ MOTT     │  OVERVIEW                                           │
│          │                                                     │
│ Overview │  Supply     2,400,000 issued · 10,000,000 cap       │
│ Holders  │  Treasury   1,100,000 held · 400,000 reserved       │
│ Offering │  Holders    412 subjects · 486 wallets              │
│ Rules    │  Offering   Series A · active · 68% of soft cap     │
│ Roles    │                                                     │
│ Passport │  ⚠ 3 transfers blocked in the last 7 days           │
│          │    2 × jurisdiction · 1 × hold period               │
│ ──────── │                                                     │
│ Deploy   │  ┌────────┐ ┌──────────┐ ┌───────────────┐          │
│ new      │  │ Issue  │ │ Distribute│ │ New offering │          │
│          │  └────────┘ └──────────┘ └───────────────┘          │
└──────────┴─────────────────────────────────────────────────────┘
```

### Deploy flow

Six steps, mapping directly onto `TokenParams`.

| Step | Fields | Warning shown |
|---|---|---|
| 1 Identity | name, symbol, decimals | Cannot be changed after deployment |
| 2 Supply | max supply, **lock the cap** | Locking is irreversible |
| 3 Regime | preset from [10](10-rules.md#presets) | Determines who may invest |
| 4 Identity source | allowlist, EAS, StoboxDID | Determines what rules can check |
| 5 Roles | four addresses | Warn if any two are the same wallet |
| 6 Review | full summary, estimated gas | Final |

Step 5 must warn — not block — when `SUPPLY_OPERATOR` equals `COMPLIANCE_OFFICER`, because together
they can mint and freeze, which removes the check each provides on the other.

### Holders

Grouped **by subject**, expandable to wallets. This is the view that makes the subject-vs-address
distinction concrete for the issuer.

```
  Subject 0x8e…42    Germany · professional     12,400   3 wallets ▾
    0x4b2f…9c1a        8,200      5,300 free
    0x77a0…2b31        3,100      3,100 free
    0x91cc…04de        1,100          0 free   Dec lockup
```

### Rules

Read-only display of the live policy set in plain language, with the contract address of each rule and
a link to its source. A "simulate change" action shows how many current holders a proposed rule set
would newly block — **before** it is applied. Applying is `UPGRADE_ADMIN` and timelocked.

---

## Surface 4 — Compliance console

Separate application, separate role, separate audit trail. Every action requires a reason.

```
┌────────────────────────────────────────────────────────────────┐
│  COMPLIANCE — MOTT                            ● 0x33f1…  CO    │
├────────────────────────────────────────────────────────────────┤
│  ┌──────────────────┐  Token active · not paused               │
│  │  PAUSE TOKEN     │  Halts all transfers immediately.        │
│  └──────────────────┘  Reason required.                        │
├────────────────────────────────────────────────────────────────┤
│  BLOCKED TRANSFERS — last 30 days                       14     │
│  ├ 8   jurisdiction excluded                                   │
│  ├ 4   hold period not elapsed                                 │
│  ├ 1   sanctions screening stale                               │
│  └ 1   RuleFailed — MaxHolders 0x2a…f0 reverted        ⚠       │
│                                                                │
│  The last row is an operational fault, not a policy outcome.   │
├────────────────────────────────────────────────────────────────┤
│  ACTIONS                                                       │
│  Freeze tokens        account, amount, reason                  │
│  Add lockup           account, amount, unlock date, note       │
│  Forced transfer      from, to, amount, reason  ⚠ if installed │
└────────────────────────────────────────────────────────────────┘
```

Forced operations require a typed confirmation of the reason, show the destination's eligibility
before executing, and warn explicitly that the action is permanent and publicly logged.

`RuleFailed` events are surfaced separately from ordinary refusals. A reverting rule is a bug in
someone's contract, not a compliance decision, and conflating the two hides real faults.

---

## Component inventory

| Component | Used by | Notes |
|---|---|---|
| `WalletBadge` | all | Seven connection states |
| `EligibilityPanel` | investor, verifier | One row per claim, with expiry |
| `BalanceBar` | investor, issuer | Free vs locked segments with unlock dates |
| `RuleList` | all | Plain language plus contract address |
| `TransferPreflight` | investor, verifier | Wraps `whyBlocked` |
| `AttestationList` | verifier, investor | Metadata only, never values |
| `SnapshotFreshness` | verifier, issuer | Age plus stale flag from the contract |
| `ReasonDialog` | compliance, issuer | Mandatory reason before any privileged write |
| `TxState` | all | idle → simulating → awaiting signature → pending → confirmed / failed |
| `AddressChip` | all | Truncated, copyable, explorer link, ENS if present |

---

## Global states

Every surface handles all of these. A screen is not done until each renders deliberately.

| State | Rule |
|---|---|
| **Loading** | Skeletons matching final layout — never a spinner over a blank page |
| **Empty** | Explain what will appear and the action that creates it |
| **Error — RPC** | "Cannot reach the network", retry, never a raw error object |
| **Error — revert** | Decode ERC-7943 errors into the same language as `whyBlocked` |
| **Wrong network** | Blocking banner with a switch action |
| **Not connected** | Everything readable; actions replaced with Connect |
| **No identity** | Actions disabled with an explanation and a route to verification |
| **Paused** | Persistent banner on every surface for that token |
| **Stale snapshot** | Passport data marked stale wherever it appears |
| **Pending transaction** | Optimistic state with the hash, and an explorer link |

---

## Error language

Contract errors are decoded into one sentence naming the problem and the next step. Never show a
selector.

| Error | Shown as |
|---|---|
| `ERC7943CannotSend` | "This wallet is not verified, so it cannot send tokens." |
| `ERC7943CannotReceive` | "The recipient is not verified and cannot receive this token." |
| `ERC7943InsufficientUnfrozenBalance` | "5,000 requested, 3,300 available. 1,900 unlocks on 1 June." |
| `ERC7943CannotTransfer` | The rule's own `reason`, verbatim. |
| `ProtocolPaused` | "Transfers are paused by the issuer." |
| `AllocationExceeded` | "Your allocation for this offering is 10,000; you have used 8,500." |

---

## Technical notes

| Concern | Approach |
|---|---|
| Reads | Direct RPC with multicall batching. No indexer required for correctness — the chain is the source. |
| History | Event logs; an indexer is a performance optimisation, never a dependency. |
| Wallets | EIP-6963 discovery, WalletConnect, plus ERC-4337 smart accounts |
| Approvals | ERC-2612 permit where the payment token supports it, saving a transaction |
| Accessibility | WCAG 2.1 AA. Never encode state in colour alone — freeze, pause and eligibility all carry text or icon |
| i18n | English and Ukrainian at launch; all contract-derived strings pass through the dictionary |
| Responsive | Investor page and verifier are mobile-first; the consoles are desktop-first |

---

## Related documents

- [06 — States](06-states.md)
- [07 — Function reference](07-functions.md)
- [20 — Development plan](20-development-plan.md)
