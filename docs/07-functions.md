# 07 — Function reference

Every function in the system, with four things stated for each: **what it does**, **who calls it**,
**why it exists**, and where relevant, **how to use it correctly**.

## How to read this

| Column | Meaning |
|---|---|
| **Function** | Signature. Return types shown after `→` |
| **Does** | What actually happens on chain |
| **Called by** | The role or actor who realistically calls it |
| **Why** | The problem it solves. If a function has no answer here, it should not exist |

`view` means it reads only — free to call, no transaction, no gas when called off-chain.
`write` means it changes state and needs a transaction.

## Contents

| Contract | Purpose | Section |
|---|---|---|
| **uRWAToken — core** | The ERC-20 everyone already knows how to use | [↓](#urwatoken-erc-20-core) |
| **ComplianceFacet** | Decides whether a transfer may happen | [↓](#compliancefacet) |
| **FreezeFacet** | Freezes balances indefinitely | [↓](#freezefacet) |
| **LockupFacet** | Locks balances until a date | [↓](#lockupfacet) |
| **MonetaryFacet** | Creates, destroys and distributes supply | [↓](#monetaryfacet) |
| **RolesFacet** | Who is allowed to do what | [↓](#rolesfacet) |
| **EmergencyFacet** | Court orders and lost keys. Opt-in | [↓](#emergencyfacet-opt-in) |
| **PurchaseFacet** | Buying during an offering | [↓](#purchasefacet) |
| **IPolicySet** | Composes rules into a policy | [↓](#ipolicyset) |
| **IRule** | A single compliance check | [↓](#irule) |
| **IIdentityRegistry** | What is verified about a wallet | [↓](#iidentityregistry) |
| **Treasury** | Holds supply and investor payments | [↓](#treasury) |
| **uRWAFactory** | Deploys everything | [↓](#urwafactory) |
| **AssetPassport** | What the asset actually is | [↓](#assetpassport) |
| **AttestorRegistry** | Who may sign attestations | [↓](#attestorregistry) |
| **OfferingRegistry** | Runs the primary sale | [↓](#offeringregistry) |
| **AgentAuthority** | Bounds what an agent may do | [↓](#agentauthority) |
| **AtomicDvP** | Settles a trade in one transaction | [↓](#atomicdvp) |

---

## uRWAToken — ERC-20 core

**What this is.** The ordinary ERC-20 surface. Wallets, exchanges, block explorers and accounting
systems already speak it, which is the entire reason a regulated asset is wrapped this way rather than
in a bespoke interface.

**Who it is for.** Everyone. Holders, wallets, integrators, indexers.

**Why it matters that these are immutable.** These selectors are registered against the diamond
itself, so `LibDiamond` refuses to replace or remove them. No admin key, no governance vote and no
upgrade can alter how balances are accounted. That is the foundation of the whole security model: a
compliance bug can stop transfers, but nothing can rewrite who owns what.

| Function | Does | Called by | Why |
|---|---|---|---|
| `name() → string` | Returns the token's full name | Anyone, wallets | Display |
| `symbol() → string` | Returns the ticker | Anyone, wallets | Display |
| `decimals() → uint8` | Divisibility, usually 18 | Anyone, wallets | Correct amount maths |
| `totalSupply() → uint256` | Tokens currently in existence | Anyone | Supply transparency |
| `balanceOf(address) → uint256` | Holdings of one address | Anyone | The basic question |
| `maxSupply() → uint256` | Hard cap; `0` means unlimited | Anyone, investors | An investor must know dilution is bounded |
| `allowance(owner, spender) → uint256` | How much a spender may move | Anyone, dApps | Standard delegation |
| `transfer(to, value) → bool` | Moves tokens, **through the compliance pipeline** | Holder | The core action |
| `approve(spender, value) → bool` | Authorises a spender | Holder | Lets contracts move tokens for you |
| `transferFrom(from, to, value) → bool` | Moves on behalf of an owner, **through the pipeline** | Approved spender | Exchanges, settlement contracts |
| `permit(...)` | Approval by signature instead of a transaction | Holder, ERC-2612 | Saves a transaction and its gas at purchase |
| `nonces(address) → uint256` | Signature counter for permit | dApps | Replay protection |
| `DOMAIN_SEPARATOR() → bytes32` | EIP-712 domain | dApps | Signature scoping |
| `owner() → address` | ERC-173 owner | Anyone, tooling | Explorer and tooling compatibility |
| `deployer() → address` | Who deployed it | Anyone | Provenance |

**How to use `transfer` correctly.** Call `canTransfer(from, to, amount)` first. It is free and it
tells you whether the transfer will succeed. Submitting a transfer that will revert costs gas and
teaches the user nothing — see [21 — Interface specification](21-interface-specification.md).

**Note on `approve`.** Approval is *not* compliance-checked. Anyone may hold an allowance; the check
happens when tokens actually move. This is deliberate and matches ERC-7943 — restricting approvals
would break ordinary DeFi patterns without adding safety, because the transfer itself is still gated.

---

## DiamondCutFacet and DiamondLoupeFacet

**What this is.** The EIP-2535 machinery: one facet changes the function table, the other reads it.
Both are installed on the token, the factory and the offering registry — every diamond in the system.

**Who it is for.** `DiamondCutFacet` is for the upgrade admin. `DiamondLoupeFacet` is for **everyone
else** — it is how an outsider proves which code a deployed token actually runs, without trusting
anything we say about it.

| Function | Does | Called by | Why |
|---|---|---|---|
| `diamondCut(cuts, init, calldata)` | Add, replace or remove selectors | `UPGRADE_ADMIN` | The only way the function table changes |
| `facets() → Facet[]` | Every facet and its selectors | **Anyone** | The loupe report; independent verification |
| `facetAddresses() → address[]` | Installed facet addresses | Anyone | Diff against the published package |
| `facetAddress(selector) → address` | Which facet serves this call | Anyone | Proves an absent function is absent — `address(0)` |
| `facetFunctionSelectors(facet) → bytes4[]` | Selectors of one facet | Anyone | Per-facet audit |
| `supportsInterface(id) → bool` | ERC-165 | Anyone | How conformance is claimed and checked |
| `upgradeDelay() → uint64` | The delay the issuer configured; `0` means immediate | **Anyone** | A token with a seven-day delay is a different instrument from one without |
| `scheduledAt(cutHash) → uint64` | When a pending cut becomes executable | Anyone | A scheduled upgrade is inspectable before it lands |
| `setUpgradeDelay(newDelay)` | Changes the delay — **raising is immediate, lowering waits out the current delay** | `UPGRADE_ADMIN` | Otherwise the delay is worthless: an admin would zero it and cut in the same transaction |
| `cancelCut(cutHash)` | Abandons a scheduled cut | `UPGRADE_ADMIN` | An upgrade announced and then reconsidered must be withdrawable, and visibly so |

**`diamondCut` cannot replace or remove the ERC-20 selectors.** They are immutable selectors —
registered against the diamond itself — and `LibDiamond` reverts with
`CannotReplaceImmutableFunction`. This is the mechanism behind the whole three-plane split, and the
reason the ledger plane is genuinely immutable rather than immutable by policy. See
[02](02-architecture.md).

## ComplianceFacet

**What this is.** The part that decides whether value may move. Everything else in the system exists
to feed it or to act on its answer.

**Who it is for.** Three different audiences use it for three different reasons: **integrators** ask
it questions before acting, **investors** find out why something failed, and **issuers** configure it.

### The ERC-7943 questions

These three are the standard interface. They are `view`, they are free, and **they never revert** —
an integrator can call them on any address, including garbage, and always get an answer.

| Function | Does | Called by | Why |
|---|---|---|---|
| `canSend(account) → bool` | May this account send at all? | Integrators, agents, UI | Account-level eligibility, independent of amount |
| `canReceive(account) → bool` | May this account receive at all? | Integrators, agents, UI | Check a recipient before sending them anything |
| `canTransfer(from, to, amount) → bool` | Will this specific transfer succeed? | Integrators, agents, UI, settlement | The complete answer, including amount and rules |

**How to use them.** `canSend` and `canReceive` answer "is this wallet eligible in principle" — useful
for onboarding screens and address books. `canTransfer` answers "will this exact operation work" and
is what you call immediately before acting.

**Why this matters more than it looks.** Almost no token can answer these questions. Systems built on
tokens that cannot must guess, submit, and handle failure — which is why autonomous agents have been
impractical on regulated assets. A free, deterministic, non-reverting pre-flight changes that
completely. See [22 — Agents and settlement](22-agents-and-settlement.md).

### The hook

| Function | Does | Called by | Why |
|---|---|---|---|
| `beforeUpdate(from, to, amount)` | Runs the seven gates and reverts with the reason | **The ledger, on itself** | Every movement of value passes through it |
| `afterUpdate(from, to, amount)` | Updates holder counts and subject balances | **The ledger, on itself**, after the move | Subject accounting needs the identity registry, which the ledger plane must not depend on |

**Not called by anyone else, and that is enforced.** `afterUpdate` refuses any caller but the
diamond. It moves the numbers holder caps are decided on and moves no balance, so an unguarded one
would let a bystander make `MaxHolders` refuse an honest investor without touching the ledger.
`beforeUpdate` needs no such guard: it is a `view` and can change nothing.

The token invokes both on its own address before touching a balance, so
the fallback router resolves it. That indirection is what makes the system fail closed: remove the
compliance facet and the selector is unregistered, so every transfer reverts `FunctionNotFound` with
no code anywhere stating that behaviour.

The gate order is a cost decision — cheap storage reads first, the single unbounded external call
last. Refusing a paused token or an unverified wallet costs almost nothing. See
[08](08-compliance-pipeline.md).

**`afterUpdate` runs after balances have moved and cannot refuse anything.** That is deliberate: it
exists to maintain counts, and a bookkeeping function that could revert a transfer the pipeline
already allowed would be a second, weaker compliance system. If no facet serves it, the token keeps
working and simply does not maintain subject counts.

### Diagnostics

| Function | Does | Called by | Why |
|---|---|---|---|
| `whyBlocked(from, to, amount) → (uint8 stage, address rule, string reason)` | Explains the first failure | UI, support, agents | "It failed" is useless; "jurisdiction excluded, by rule 0x5c…d9" is actionable |
| `detectTransferRestriction(from, to, amount) → uint8` | ERC-1404 restriction code | Legacy integrators | Older platforms speak ERC-1404, not ERC-7943 |
| `messageForTransferRestriction(uint8) → string` | Human text for a code | Legacy integrators | Same |

**How to use `whyBlocked`.** It runs the identical code path as enforcement, in view mode. Show the
`reason` to the user verbatim; show the `rule` address to a developer. The stage index maps to
[06 — States](06-states.md#2-transfer-outcome-state).

**Why it exists.** Compliance systems fail in support tickets, not in exploits. A transfer that
reverts with no explanation costs an issuer a day of back-and-forth. Because enforcement and
explanation share one implementation, they cannot drift apart — which is the actual mechanism, not the
diagnostic itself.

### Configuration

| Function | Does | Called by | Why |
|---|---|---|---|
| `policySet() → address` | Current rule engine | Anyone | Transparency — anyone can read the live rules |
| `identityRegistry() → address` | Current identity source | Anyone | Same |
| `setPolicySet(address)` | Swaps the entire compliance regime | UPGRADE_ADMIN | Regulation changes; the token should not have to |
| `setIdentityRegistry(address)` | Swaps the identity source | UPGRADE_ADMIN | Move between allowlist, EAS and DID without redeploying |

**Why these two matter.** This is the agility claim made concrete. A new regulation means deploying a
new `PolicySet` and calling `setPolicySet`. Holders do not move, nothing is re-minted, no migration
happens, and balances are untouchable by construction.

### Trust list

| Function | Does | Called by | Why |
|---|---|---|---|
| `trust(account, reason)` | Marks a system address as trusted | ISSUER_ADMIN | Treasury and offering contracts would otherwise fail their own rules |
| `distrust(account, reason)` | Removes it | ISSUER_ADMIN | Decommissioning |
| `isTrusted(address) → bool` | Trust status | Anyone | Auditability |
| `trustList() → address[]` | Everything trusted | Anyone | An investor can see exactly which addresses are privileged |
| `trustReasonOf(address) → string` | Why it was trusted | Anyone | A privilege with no stated reason is a red flag |

**How to use it.** Trust the treasury and the offering registry at deployment. Trust nothing else
without a written reason — the reason is mandatory precisely so that it ends up in the audit trail.

**What trust does and does not do.** It skips **rules only**. It never skips the pause check or the
frozen-balance check. That is what stops a compromised treasury from draining locked supply.

### Pause

| Function | Does | Called by | Why |
|---|---|---|---|
| `pause()` | Halts every transfer immediately | COMPLIANCE_OFFICER | Security incident, regulatory order, corporate action |
| `unpause()` | Resumes | COMPLIANCE_OFFICER | Recovery |
| `paused() → bool` | Current state | Anyone | Integrators must show it |
| `pauseAddress(account, reason)` | Halts one address in **both** directions | COMPLIANCE_OFFICER | A compromised wallet or a counterparty under investigation |
| `unpauseAddress(account)` | Resumes that address | COMPLIANCE_OFFICER | Recovery |
| `addressPaused(account) → bool` | Is this address halted | Anyone | Pre-flight, and why a transfer failed |

**Why an address pause is not just a full freeze.** A freeze restricts sending; the holder can still
be paid. An address pause blocks sending *and* receiving. See [05](05-roles.md) for the full
comparison — the two are separate instruments for separate problems, and collapsing them would leave
no way to stop value flowing **toward** an address.

`reason` is mandatory and evented, on the same principle as the trust list: an unexplained
restriction is indistinguishable from an attack on a holder.

**Why there is no timelock on this.** A delay on an emergency stop defeats the purpose. Upgrades are
timelocked; the emergency brake is not.

### Holder accounting

| Function | Does | Called by | Why |
|---|---|---|---|
| `holderCount() → uint256` | Addresses with a balance | Anyone, reporting | Basic register size |
| `subjectHolderCount() → uint256` | **Identities** with a balance | Rules, reporting, regulators | The number holder caps must use |
| `subjectBalanceOf(subject) → uint256` | Total across all of an identity's wallets | Rules, reporting | Concentration limits |
| `subjectOf(wallet) → bytes32` | Which identity owns this wallet | Anyone, UI | Grouping wallets by person |

**Why the distinction is not academic.** A Reg D offering may have at most 2,000 holders. If the cap
counts addresses, one investor with three wallets consumes three slots — or worse, evades the cap
entirely while every dashboard reports compliance. Counting identities is the only correct
implementation, and it cannot be added later because past addresses cannot be retroactively grouped.

---

## FreezeFacet

**What this is.** Indefinite freezing of part of a balance, by the compliance officer.

**Who it is for.** Compliance officers acting on a legal instruction; integrators displaying what is
actually spendable.

| Function | Does | Called by | Why |
|---|---|---|---|
| `getFrozenTokens(account) → uint256` | Total frozen: admin freeze **plus** unexpired lockups | Anyone, ERC-7943 | One number every integrator understands |
| `setFrozenTokens(account, amount) → bool` | Sets the admin freeze | COMPLIANCE_OFFICER | Court order, investigation, suspected compromise |
| `unfrozenBalanceOf(account) → uint256` | What can actually move now | UI, agents | The number a user cares about |
| `adminFrozenOf(account) → uint256` | Just the admin component | UI, audit | Distinguishes a freeze from a scheduled lockup |

**How to use it.** `setFrozenTokens` writes only the admin portion. Lockups are managed separately
through `LockupFacet`, and `getFrozenTokens` returns the sum. This keeps the standard's setter honest
while supporting any number of independent restrictions on the same balance.

**Why `getFrozenTokens` may exceed the balance.** ERC-7943 permits it, and it is the right behaviour:
freezing 1,000 tokens on an account holding 400 means the next 600 received are also frozen. It must
never revert.

---

## LockupFacet

**What this is.** Time-limited restrictions that expire on their own.

**Who it is for.** Issuers applying regulatory hold periods and vesting; investors seeing when their
tokens unlock.

| Function | Does | Called by | Why |
|---|---|---|---|
| `addLockup(account, amount, unlockAt, note)` | Locks an amount until a date | COMPLIANCE_OFFICER | Rule 144 hold periods, vesting, offering lockups |
| `clearLockups(account, reason)` | Removes all lockups early | COMPLIANCE_OFFICER | Correcting a mistake; reason mandatory |
| `releaseExpired(account)` | Prunes expired entries | **Anyone** | Housekeeping to bound gas |
| `lockupsOf(account) → Lockup[]` | Full schedule with dates and notes | Anyone, UI | An investor must see when tokens unlock |
| `lockedAmountOf(account) → uint256` | Currently locked total | Anyone | Feeds the frozen total |
| `lockupCount(account) → uint256` | Number of entries | UI, gas estimation | Pagination |

**How lockups expire.** By timestamp comparison, with no transaction. Nobody has to "unlock" anything;
no keeper is required; the state cannot go stale. `releaseExpired` is permissionless and purely
cosmetic — it tidies the array and cannot change the computed total.

**Why `note` is required.** Six months later, "why is 300 of my balance locked" must have an answer
that does not depend on someone's memory.

---

## MonetaryFacet

**What this is.** Creation, destruction and distribution of supply.

**Who it is for.** The issuer's finance function.

| Function | Does | Called by | Why |
|---|---|---|---|
| `issue(to, amount)` | Mints new tokens | SUPPLY_OPERATOR | Creating the asset's representation |
| `redeem(amount)` | Burns from the treasury | SUPPLY_OPERATOR | Buy-backs, redemptions, cancelling unsold supply |
| `distributeFromTreasury(to, amount, unlockAt)` | Sends to a holder, optionally with a lockup | SUPPLY_OPERATOR | Allocations, private placements, dividends in kind |
| `totalIssued() → uint256` | Lifetime issuance, never decreases | Reporting, auditors | Distinguishes "ever created" from "currently outstanding" |
| `lockCap()` | Makes the cap permanent | ISSUER_ADMIN | Irreversible by design: a cap that can be raised is not a cap |
| `setMaxSupply(newMax)` | Changes the cap | ISSUER_ADMIN | Follow-on rounds — **reverts if the cap was locked** |
| `capLocked() → bool` | Whether the cap is permanent | Anyone, investors | The strongest possible dilution guarantee |
| `treasury() → address` | The vault | Anyone | Provenance and reconciliation |
| `setTreasury(address)` | Points at a treasury | ISSUER_ADMIN | Initial wiring |
| `offeringRegistry() → address` | The sale contract | Anyone | Transparency |
| `setOfferingRegistry(address)` | Points at a registry | ISSUER_ADMIN | Initial wiring |

**How to use `issue`.** Default practice is minting to the treasury and distributing from there — one
custody point, clean accounting, easy reconciliation. Minting directly to a holder is the same
function with a different destination, and it still passes the full compliance pipeline.

**Why `totalIssued` exists separately from `totalSupply`.** After a redemption, supply falls but the
fact that tokens were once issued does not. Regulators and auditors ask for both.

**Why `capLocked` is irreversible.** A cap that can be unlocked is not a cap. Making the lock
permanent at deployment is what turns it into a guarantee an investor can rely on rather than a
current setting.

---

## RolesFacet

**What this is.** Access control. Four roles, deliberately separated.

**Who it is for.** Whoever governs the token — typically a board, a CFO and a compliance officer.

| Function | Does | Called by | Why |
|---|---|---|---|
| `grantRole(role, account)` | Gives a role | The role's admin | Onboarding staff and multisigs |
| `revokeRole(role, account)` | Takes it away | The role's admin | Offboarding, key compromise |
| `renounceRole(role)` | Gives up your own | The holder | Voluntary reduction of privilege |
| `hasRole(role, account) → bool` | Check | Anyone | Auditability |
| `getRoleMember(role, index) → address` | Enumerate | Anyone | Who actually holds power here |
| `getRoleMemberCount(role) → uint256` | How many | Anyone | Same |
| `roleAdmin(role) → bytes32` | Which role administers it | Anyone | Understanding the hierarchy |

**Why enumeration is public.** An investor should be able to see how many keys can freeze their assets
without asking the issuer. A role system that cannot be enumerated cannot be audited.

See [05 — Roles](05-roles.md) for what each role can and cannot do.

---

## EmergencyFacet — opt-in

**What this is.** Forced movement of tokens without the owner's consent.

**Who it is for.** Compliance officers acting on a court order, a regulatory instruction, or a
documented case of lost access.

**Not installed by default.** Adding it is a deliberate act by the issuer. A token without this facet
simply does not have these functions, and that is a meaningful thing to be able to tell investors.

| Function | Does | Called by | Why |
|---|---|---|---|
| `forcedTransfer(from, to, amount) → bool` | Moves tokens without consent | COMPLIANCE_OFFICER | Court orders; recovery from a compromised wallet |
| `forcedTransfer(from, to, amount, reason) → bool` | Same, with the justification on chain | COMPLIANCE_OFFICER | The audit trail regulators actually want |
| `forcedMint(to, amount, reason)` | Creates tokens outside the normal path | COMPLIANCE_OFFICER | Correcting an issuance error; compensation |
| `forcedBurn(from, amount, reason)` | Destroys tokens | COMPLIANCE_OFFICER | Recall, court-ordered cancellation |

**How `forcedTransfer` behaves, in order.** Unfreezes what it must and emits `Frozen` **before** the
transfer event, as ERC-7943 requires; enforces `canReceive` on the destination; moves the balance
directly, bypassing the rules; emits the ordinary `Transfer`, then `ForcedTransfer`, then
`ForcedOperation` with the reason.

**Why `canReceive` is still enforced.** A seizure to an unverified address would place a regulated
asset with an unknown party — solving one compliance problem by creating another. If a court names a
destination, that destination is onboarded first.

---

## PurchaseFacet

| Function | Does | Called by | Why |
|---|---|---|---|
| `purchase(offeringId, amount)` | Buys tokens in an active offering | Investor | The primary sale |
| `previewPurchase(offeringId, amount) → (cost, tokens, unlockAt)` | Calculates before committing | Investor, UI | Nobody should sign before seeing the price and the lockup |
| `refundPurchase(purchaseId)` | Claims a refund | Investor | Soft cap missed — the investor gets their money back without anyone's permission |

**Why `refundPurchase` is callable by the investor.** Operator-driven refunds are better UX, but an
operator who is absent, unwilling or insolvent must not be able to strand funds.

---

## IPolicySet

**What this is.** The contract that composes individual rules into a compliance regime.

**Who it is for.** Issuers configuring a regime; integrators reading what applies.

| Function | Does | Called by | Why |
|---|---|---|---|
| `evaluate(from, to, amount) → (ok, failingRule, reason)` | Runs every rule | The token, agents | The compliance decision |
| `addGroup(group)` | Creates an OR-group | UPGRADE_ADMIN | Expressing "professional **or** accredited" |
| `removeGroup(group)` | Deletes one | UPGRADE_ADMIN | Regime change |
| `addRule(group, rule)` | Adds a rule to a group | UPGRADE_ADMIN | Extending a regime |
| `removeRule(group, rule)` | Removes one | UPGRADE_ADMIN | Same |
| `groups() → bytes32[]` | All groups | **Anyone** | Public transparency of the live policy |
| `rulesOf(group) → address[]` | Rules in a group | **Anyone** | Same |
| `ruleCount() → uint256` | Total rules | Anyone, gas estimation | Cost visibility |
| `maxRules() → uint256` | The hard cap | Anyone | Proof that an admin cannot gas-grief the token |

**How composition works.** Groups AND together; rules inside a group OR. `(identity) AND (EU
professional OR US accredited) AND (sanctions clear)` covers essentially every real regime without a
general expression engine, which would be the easiest place to misconfigure a live policy and the
hardest thing to audit.

**Why the reads are public.** An investor must be able to determine their eligibility **before**
buying. A compliance regime nobody can inspect is one nobody should trust.

---

## IRule

**What this is.** A single compliance check. The extension point of the whole system.

**Who it is for.** Anyone. Writing a rule needs no permission from anybody.

| Function | Does | Called by | Why |
|---|---|---|---|
| `check(from, to, amount, ctx) → (ok, reason)` | Answers yes or no, with a reason | PolicySet | The atomic compliance decision |
| `bounds(account) → (min, max)` | Investment limits for this account | Offering registry | Accreditation-linked minimums |
| `ruleId() → bytes32` | Stable identifier | Tooling, UI | Rendering a rule in plain language |

**How to write one.** Keep `check` pure and cheap — it runs on every transfer. Read only from
`IIdentityRegistry`, token views and `Context`. Return a short specific `reason`; it surfaces directly
in `whyBlocked` and ends up in front of a user. Never revert for an ordinary "no" — return
`(false, reason)`.

**Why rules never write state.** A rule that stores data cannot be swapped without a migration, which
would destroy the agility the policy layer exists to provide. Where a rule appears to need state — a
holder cap — the **token** maintains the counter and the rule reads it.

---

## IIdentityRegistry

**What this is.** The source of truth about wallets. One interface, three interchangeable
implementations.

**Who it is for.** Rules read it. Issuers choose which implementation to install.

Three implementations ship, all behind this one interface: `AllowlistRegistry` (tier 0, own storage,
the open-source default), `EASAdapter` (tier 1, Ethereum Attestation Service) and `StoboxDIDAdapter`
(tier 2, StoboxDID). **The token neither knows nor cares which is installed** — swapping one for
another is a single `setIdentityRegistry` call and moves no balance.

| Function | Does | Called by | Why |
|---|---|---|---|
| `subjectOf(wallet) → bytes32` | Which identity owns this wallet | Token, rules | One person, many wallets |
| `isActive(wallet) → bool` | Verified, unexpired, unblocked, not deactivated | Token, rules, UI | The base eligibility gate |
| `claim(subject, key) → Claim` | One verified fact, with issuer and expiry | Rules | Jurisdiction, accreditation, screening |
| `hasValidClaim(subject, key) → bool` | Convenience check | Rules | The common case |

**Critical implementation requirement.** All four **must return rather than revert** for unknown
wallets. StoboxDID's `getUserDID` and `getAttribute` revert when a wallet has no DID, so every call in
that adapter is wrapped in `try/catch`. Without this the token breaks ERC-7943 conformance on the most
common case in existence: a transfer to a new address. See
[09 — Identity and DID](09-identity-did.md).

**Why claims are hashed.** The registry holds `valueHash`, not the value. A rule compares hashes, so
"is this investor in Germany" is answerable on chain without a country code — let alone a name —
appearing anywhere.

---

## Identity adapters

**What this is.** Three implementations of `IIdentityRegistry`, plus the few
administrative functions each needs. A token neither knows nor cares which is installed.

### `AllowlistRegistry` — tier 0

| Function | Does | Called by | Why |
|---|---|---|---|
| `allow(wallet)` | Permits an address | Registry admin | The whole of tier 0's eligibility model |
| `deny(wallet)` | Withdraws permission | Registry admin | Reversing a mistake, or acting on one |
| `link(wallet, subject)` | Binds several wallets to one person | Registry admin | Without it a tier-0 holder cap counts addresses, and one investor with two wallets defeats it |

### `EASAdapter` — tier 1

| Function | Does | Called by | Why |
|---|---|---|---|
| `bind(wallet, subject)` | Binds a wallet to an identity | Registry admin | EAS attests to recipients; the subject binding is ours |
| `record(subject, key, uid)` | Points a claim key at an attestation | Registry admin | The adapter holds the mapping; the attestation itself lives in EAS |

### `StoboxDIDAdapter` — tier 2

| Function | Does | Called by | Why |
|---|---|---|---|
| `mapKey(key, name)` | Maps a `bytes32` claim key to a StoboxDID attribute name | Registry admin | The adapter never guesses a name — a wrong guess reads empty and refuses silently |
| `claimForWallet(wallet, key)` | Reads a claim by **wallet** | Rules, integrators | StoboxDID indexes attributes by wallet; the adapter cannot invert that on chain |
| `hasValidClaimForWallet(wallet, key)` | The same question, as a boolean | Rules | The form a rule actually uses |

**Why tier 2 has two extra reads.** `IIdentityRegistry.claim` is keyed by subject, and StoboxDID
stores attributes against wallets. Inverting that mapping on chain would mean an enumeration the
registry does not support, so the adapter exposes the wallet-keyed form and returns empty from the
subject-keyed one rather than pretending to an answer it cannot compute.

---

## Treasury

**What this is.** The vault. One per token.

**Who it is for.** The issuer's finance function; the offering registry.

| Function | Does | Called by | Why |
|---|---|---|---|
| `token() → address` | Which token this serves | Anyone | Provenance |
| `deposit(asset, amount)` | Accepts tokens | Anyone | Funding the treasury |
| `initialise(token, issuer, offeringRegistry)` | Stands in for a constructor on a clone | Anyone, once | Minimal proxies have no constructor. The factory clones and initialises in one transaction, so nobody can get between the two; a clone initialised by anyone else is an address the factory never registered and nothing was ever sent to |
| `refund(asset, investor, amount)` | Returns investor payment | **The offering registry**, even while payments are locked | Refunding is precisely what the lock exists for; the issuer cannot reach this money and the registry can only send it back to whoever paid |
| `withdrawPayments(asset, to, amount, offeringId)` | Moves investor payment out | ISSUER_ADMIN | Refuses while that offering's payments are locked — the guarantee the treasury exists for |
| `withdrawERC20(asset, to, amount)` | Takes payment tokens out | SUPPLY_OPERATOR | The issuer collecting proceeds |
| `reserve(amount, offeringId)` | Commits supply to an offering | Offering registry | Buyers must be sure tokens exist |
| `release(amount, offeringId)` | Uncommits it | Offering registry | Offering cancelled or under-subscribed |
| `lockPayments(offeringId)` | Freezes investor money | Offering registry | Refundability until the soft cap |
| `unlockPayments(offeringId)` | Releases it | Offering registry | Soft cap met |
| `reservedOf(offeringId) → uint256` | Committed supply | Anyone | Investors verify availability |
| `availableBalance() → uint256` | Unreserved supply | Anyone, SUPPLY_OPERATOR | What can actually be moved |
| `paymentBalance(asset) → uint256` | Payment tokens held | Anyone | Raise transparency |

**Who may take money out is asked of the token, every call.** The treasury holds no role register of
its own and does not trust the address recorded when it was created: `withdrawPayments` requires
`ISSUER_ADMIN` and `withdrawERC20` requires `SUPPLY_OPERATOR`, both read from the token at the moment
of the call. Revoking a role therefore reaches the money — which is the one place where a revocation
that did not take effect would matter most.

**Why `withdrawERC20` sometimes reverts.** It refuses while any offering holding that asset is active
or closed with its soft cap unmet. **The treasury enforces this, not operator discipline.** An operator
who wants the money early cannot get it by calling in a different order, and one who forgets cannot
accidentally break refundability.

---

## uRWAFactory

**What this is.** The deployer. Permissionless.

**Who it is for.** Anyone issuing an asset.

The factory is itself a diamond. `CreateFacet` serves the two creation calls; `PackageFacet` and
`PresetFacet` hold the facet packages and policy presets they draw on; `RegistryFacet` records what
was deployed and answers `isFactoryIssued`; `FeeFacet` holds the fee token and amount, **which are
zero in the open distribution**; `DiamondCutFacet` and `DiamondLoupeFacet` are as above.

| Function | Does | Called by | Why |
|---|---|---|---|
| `createToken(params) → (token, treasury)` | Deploys and wires everything | **Anyone** | One transaction from nothing to a working compliant token |
| `createTokenWithOffering(params, offering) → (token, treasury, id)` | Same, plus the first sale | Anyone | Fewer steps for the common case |
| `registerPackage(id, cuts)` | Defines a facet set | FACTORY_ADMIN | Versioned feature sets |
| `packages(id) → FacetCut[]` | Reads one | Anyone | Verify what you are deploying |
| `packageOf(id) → FacetCut[]` | The facets a package installs | Anyone | Diff a deployed token against the published package |
| `presetOf(id) → (rules, groups)` | The rules a preset composes | Anyone | An investor reads the regime before the token exists |
| `registerPreset(id, rules, groups)` | Defines a regime | FACTORY_ADMIN | Reg D, Reg S, MiFID II, MiCA |
| `presets(id) → (address[], bytes32[])` | Reads one | Anyone | Verify before choosing |
| `setFeeToken(address)` / `setFee(uint256)` | Configures a fee | FACTORY_ADMIN | **Zero in the open distribution** |
| `feeToken()` / `fee()` | Reads it | Anyone | Anyone can verify the open build charges nothing |
| `deploymentsOf(issuer) → address[]` | Tokens by issuer | Anyone | Portfolio views |
| `allDeployments() → address[]` | Everything | Anyone | Ecosystem visibility |
| `isFactoryIssued(token) → bool` | Did this factory create it? | Anyone | **Distinguishes a real issuance from a misconfigured fork in one call** |

**Why `createToken` has no access control.** A permissioned factory is a gatekeeper, and the point of
this project is that there is no gatekeeper. `FACTORY_ADMIN` governs only the factory's own
configuration and can never touch a deployed token — which is the deliberate departure from designs
where the factory retains admin rights over everything it created.

**Why `isFactoryIssued` matters commercially.** When someone misconfigures a fork and loses money, the
question "was that one of yours" must be answerable in seconds, publicly, by anyone, without your
cooperation.

---

## AssetPassport

**What this is.** The record of what the asset actually is. Interface open, Stobox implementation
proprietary.

**Who it is for.** Diligence teams, allocators, custodians, auditors.

| Function | Does | Called by | Why |
|---|---|---|---|
| `mint(passportId, issuer)` | Creates a passport | PASSPORT_ISSUER | An asset gets a record before any token exists |
| `anchorSnapshot(passportId, snapshot)` | Commits the current record | PASSPORT_ISSUER | One 32-byte root covering every datapoint |
| `declareToken(token, chainId)` | Token claims a passport | Token's ISSUER_ADMIN | One half of the handshake |
| `confirmToken(passportId, token, chainId)` | Passport confirms the token | PASSPORT_ISSUER | The other half — **only this side proves provenance** |
| `revokeToken(passportId, token)` | Withdraws confirmation | PASSPORT_ISSUER | The link was wrong or the asset changed |
| `grantAccess(passportId, grant)` | Lets someone read private data | Passport owner | Diligence under an NDA |
| `revokeAccess(passportId, grantee)` | Ends it | Passport owner | Deal over |
| `recordAttestation(passportId, attestation)` | Signs a fact | ATTESTOR | An auditor's own signature, not the issuer's claim |
| `snapshotOf(passportId) → (Snapshot, bool stale)` | Latest commitment + freshness | Anyone | **Staleness is a value, not a UI convention** |
| `tokensOf(passportId) → address[]` | Confirmed tokens | Anyone | One asset, several tranches |
| `passportOf(token) → bytes32` | Reverse lookup | Anyone | Start from the token, find the asset |
| `isConfirmed(passportId, token) → bool` | Is the link real? | Anyone | The only state that proves provenance |
| `attestationsOf(passportId) → Attestation[]` | Who signed what, when | **Anyone** | Signal without disclosure |
| `verify(passportId, code, value, salt, proof) → bool` | Checks a disclosed value | Anyone | Verify without trusting the issuer |
| `verifyAbsence(passportId, code, proof) → bool` | Proves something is **not** recorded | Anyone | "There is no legal opinion" is what diligence checks |
| `accessOf(passportId, grantee) → AccessGrant` | Current grant | Anyone | Who has access is public even when the data is not |

**How the handshake works.** Anyone can *declare* a passport. Only the passport can *confirm*. A
declared-but-unconfirmed link is exactly what a forgery looks like, and integrators must treat it that
way.

**Why attestation metadata is public while values are not.** A counterparty can see that a named audit
firm signed the reserve figure eleven days ago, valid for ninety days — without seeing the figure.
That answers most of the diligence question before anyone signs an NDA.

**Why `verifyAbsence` exists.** A system that can only prove presence lets an issuer hide an
inconvenient fact by omitting it. Absence must be as provable as presence.

---

## AttestorRegistry

| Function | Does | Called by | Why |
|---|---|---|---|
| `registerKey(attestor, validFrom, validTo)` | Records a signing key and its window | PASSPORT_ADMIN | Attestors rotate keys |
| `revokeKey(attestor)` | Ends validity | PASSPORT_ADMIN | Compromise |
| `isValidAt(attestor, timestamp) → bool` | Was this key valid then? | Verifiers | **History must survive a rotation** |
| `attestors() → address[]` | Recognised signers | Anyone | Who this passport trusts |

**Why validity windows.** Checking a signature against the *current* key would invalidate every past
attestation the moment a firm rotated its key. Checking against the key valid **at signing time**
keeps history intact.

---

## OfferingRegistry

**What this is.** The primary sale.

**Who it is for.** Issuers running a raise; investors buying.

Also a diamond, split by concern so the read path can never be blocked by an upgrade to the write
path: `OfferingGovernanceFacet` (create, activate, pause, close, cancel), `OfferingPurchaseFacet`
(purchases, allocation, pricing), `OfferingRefundFacet` (operator push and investor pull),
`OfferingRuleFacet` (offering-level rules) and `OfferingStorageFacet` (all reads).

| Function | Does | Called by | Why |
|---|---|---|---|
| `createOffering(params) → id` | Defines a sale | OFFERING_OPERATOR | Price, caps, dates, rules, regime |
| `activate(id)` | Opens it | OFFERING_OPERATOR | Go live |
| `pause(id)` / `unpause(id)` | Suspends and resumes | OFFERING_OPERATOR | Issues mid-raise |
| `close(id)` | Ends purchasing | OFFERING_OPERATOR | End date or hard cap |
| `cancel(id, reason)` | Aborts | OFFERING_OPERATOR | Raise abandoned; refunds follow |
| `settle(id)` | Releases proceeds | **Anyone**, once soft cap met | The issuer collects |
| `beginRefunding(id)` | Starts refunds | **Anyone**, once soft cap missed | Investors get their money back |
| `refundBatch(id, limit)` | Refunds many at once | OFFERING_OPERATOR | Good UX at scale |
| `claimRefund(purchaseId)` | Refunds yourself | Investor | The backstop that makes refunds a guarantee |
| `addRule(id, rule)` / `removeRule(id, rule)` | Offering-level compliance | OFFERING_OPERATOR | Accreditation, geography, allocations |
| `offeringOf(id) → Offering` | Full terms | Anyone | An investor reads terms before buying |
| `statusOf(id) → uint8` | Current state | Anyone | Can I still buy? |
| `purchaseOf(purchaseId) → Purchase` | One purchase | Investor, audit | Receipts |
| `purchasesOf(investor) → uint256[]` | All of an investor's purchases | Investor, UI | Portfolio |
| `raisedOf(id) → uint256` | Progress | Anyone | Soft cap visibility |
| `previewPurchase(id, amount) → (cost, tokens, unlockAt)` | Calculates | Anyone, UI | See price and lockup before signing |

| `setDefaultPaymentTokens(tokens[])` | Chain-wide payment token list | REGISTRY_ADMIN | One list, not one per offering |
| `forceStatus(id, status, reason)` | Overrides a stuck offering | REGISTRY_ADMIN | Recovery of last resort; reason mandatory and evented |

`REGISTRY_ADMIN` administers the registry contract itself and can neither move a token nor touch a
balance. Its two powers are chain-wide configuration and the recovery override — which is why
`forceStatus` records a reason on chain rather than silently changing state.

**Why `settle` and `beginRefunding` are permissionless.** Both are mechanical consequences of facts
already true on chain — the soft cap was met or it was not. Requiring an operator to act would let an
absent operator hold investor funds hostage.

---

## AgentAuthority

**What this is.** The bounds on what an automated agent may do for a principal.

**Who it is for.** Issuers automating operations; market-making agents; anyone delegating to software.

| Function | Does | Called by | Why |
|---|---|---|---|
| `grant(mandate) → mandateId` | Authorises an agent within limits | Principal | Delegation with a hard ceiling |
| `revoke(mandateId)` | Cancels, immediately | Principal | **The kill switch — no timelock** |
| `check(mandateId, scope, token, counterparty, amount) → (bool, reason)` | Is this action permitted? | The agent, before acting | Free pre-flight, same idea as `canTransfer` |
| `consume(mandateId, amount)` | Draws against the mandate's limits, or reverts | The scoped function being called | The agent cannot exceed its mandate, rather than being trusted not to |
| `mandateOf(mandateId) → Mandate` | The mandate's terms | Principal, agent, anyone | Bounds are public, so a counterparty can see them |
| `consumed(mandateId) → (thisEpoch, epochEnds)` | Budget used and remaining | Principal, agent | Monitoring |
| `mandatesOf(principal) → bytes32[]` | Every live mandate | Principal | **You cannot lose track of your own agents** |

**How a mandate bounds an agent.** Scope, token allowlist, counterparty allowlist, per-action cap,
per-epoch cap and a mandatory expiry. Exceeding any of them reverts. The agent is not trusted to
respect its mandate — it is unable to exceed it.

**What no scope ever grants.** Minting, role changes, upgrades, freezing, seizure or pause. Those
require a human role holder, and there is no mandate that can include them.

---

## AtomicDvP

**What this is.** Delivery versus payment in a single transaction. Both legs move or neither does.

**Who it is for.** Secondary trading, market makers, agent-to-agent settlement.

| Function | Does | Called by | Why |
|---|---|---|---|
| `settle(instruction, sellerSig, buyerSig) → settlementId` | Executes both legs atomically | Either party, or their agent | **Settlement risk cannot occur** |
| `previewSettle(instruction) → (ok, stage, rule, reason)` | Will this trade work? | Anyone, agents | Check before signing, for free |
| `cancel(instruction)` | Invalidates a signed instruction | Either party — enforced | Change of mind before settlement |
| `isSettled(nonce) → bool` | Already done? | Anyone | Replay protection |

**Why signatures rather than approvals.** Both parties sign off-chain; either side or their agent
submits. No standing allowance is granted to a counterparty, the terms are fixed at signing, and a
matching agent can execute a trade it negotiated **without ever holding custody of either leg**.

**Why this removes settlement risk rather than reducing it.** Conventional settlement runs securities
and cash on separate ledgers, so there is always an interval where one leg has moved and the other has
not. Here both legs are transfers in one transaction on one chain. There is no interval.

**And the part that is genuinely new:** the security leg passes the token's own compliance pipeline as
part of the atomic operation. A non-compliant trade **cannot settle** — not "is detected and
reversed". That is only possible because the compliance system and the settlement system are the same
system.

---

## Related documents

- [06 — States](06-states.md) — what the return values mean
- [08 — Compliance pipeline](08-compliance-pipeline.md) — the order these run in
- [14 — Events and errors](14-events-errors.md) — what each function emits
- [21 — Interface specification](21-interface-specification.md) — how a user reaches these
