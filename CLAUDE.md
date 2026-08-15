# Working rules for this repository

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

`build-docs.py` regenerates `index.html` from `README.md`, `docs/*.md` and `theme.css`.
The built file is committed, and CI fails if it is stale — so rebuild in the same commit as any
change to a document or to the theme. Never hand-edit `index.html`.

Every check in `verify.py` must appear in [docs/31-verification.md](docs/31-verification.md) and must
fail on its own fixture (`--self-test`). A new check needs both, or L2.16 and L5 fail.

## Prose

Documentation is written, not generated. Keep the register of the surrounding text, keep claims
verifiable, and do not add a figure or a claim the sources do not support.
