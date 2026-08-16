# Working rules for this repository

## The session cycle

Every working session follows the same cycle, and none of it is optional:

1. **Build** the session's work.
2. **Audit it** — `python3 verify.py`, `forge test`, and for any substantive change a multi-agent
   adversarial audit (finders by subsystem, plus skeptics that try to refute each finding).
3. **Audit the audit** — `python3 verify.py --self-test` (every check must fail its own fixture),
   every new test proven by reverting its fix, every finding re-read against the code before it is
   acted on.
4. **Log** the session in [docs/34-build-log.md](docs/34-build-log.md) — newest entry first: what
   shipped, what was audited and its results, what the audit found and how it was resolved, what is
   open. Write an entry even when nothing was found; "audited, clean" is a result.
5. **Refresh the handoff** — [docs/26-handoff.md](docs/26-handoff.md) must reflect the end state.

The commit that closes a session includes its build-log entry. The next session opens by reading the
top of the build log and the handoff, and starts from the recorded gaps before taking on new work.
This makes the *process* auditable, not only the code: a gap found in one session is provably carried
into the next rather than lost.

## The design system is one file

`theme.css` at the repository root declares every colour, face, radius, shadow and control in this
project. It is not a starting point to copy from — it is the only place those decisions exist.

**Any new HTML page — prototype, console, production interface, one-off demo — links it and inherits
the whole system. This needs no instruction and no approval; it is the default.**

```html
<link rel="stylesheet" href="theme.css">      <!-- repository root -->
<link rel="stylesheet" href="../theme.css">   <!-- prototypes/ -->
```

The page's own `<style>` block carries only what is true of that page alone: its layout, its measure,
its one-off components. Never:

- declare a token (`--ground`, `--ink`, `--accent`, `--spot`, `--r-pill`, `--sh-card`, …) — inherit it;
- load a web font — `theme.css` imports Inter for non-Apple platforms;
- restate a rule that already lives in `theme.css` — if a control needs a new variant, add the
  variant to `theme.css`, where every page gets it.

`verify.py` `L0.12` fails the build on all three. Changing how everything looks is one edit to one
file; do it there.

`index.html` is the exception that proves the rule: it *inlines* `theme.css` at build
time, from the same file, because it must travel as one self-contained artefact. `build-docs.py`
reads the file — it does not hold a copy.

The system itself is documented in [docs/25-design-system.md](docs/25-design-system.md): the tokens,
their measured contrast ratios, and the six rules the surfaces are held to. Read it before changing
a value; update it in the same commit if you do.

## Everything is verified

`verify.py` is the contract. Run it before reporting any change as done:

```bash
python3 build-docs.py && python3 verify.py && python3 verify.py --self-test
```

`build-docs.py` regenerates three surfaces from `docs/*.md` and `theme.css`:

| Output | What it is |
|---|---|
| `index.html` | The whole documentation on one page — what the folder opens on |
| `start.html` | One card per document, for people who know what they want |
| `pages/*.html` | Each document as its own page, with previous/next |

All three are committed, and CI fails if they are stale — so rebuild in the same commit as any change
to a document or to the theme. Never hand-edit them.

The masthead, the author and the reason the work is given away belong to `index.html` alone; the other
surfaces open with a one-line breadcrumb. Anything added to the shared chrome lands on 36 pages.

Every check in `verify.py` must appear in [docs/31-verification.md](docs/31-verification.md) and must
fail on its own fixture (`--self-test`). A new check needs both, or L2.16 and L5 fail.

## Contracts

```bash
forge build && forge test && forge fmt --check
```

`src/` is interfaces and storage only — no implementation yet. The storage layout in
`src/storage/Layout.sol` is **frozen**: append fields, never insert or reorder, because in a diamond
those fields hold live balances.

`L3.1`…`L3.5` compare the Solidity with the documentation in both directions, so a function added to
an interface must be added to [docs/07-functions.md](docs/07-functions.md) in the same commit, and an
event added to either must be added to [docs/14-events-errors.md](docs/14-events-errors.md).

## Test results

```bash
python3 report.py
```

Runs every tool and writes [docs/33-test-results.md](docs/33-test-results.md). Generated — never edit
it by hand. It carries a timestamp, so regenerating it always produces a diff; commit it when the
results actually changed, not on every run.

## Prose

Documentation is written, not generated. Keep the register of the surrounding text, keep claims
verifiable, and do not add a figure or a claim the sources do not support.
