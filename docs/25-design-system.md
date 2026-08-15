# 25 — Design system

One light theme, applied to the documentation site and every prototype, from one file:
[`theme.css`](../theme.css). Nothing else declares a colour, a face, a radius or a shadow.

## The decision

**A single committed light theme: near-black type on Apple grey, with one aqua spot colour.**

Dark mode was removed deliberately. A dual-theme system doubles every colour decision and is where
most contrast bugs live — a value defined only inside a media query renders one theme's text on the
other theme's ground. Committing to one theme means every colour is painted explicitly and there is
one thing to get right.

Every surface sets its own `background` and `color` from tokens rather than inheriting, so the page
holds on any host background.

## Tokens

### Ground and surfaces

| Token | Value | Use |
|---|---|---|
| `--ground` | `#F5F5F7` | Page canvas |
| `--surface` | `#FFFFFF` | Cards, panels, inputs |
| `--sunk` | `#F0F2F8` | Inline code, hover states, quiet fills |
| `--dark` | `#0C0C0F` | Inverted sections and filled controls |

### Ink

| Token | Value | Contrast on `--ground` | Use |
|---|---|---|---|
| `--ink` | `#1D1D1F` | 15.4:1 | Headings and primary text |
| `--ink-2` | `#3C3C43` | 10.1:1 | Body copy in tables and cards |
| `--muted` | `#57575B` | 6.6:1 | Supporting text |
| `--faint` | `#6E6E73` | 4.7:1 | Labels, captions, metadata |

`--faint` is the lightest ink in the system and still clears 4.5:1 on both `--ground` and
`--surface`. Nothing lighter is used for text. The two lightest greys are one step darker than the
Apple originals they are drawn from, which sit at roughly 3.3:1 and fail at caption sizes.

### Lines

| Token | Value | Use |
|---|---|---|
| `--rule` | `#E2E4E9` | Default hairline. Almost invisible, on purpose |
| `--rule-strong` | `#D2D5DB` | Input borders, emphasis |

Separation comes from space first, a hairline second, and a border only when a boundary is genuinely
structural. Depth comes from `--sh-card`, never from a heavy line.

### Emphasis

The primary action is **black**, not coloured. Colour is reserved for the one thing on a screen that
should be seen before anything else.

| Token | Value | Use |
|---|---|---|
| `--accent` | `#0C0C0F` | Primary buttons, active state, links |
| `--accent-2` | `#1D1D1F` | Hover — black lifts rather than darkens |
| `--accent-wash` | `#F5F5F7` | Selected rows, quiet fills |
| `--accent-edge` | `#E2E4E9` | Border on emphasised surfaces |

### The spot colour

| Token | Value | Use |
|---|---|---|
| `--spot` | `#22D3EE` | Eyebrow badges, the highlighted phrase, one emphasised quantity |
| `--spot-2` | `#0EBDD9` | Hover on a spot-filled control |
| `--spot-ink` | `#0C2E33` | Text on a spot fill — 8.0:1 |
| `--spot-text` | `#0E7490` | Spot-family text on white — 5.4:1 |
| `--spot-wash` | `rgba(34,211,238,.22)` | Selected option, active navigation, quiet strips |
| `--spot-edge` | `#A5E9F4` | Border on a washed surface |

Aqua marks emphasis and nothing else: an eyebrow badge, the one highlighted phrase, the audience tag
on a card, the free share of a position. It never carries status, never fills a large area, and is
never used as text on white — that is what `--spot-text` is for. The moment it decorates something
that is not the point of the screen it stops meaning anything.

### You are here

Every menu marks its selection, and marks it the same way — an aqua wash, an aqua ring and heavier
text, so the mark is legible without relying on colour:

```css
background: var(--spot-wash);
color: var(--accent);
font-weight: 600;
box-shadow: inset 0 0 0 1px var(--spot-edge);
```

It applies to the current page in the site navigation (`a[aria-current="page"]`), the open section in
the token console (`.nb.on`), and the section being read in the documentation contents
(`a[aria-current="true"]`, set as you scroll). The state is carried by `aria-current`, not by a class,
so a screen reader announces it too. The documentation's contents list marks the section under a line
a quarter down the viewport, and scrolls the mark into view inside the list without moving the page;
without JavaScript the list behaves as a plain set of links.

### Status

| Token | Value | Meaning |
|---|---|---|
| `--ok` | `#0F7A5F` | Passed, verified, eligible — 5.3:1 |
| `--warn` | `#B45309` | Needs attention, irreversible, locked — 5.0:1 |
| `--crit` | `#B42318` | Refused, failed, unverified — 6.6:1 |

Status is never encoded in colour alone. Every status carries a word, a mark, or both — required for
accessibility and for anyone reading a screenshot in greyscale. Status green is deliberately distinct
from the aqua spot colour: one reports a fact, the other draws an eye.

### Shape

| Token | Value | Applied to |
|---|---|---|
| `--r` | `10px` | Inputs, small controls, nav items |
| `--r-md` | `12px` | Notes, code blocks, small panels |
| `--r-lg` | `20px` | Cards, tables, figures |
| `--r-pill` | `980px` | **Every button**, chips, pills, status dots, step markers |

Controls are pills. Containers are soft rectangles. Nothing in the system has a sharp corner.

### Depth

```css
--sh:      0 1px 3px rgba(0,0,0,.08), 0 4px 12px rgba(0,0,0,.04);
--sh-lg:   0 8px 20px -4px rgba(0,0,0,.1), 0 4px 8px -2px rgba(0,0,0,.05);
--sh-card: 0 10px 30px -24px rgba(0,0,0,.3);
```

`--sh-card` is the default on cards: a heavily negative spread, so the shadow reads as the card
sitting on the page rather than floating above it. `--sh-lg` is reserved for hover.

### Type

| Role | Stack |
|---|---|
| `--display` | SF Pro Display → Inter → system sans |
| `--body` | SF Pro Display → SF Pro Text → Inter → system sans |
| `--mono` | JetBrains Mono → SF Mono → IBM Plex Mono → system mono |

All sans. `theme.css` imports Inter from Google Fonts once, so non-Apple platforms get the same
shapes; on macOS and iOS the system face wins and nothing is fetched for the visible text.

Headings run at weight 700 with tight negative tracking that scales with size: `-.038em` on the
masthead, `-.034em` on section titles, `-.022em` at 20px. Body text sits at `-.005em`. Measure stays
at 74 characters; line height is 1.7 in body copy, because most of these surfaces are read rather
than scanned.

### Diagrams

Every diagram opens with the same header band: a 56px tile in the spot colour at 16% carrying a 32px
line glyph stroked in `--accent`, the word `DIAGRAM`, the subject, and a hairline under all three. The
glyph is the diagram's one piece of ornament and it does the work of a title — the sixteen glyphs are
distinct enough to tell the diagrams apart in a contact sheet.

Diagrams are drawn only in the tokens above; `verify.py` `L0.11` pins every colour literal to one, and
fails a diagram that has no header. Text colour is always set by a class, never by a `fill` attribute,
because a scoped `text{fill:…}` rule silently beats an inline fill.

## Rules

1. **Space before lines.** Reach for a gap before a border.
2. **Black is the action; aqua is the emphasis.** One black control per view, and aqua only on what
   the view is actually about.
3. **Never colour alone.** Status carries a word or a mark as well, and the selected menu item
   carries a ring and heavier text as well as its wash.
4. **Every button is a pill.** No exceptions in this system.
5. **Focus is always visible.** A 2px black outline at 2px offset plus an aqua ring, on every
   interactive element. The ring alone is not enough contrast to carry focus by itself.
6. **No gradients, no glow.** Depth comes from shadows and nothing else. The one blurred surface is
   the sticky site navigation, which is translucent so the page reads through it.

## Where it is applied

| Surface | File | How it gets the system |
|---|---|---|
| Design system | `theme.css` | — it *is* the system |
| Documentation site | `build-docs.py` → `index.html` | Inlined at build time |
| Prototype index | `prototypes/index.html` | `<link href="../theme.css">` |
| Deploy console | `prototypes/deploy-console.html` | `<link href="../theme.css">` |
| Token console | `prototypes/token-console.html` | `<link href="../theme.css">` |
| Public verifier | `prototypes/verifier.html` | `<link href="../theme.css">` |
| Investor page | `prototypes/investor.html` | `<link href="../theme.css">` |

The documentation page inlines the file rather than linking it, because it is meant to travel as one
self-contained artefact. Everything else links it. When the production interfaces are built in
Phase 5, they link the same file.

## Adding a page

A new page needs one line, and inherits everything — tokens, base, controls, containers, marks, site
navigation, the web font, and the reduced-motion behaviour:

```html
<link rel="stylesheet" href="../theme.css">   <!-- prototypes/ -->
<link rel="stylesheet" href="theme.css">      <!-- repository root -->
```

Its own `<style>` block carries only what is true of that page alone — its layout, its measure, its
one-off components. Three things a page must never do, each of which `verify.py` `L0.12` fails:

1. **Declare a token.** A page with its own `--ground` is not styled by the system; it resembles the
   system until one of the two is edited.
2. **Load a font.** `theme.css` imports Inter for non-Apple platforms. A second copy is a second
   decision.
3. **Restate a rule that already lives in `theme.css`.** If a button needs to look different, the
   system is missing a variant — add it to `theme.css`, where every page gets it.

Changing the look of everything is therefore one edit to one file. The documentation digest covers
`theme.css`, so a theme change makes the committed build stale and CI asks for a rebuild.

## Related

- [21 — Interface specification](21-interface-specification.md) — the surfaces this styles
- [24 — Work registry](24-work-registry.md) — `UI-01` onward
