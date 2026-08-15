# 25 — Design system

One light theme, applied to the documentation site and every prototype. The canonical token file is
[`prototypes/theme.css`](../prototypes/theme.css); each surface inlines the same values so it stays
self-contained and works when opened from disk.

## The decision

**A single committed light theme, not a light-and-dark pair.**

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
| `--ground` | `#FAFAFC` | Page canvas |
| `--surface` | `#FFFFFF` | Cards, panels, inputs |
| `--sunk` | `#F4F5F9` | Inline code, hover states, quiet fills |

### Ink

| Token | Value | Use |
|---|---|---|
| `--ink` | `#0E1017` | Primary text |
| `--ink-2` | `#3A4050` | Body copy in tables and cards |
| `--muted` | `#666E80` | Supporting text |
| `--faint` | `#949BAB` | Labels, captions, metadata |

`--faint` on `--ground` is the tightest pairing in the system and clears 4.5:1. Nothing lighter is
used for text.

### Lines

| Token | Value | Use |
|---|---|---|
| `--rule` | `#EFF1F6` | Default hairline. Almost invisible, on purpose |
| `--rule-strong` | `#E2E5EE` | Input borders, emphasis |

Separation comes from space first, a hairline second, and a border only when a boundary is genuinely
structural. Depth comes from `--sh`, never from a heavy line.

### Accent

| Token | Value | Use |
|---|---|---|
| `--accent` | `#4338CA` | Links, active state, primary action |
| `--accent-2` | `#312BA0` | Hover on the primary action |
| `--accent-wash` | `#F0F1FE` | Selected rows, focus ring, quiet accent fills |
| `--accent-edge` | `#CFD2F9` | Border on accent surfaces |

**One accent, held back.** At most one accent-filled control per view; everything else is neutral. The
accent earns attention because it is rare.

### Status

| Token | Value | Meaning |
|---|---|---|
| `--ok` | `#0B7A5B` | Passed, verified, eligible |
| `--warn` | `#8A5B10` | Needs attention, irreversible, locked |
| `--crit` | `#B3261E` | Refused, failed, unverified |

Status is never encoded in colour alone. Every status carries a word, a mark, or both — required for
accessibility and for anyone reading a screenshot in greyscale.

### Shape

| Token | Value | Applied to |
|---|---|---|
| `--r` | `10px` | Inputs, small controls, nav items |
| `--r-lg` | `14px` | Cards, notes, tables, code blocks |
| `--r-pill` | `999px` | **Every button**, chips, pills, status dots, step markers |

Controls are pills. Containers are soft rectangles. Nothing in the system has a sharp corner.

### Depth

```css
--sh:    0 1px 2px rgba(14,16,23,.05), 0 1px 3px rgba(14,16,23,.03);
--sh-lg: 0 2px 4px rgba(14,16,23,.04), 0 12px 32px rgba(14,16,23,.06);
```

Two layers each: a tight contact shadow and a soft diffused one. Both carry a vertical offset — a
zero-offset halo is decoration, not depth.

### Type

| Role | Stack |
|---|---|
| `--display` | SF Pro Display → Inter → system sans |
| `--body` | SF Pro Text → Inter → system sans |
| `--mono` | SF Mono → JetBrains Mono → IBM Plex Mono → system mono |

All sans. The earlier serif display face was warm and editorial; this system is quiet and technical,
and a serif fought that. Display sizes carry tight negative tracking (`-.026em` to `-.032em`); body
text sits at `-.003em`.

Measure stays at 74 characters. Line height is 1.68 in body copy — more air than a typical interface,
because most of these surfaces are read rather than scanned.

## Rules

1. **Space before lines.** Reach for a gap before a border.
2. **One accent per view.** Every other control is neutral.
3. **Never colour alone.** Status carries a word or a mark as well.
4. **Every button is a pill.** No exceptions in this system.
5. **Focus is always visible.** A 2px accent outline at 3px offset, on every interactive element.
6. **No gradients, no glass, no glow.** Depth comes from two-layer shadows and nothing else.

## Where it is applied

| Surface | File |
|---|---|
| Documentation site | `build-docs.py` → `urwa-documentation.html` |
| Prototype index | `prototypes/index.html` |
| Deploy console | `prototypes/deploy-console.html` |
| Token console | `prototypes/token-console.html` |
| Public verifier | `prototypes/verifier.html` |
| Investor page | `prototypes/investor.html` |
| Canonical tokens | `prototypes/theme.css` |

When the production interfaces are built in Phase 5, `theme.css` is the source. The prototypes inline
it only so each file opens standalone.

## Related

- [21 — Interface specification](21-interface-specification.md) — the surfaces this styles
- [24 — Work registry](24-work-registry.md) — `UI-01` onward
