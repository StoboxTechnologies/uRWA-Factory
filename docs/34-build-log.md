# 34 — Build log

One entry per working session, newest first. This is the build's own history: what shipped, what was
audited, what the audit found, and what was left open. The next session opens by reading the top entry
and [26 — Handoff](26-handoff.md), and starts from the recorded gaps before new work.

The discipline every entry records is fixed, and defined in [working rules](../CLAUDE.md#the-session-cycle):

1. **Build** the session's work.
2. **Audit it** — `verify.py`, `forge test`, and a multi-agent adversarial audit for substantive change.
3. **Audit the audit** — `verify.py --self-test`, every new test proven by reverting its fix, every
   finding verified by an independent skeptic before it is acted on.
4. **Log** the session here.
5. **Refresh** the handoff.

An entry is written even when a session finds nothing — "audited, clean" is a result worth recording.

---

## 2026-08-16 · Session 7 — the stack becomes a script an operator can run

**Shipped.** `script/Deploy.s.sol` — doc 16's deployment flow, executable. `DeployStack` stands up
everything a chain needs once: facet implementations, the factory, the offering registry, the tier-0
allowlist, the shared rules, and registers the `base.v1` / `base+purchase.v1` packages and the
`RegD506c` / `RegS` / `Open` presets. `DeployDemoToken` performs the per-asset steps for a first
token. `script/README.md` is the operator manual: commands, environment, and a post-deploy
verification section where every check is a `cast` call needing no trust in the deployer — including
proving seizure absent through the loupe.

**Design decisions recorded.** The deploy logic lives in `StackDeployer`, which both the broadcast
scripts and `Deploy.t.sol` run — CI deploys through the operator's exact code on every commit, so
the script cannot rot silently. No emergency package: installing seizure stays a deliberate act by
cut. No MiCA presets: `MiCARule` is parameterised by the issuer's subject, so a MiCA regime is
composed per issuance. Sanctions freshness ships at zero until `PA-03` settles the windows — noted
in the script where an operator will read it. The factory's admin is the broadcaster and is not
transferable; the manual says to deploy from the multisig that should hold it permanently.

**Audited.** `verify.py` 44/44, self-test 44/44, `forge test` 184/184 across 16 suites, 7/7 tools.
`Deploy.t.sol` proves: the deployed stack sells a token end to end (create → issue → offer →
purchase through the token door → settle → deliver → onward transfer); the registered preset is
attached, officer-owned and enforcing; **every selector both packages promise routes to its facet**
— the drift between a registered package and the real facet surfaces that unit tests cannot see; and
the presets compose exactly as doc 10 writes them.

**Found.** Nothing new in this session's work.

**Open.** `OP-04`: run the two scripts on Base Sepolia, verify the contracts, publish the addresses —
the first demo token on a real chain. Needs funded keys and RPC/BaseScan env, so it is an operator
step, not a CI one. Then branch coverage on the thin files, then `TO-01`.

---

## 2026-08-16 · Session 6 — offering rules enforced, and the token-side door

**Shipped.** `CU-05` and `CU-06`, taking Phase 3 to 9 of 11. This was also the first session run
under the protocol this log records — it opened from session 5's open items, exactly as intended.

- **`CU-05`** — offering-level rules were stored and never evaluated. Purchases now run every
  attached rule under the policy plane's discipline: one 100k gas budget per rule, a rule that
  reverts counts as a refusal, the list capped at 24, and rule `bounds` tighten the offering's
  min/max per investor but never loosen them. The refusal names the rule and its reason.
- **`CU-06`** — the `PurchaseFacet`: a wallet does everything against the token's address. The facet
  forwards its caller into the registry's `purchaseFor`/`claimRefundFor`, which only the offering's
  own token may call; both doors funnel into the registry's single `_purchase`/`_refund` paths, so
  the facet cannot be a way around any check. The refactor that made this safe was one internal
  path with two doors — the `L4.10` shape again.

**Audited.** `verify.py` 44/44 and self-test 44/44; `forge test` 180/180 across 15 suites; 7/7
tools. Every mechanism proven by reverting it: removing the rule evaluation fails three tests,
removing the `purchaseFor` guard fails a fourth. The end-to-end suite `PurchaseDoor.t.sol` runs
primary issuance with **no stubs on the money path** — factory-made diamond, real treasury clone,
real registry: wallet → token door → registry → treasury lock → settlement → delivery through the
real pipeline, and the refund chain reversed. This is the standing answer to session 4's finding
that a permissive stub had hidden a broken production path.

**Found.** Two stale claims in the README (a "Specification" status badge, "36 checks" in the build
section) — corrected. Nothing in this session's own code.

**Open.** The deployment script — factory, package, rules and presets stood up in one run: the
executable core of the implementation manual and the path to the first demo token. Then branch
coverage on the thin files, and `TO-01`. `CU-07` and `AG-04` stay parked/planned as recorded.

---

## 2026-08-16 · Session 5 — presets applied, tiered and multi-currency pricing

**Shipped.** `PO-08` and `CU-03`, closing Phase 2 and taking Phase 3 to 7 of 11.

- **`PO-08`** — regime presets are now *applied* at creation, not merely recorded. The preset model
  became parallel arrays (`rules[i]` in `groups[i]`, so groups AND and rules within a group OR), and
  `createToken` bakes each token its own `PolicySet` from the recipe, owned by that token's compliance
  officer — no shared central party can alter one token's live compliance. `PolicySet.transferOwnership`
  added for the hand-off.
- **`CU-03`** — tiered pricing walks the bands from where the offering has already sold (a purchase
  crossing a boundary pays each band for the tokens that fall in it; past the last band is priced at
  it, never at zero), and multi-currency lets the buyer name any listed currency, refusing an unlisted
  one rather than retargeting it.

**Audited.** `verify.py` 44/44; `verify.py --self-test` 44/44 (every check fails its fixture);
`forge test` 168/168; `forge fmt --check` clean; `report.py` 7/7 tools green. New checks earned their
keep by reverting the fix: the preset tests fail if `createToken` does not apply the preset; the
pricing tests fail if a band or the currency guard is removed. `L3.5` caught the undocumented
`PaymentTokenNotAccepted` error before commit and it was added to doc 14.

**Found.** No new defects in this session's own work. One interaction documented rather than fixed:
`HasValidIdentity` checks the sender too, so a trusted treasury needs its own identity claim to
distribute — realistic, and recorded in the preset test.

**Open.** `CU-05` (offering-level rules) and `CU-06` (PurchaseFacet, token side) remain; `CU-07` (the
registry facet split) stays parked behind the audit by design. Then the deployment script — the
executable core of the implementation manual and the path to a first demo token.

---

## 2026-08-16 · Session 4 — full multi-agent audit, and its remediation

**Shipped.** A complete adversarial audit of every Solidity file and the verification tooling, then
the fixes, in batches A–D (`a9160e9`…`f99fb00`).

**Method.** Eight finder agents, one subsystem and lens each — ledger/diamond, compliance, money,
offerings, policy/identity, agents/DvP, test quality, and the Python tooling itself. Every finding
above "low" went to two independent skeptics prompted to refute it, one on the mechanics and one on
economic reachability. Only findings surviving both returned; each was then re-read by hand against
the code before any fix.

**Found.** 18 confirmed (1 critical, 9 high, 8 medium), 1 split, 3 refuted, 2 low. The critical:
`Treasury.withdrawERC20` never checked the payment lock, so a supply operator could drain locked
investor funds. Highs clustered in the money path (refunds that left investors holding free tokens; a
`cancel` that reopened a settled offering; per-offering locks that a caller-chosen id could bypass),
in identity (`StoboxDIDAdapter.hasValidClaim` hard-coded false, bricking every tier-2 token; a
jurisdiction rule that accepted revoked claims), and in the gas ceiling applied to the whole policy
set rather than per rule. The tooling audit found `report.py` reporting the open-boundary grep as
clean when grep errored.

**Fixed.** All 18, each with a test that fails without the fix. The money path was reworked:
per-asset payment locking, delivery at settlement (a failed offering delivers nothing to claw back),
a forward-only offering state machine. One finding deferred with rationale — subject accounting
cannot follow a wallet re-link (`CO-05`), recorded in doc 26 and the audit log.

**Audited the audit.** Every check still fails its own fixture; every fix reverted to confirm its
test catches it; the skeptic pass killed 3 finder claims that did not survive scrutiny.

**Open.** The deferred re-link finding; branch coverage on the thinnest files before the pre-audit
freeze.

---

## 2026-08-16 · Session 3 — the caller check, and the loupe made honest

**Shipped.** `L3.6` (every documented caller is enforced by the implementation) and `CO-02a` (the
full loupe, moved into the immutable ledger core).

**Found, by writing `L3.6`.** Three functions whose only guard was the sentence in the documentation:
`ComplianceFacet.afterUpdate` moved the holder counters with no caller check; `AtomicDvP.cancel` was
forgeable; the treasury trusted a stored address rather than the token's live role register, so a
revoked role kept its withdrawal rights. The loupe's own bookkeeping was maintained on the way in
only, so a replaced or removed selector left the report contradicting the router.

**Fixed.** All four, with tests. The loupe's five selectors are now immutable, and the diamond appears
in its own report so the immutable set is enumerable rather than asserted.

**Open.** A full logic audit — which became session 4.

---

## 2026-08-16 · Session 2 — Phases 1–3 built out

**Shipped.** Supply, roles and custody; the factory; the policy engine and eight rules; three identity
tiers behind one interface; primary issuance; agent mandates and atomic DvP. Phase 1 closed with the
open-source claim as a running test (`FreshChain`), Phase 2 with the three adapters.

**Audited.** Each area landed with its own suite and its `L4` invariant owner. Recurring hazard
recorded for later sessions: `vm.prank`/`vm.expectRevert` consumed by a helper call in an argument
list — cost eight tests in one sitting.

**Open.** The handoff and a systematic audit — sessions 3 and 4.

---

## 2026-08-15 · Session 1 — specification and the ledger core

**Shipped.** The documentation site and build pipeline, the verification framework (`verify.py` with
its self-test), and the first contracts: the compliance pipeline, subject accounting (counting people
not addresses), and freeze/lockups with one implementation of the composed total.

**Established.** The two disciplines everything since has run under: the documentation is verified
against the code in both directions, and every check must fail its own known-bad fixture.

**Open.** The rest of the build — sessions 2 onward.

---

## Related

- [26 — Handoff](26-handoff.md) — the current end state and what to do next
- [33 — Test results](33-test-results.md) — the latest recorded run
- [31 — Verification framework](31-verification.md) — what each check means
