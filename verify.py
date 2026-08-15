#!/usr/bin/env python3
"""Documentation and model verifier.

Six levels are specified in docs/31-verification.md. L0, L1 and L2 run here; L3
and L4 belong to Foundry and run once code exists. L5 verifies the checks
themselves: every check carries a known-bad fixture, and a check that passes its
own broken input is reported as dead.

    python3 verify.py
    python3 verify.py --self-test
    python3 verify.py --verbose

Check IDs here and in docs/31-verification.md must correspond exactly; L2.16
enforces that in both directions. No dependencies.
"""

import argparse
import hashlib
import re
import sys
from pathlib import Path
from xml.etree import ElementTree

ROOT = Path(__file__).parent
DOCS = ROOT / "docs"
PROTO = ROOT / "prototypes"
HTML = ROOT / "index.html"       # the whole documentation, one page
HUB = ROOT / "start.html"        # one card per document
PAGES = ROOT / "pages"
SRC = ROOT / "src"
README = ROOT / "README.md"

RESET, BOLD, RED, GREEN, DIM = "\033[0m", "\033[1m", "\033[31m", "\033[32m", "\033[2m"

SEPARATOR = re.compile(r"^\s*\|(?:\s*:?-+:?\s*\|)+\s*$")
STATUSES = {"Done", "Ready", "Blocked", "Planned", "Parked", "New"}
LEVEL_NAMES = ["structure", "document consistency", "cross-model consistency",
               "code against specification"]


# ── corpus ───────────────────────────────────────────────────────────────────


def table_rows(text):
    """Every table data row in `text`, as lists of cells."""
    out, lines = [], text.split("\n")
    for i, line in enumerate(lines):
        if not SEPARATOR.match(line):
            continue
        j = i + 1
        while j < len(lines) and lines[j].strip().startswith("|"):
            out.append([c.strip() for c in lines[j].strip().strip("|").split("|")])
            j += 1
    return out


def section(text, heading_prefix):
    """The body of the first `## ` section whose title starts with `heading_prefix`."""
    for part in re.split(r"^## ", text, flags=re.M):
        if part.startswith(heading_prefix):
            return part
    return ""


class Corpus:
    """Everything the checks read. Rebuilt per fixture, so breaking one is cheap."""

    def __init__(self):
        self.docs = {p.name: p.read_text(encoding="utf-8") for p in sorted(DOCS.glob("*.md"))}
        self.readme = README.read_text(encoding="utf-8") if README.exists() else ""
        self.html = HTML.read_text(encoding="utf-8") if HTML.exists() else ""
        self.proto = {p.name: p.read_text(encoding="utf-8") for p in sorted(PROTO.glob("*.html"))}
        self.diagrams = {p.name: p.read_text(encoding="utf-8")
                         for p in sorted((DOCS / "diagrams").glob("*.svg"))}
        self.sol = {str(p.relative_to(ROOT)): p.read_text(encoding="utf-8")
                    for p in sorted(SRC.rglob("*.sol"))}
        self.solidity = "\n".join(self.sol.values())
        self.hub = HUB.read_text(encoding="utf-8") if HUB.exists() else ""
        self.pages = {p.name: p.read_text(encoding="utf-8") for p in sorted(PAGES.glob("*.html"))}
        # Every built surface, for the checks that must hold on all of them.
        self.built = {"index.html": self.html, "start.html": self.hub}
        self.built.update({f"pages/{n}": v for n, v in self.pages.items()})
        self.html_exists = HTML.exists() and HUB.exists()
        # Content, not timestamps: a fresh git checkout gives every file the
        # same mtime, so an mtime comparison would be meaningless in CI.
        h = hashlib.sha256()
        for p in sorted(DOCS.glob("*.md")) + [ROOT / "build-docs.py", ROOT / "theme.css"]:
            h.update(p.name.encode())
            h.update(p.read_bytes())
        self.source_digest = h.hexdigest()
        m = re.search(r"<!-- source-digest: ([0-9a-f]{64}) -->", self.html)
        self.built_digest = m.group(1) if m else None

    def d(self, prefix):
        """One document by its number prefix, e.g. d('07')."""
        for n, t in self.docs.items():
            if n.startswith(prefix + "-"):
                return t
        return ""

    def numbered(self):
        return {n: t for n, t in self.docs.items() if re.match(r"^\d{2}-", n)}

    def first_col(self, text, pattern):
        """First-column values in `text` matching `pattern`, markup stripped."""
        out = []
        for r in table_rows(text):
            v = re.sub(r"[`*]", "", r[0]).strip()
            if re.match(pattern, v):
                out.append(v)
        return out

    def registry_ids(self):
        return self.first_col(self.d("24"), r"^[A-Z]{2}-\d{2}$")


# ── check registry ───────────────────────────────────────────────────────────

CHECKS = []


def check(cid, level, desc):
    def wrap(fn):
        CHECKS.append({"id": cid, "level": level, "desc": desc, "fn": fn, "break": None})
        return fn

    return wrap


def breaks(cid):
    """Attach the known-bad fixture that must make check `cid` fail."""

    def wrap(fn):
        for c in CHECKS:
            if c["id"] == cid:
                c["break"] = fn
        return fn

    return wrap


# ── L0 · structure ───────────────────────────────────────────────────────────


@check("L0.1", 0, "Every docs/*.md appears in the README index")
def _(c):
    return [f"{n} missing from the README index" for n in c.numbered() if f"docs/{n}" not in c.readme]


@breaks("L0.1")
def _(c):
    c.docs["99-orphan.md"] = "# 99 — Orphan\n\n## Related\n\n- [01](01-overview.md)\n"
    return c


@check("L0.2", 0, "Every document in the index exists on disk")
def _(c):
    linked = set(re.findall(r"\(docs/([\w.-]+\.md)\)", c.readme))
    return [f"README links {n}, which does not exist" for n in sorted(linked) if n not in c.docs]


@breaks("L0.2")
def _(c):
    c.readme += "\n| 99 | [Ghost](docs/99-ghost.md) |\n"
    return c


@check("L0.3", 0, "Document numbers are contiguous, with no gaps or duplicates")
def _(c):
    nums = sorted(int(n[:2]) for n in c.numbered())
    out = [f"duplicate document number {n:02d}" for n in sorted(set(nums)) if nums.count(n) > 1]
    out += [f"gap in numbering between {a:02d} and {b:02d}" for a, b in zip(nums, nums[1:]) if b != a + 1]
    return out


@breaks("L0.3")
def _(c):
    c.docs["77-gap.md"] = "# 77 — Gap\n"
    return c


@check("L0.4", 0, "Every internal link resolves to a real file")
def _(c):
    out = []
    for name, text in c.docs.items():
        for target in re.findall(r"\]\((?:\.\./)?(?:docs/)?([\w.-]+\.md)(?:#[\w-]+)?\)", text):
            if target not in c.docs and not (ROOT / target).exists():
                out.append(f"{name} links {target}, which does not exist")
    return out


@breaks("L0.4")
def _(c):
    c.docs["01-overview.md"] += "\n\nSee [nowhere](99-nowhere.md).\n"
    return c


@check("L0.5", 0, "The built HTML has no broken in-page anchors")
def _(c):
    if not c.html_exists:
        return ["index.html has not been built"]
    out = []
    for name, page in c.built.items():
        ids = set(re.findall(r'id="([\w-]+)"', page))
        for a in sorted(set(re.findall(r'href="#([\w-]+)"', page)) - ids):
            out.append(f"{name}: anchor #{a} has no target")
    return out


@breaks("L0.5")
def _(c):
    c.built["index.html"] += '<a href="#sec-does-not-exist">x</a>'
    return c


@check("L0.6", 0, "The built HTML is not stale relative to the sources")
def _(c):
    if not c.html_exists:
        return ["index.html has not been built"]
    if c.built_digest is None:
        return ["the built HTML carries no source digest — rebuild with build-docs.py"]
    if c.built_digest != c.source_digest:
        return ["the sources have changed since the HTML was built — run build-docs.py"]
    return []


@breaks("L0.6")
def _(c):
    c.built_digest = "0" * 64
    return c


@check("L0.7", 0, "No raw Markdown leaks into the HTML")
def _(c):
    # Code spans hold deliberate literal examples — including this check's own
    # description in doc 31, which contains `![` and `](`. Scanning them would
    # make the check fire on its own documentation.
    out = []
    for name, page in c.built.items():
        prose = re.sub(r"<code>.*?</code>", "", page, flags=re.S)
        if "&lt;div" in prose or "&lt;table" in prose:
            out.append(f"{name}: escaped raw HTML block tags appear as visible text")
        if re.search(r"!\[[^\]]*\]\(", prose):
            out.append(f"{name}: unrendered image syntax")
        if re.search(r"[^!]\]\([^)]*\.md\)", prose):
            out.append(f"{name}: unrendered Markdown link")
    return out


@breaks("L0.7")
def _(c):
    c.built["index.html"] += "&lt;div align=&quot;center&quot;&gt;"
    return c


@check("L0.8", 0, "Every HTML tag balances")
def _(c):
    out = []
    for tag in ("h2", "h3", "h4", "table", "pre", "ul", "ol", "li", "td", "th", "section", "code"):
        for name, page in c.built.items():
            opened, closed = len(re.findall(rf"<{tag}\b", page)), page.count(f"</{tag}>")
            if opened != closed:
                out.append(f"{name}: <{tag}> opened {opened} times, closed {closed}")
    return out


@breaks("L0.8")
def _(c):
    c.built["index.html"] += "<table><tr><td>unclosed"
    return c


@check("L0.9", 0, "Every page is reachable from every other — no dead ends")
def _(c):
    if not c.proto:
        return ["no prototype pages found"]
    out = []
    for name, text in c.proto.items():
        if 'href="../index.html"' not in text:
            out.append(f"prototypes/{name} does not link back to the documentation")
        missing = [s for s in c.proto if s != name and f'href="{s}"' not in text]
        if missing:
            out.append(f"prototypes/{name} does not link to {', '.join(sorted(missing))}")
    for name in c.proto:
        if f'prototypes/{name}"' not in c.html and name != "index.html":
            out.append(f"the documentation does not link prototypes/{name}")
    if 'href="prototypes/"' not in c.html:
        out.append("the documentation does not link the prototype gallery")
    return out


@breaks("L0.9")
def _(c):
    c.proto["verifier.html"] = re.sub(r'<nav class="sitenav".*?</nav>', "",
                                      c.proto["verifier.html"], flags=re.S)
    return c


@check("L0.13", 0, "Every document has a page, and every surface links the others")
def _(c):
    if not c.pages:
        return ["no per-document pages were built"]
    expected = {n[:-3] + ".html" for n in c.numbered()} | {"author.html"}
    built = set(c.pages)
    out = [f"{n} has no page" for n in sorted(expected - built)]
    out += [f"pages/{n} corresponds to no document" for n in sorted(built - expected)]
    for name, page in c.pages.items():
        if f'href="pages/{name}"' not in c.hub:
            out.append(f"start.html does not link pages/{name}")
        if 'href="../index.html"' not in page:
            out.append(f"pages/{name} does not link back to the complete documentation")
        if 'class="pnav"' not in page:
            out.append(f"pages/{name} has no adjacent-document navigation")
    if 'href="index.html"' not in c.hub:
        out.append("start.html does not link the complete documentation")
    if 'href="start.html"' not in c.html:
        out.append("the complete documentation does not link the per-document index")
    return out


@breaks("L0.13")
def _(c):
    c.pages.pop(next(iter(sorted(c.pages))))
    return c


def _page_css(text):
    """Every rule a surface declares for itself."""
    return "".join(re.findall(r"<style>(.*?)</style>", text, re.S))


@check("L0.14", 0, "No surface invents a colour, a face, a radius or a shadow")
def _(c):
    """Consistency, enforced rather than asserted.

    Spacing is a page's own business; colour, type, shape and depth are the
    system's. A literal here is how two surfaces start drifting apart.
    """
    theme = (ROOT / "theme.css").read_text(encoding="utf-8")
    palette = {h.upper() for h in re.findall(r"#[0-9A-Fa-f]{6}", theme)}
    build = ROOT / "build-docs.py"
    styles = {n: _page_css(t) for n, t in c.proto.items()}
    if build.exists():
        m = re.search(r'STYLE = """(.*?)"""', build.read_text(encoding="utf-8"), re.S)
        styles["build-docs.py"] = m.group(1) if m else ""

    out = []
    for name, css in styles.items():
        for h in sorted({x.upper() for x in re.findall(r"#[0-9A-Fa-f]{3,6}", css)}):
            if h not in palette:
                out.append(f"{name} paints {h}, which is not a token")
        for f in re.findall(r"font-family:\s*([^;}]+)", css):
            if "var(--" not in f:
                out.append(f"{name} declares its own font stack")
        for r in re.findall(r"border-radius:\s*([^;}]+)", css):
            if "var(--" not in r and r.strip() not in ("50%", "0", "inherit"):
                out.append(f"{name} sets border-radius:{r.strip()} instead of a shape token")
        for b in re.findall(r"box-shadow:\s*([^;}]+)", css):
            if "var(--" not in b and b.strip() != "none":
                out.append(f"{name} sets its own box-shadow")
    return sorted(set(out))


@breaks("L0.14")
def _(c):
    c.proto["verifier.html"] = c.proto["verifier.html"].replace(
        "<style>", "<style>\n.drift{color:#BADA55;border-radius:7px}", 1)
    return c


@check("L0.10", 0, "Every page declares its character set and viewport")
def _(c):
    out = []
    for name, text in list(c.proto.items()) + [("index.html", c.html)]:
        head = text[:600]
        if 'charset="utf-8"' not in head.lower():
            out.append(f"{name} declares no character set — em dashes render as mojibake")
        if 'name="viewport"' not in head:
            out.append(f"{name} declares no viewport — it will not scale on a phone")
    return out


@breaks("L0.10")
def _(c):
    c.proto["verifier.html"] = c.proto["verifier.html"].replace('<meta charset="utf-8">', "", 1)
    return c


@check("L0.11", 0, "Every diagram resolves, scales, and is self-contained")
def _(c):
    referenced = set()
    for text in c.docs.values():
        referenced |= set(re.findall(r"!\[[^\]]*\]\((diagrams/[\w.-]+\.svg)\)", text))
    if not c.diagrams:
        return ["no diagrams found"]
    out = [f"{r} is referenced but does not exist" for r in sorted(referenced)
           if r.split("/")[-1] not in c.diagrams]
    out += [f"diagrams/{n} exists but no document shows it" for n in sorted(c.diagrams)
            if f"diagrams/{n}" not in referenced]
    for n, svg in c.diagrams.items():
        # Well-formedness catches duplicate attributes and unclosed tags, which a
        # browser silently tolerates or silently drops.
        try:
            ElementTree.fromstring(svg)
        except ElementTree.ParseError as e:
            out.append(f"diagrams/{n} is not well-formed XML: {e}")
            continue
        if "viewBox" not in svg:
            out.append(f"diagrams/{n} has no viewBox and cannot scale to the column")
        # A scoped `text{fill:…}` rule overrides a fill="" attribute, so inverted
        # text set inline silently disappears. Colour variants must be classes.
        if re.search(r"<text[^>]*\sfill=", svg):
            out.append(f"diagrams/{n} sets fill on a <text> element; the stylesheet overrides it")
        if re.search(r'(?:href|src)="https?://', svg):
            out.append(f"diagrams/{n} references an external resource")
        if 'class="hdt"' not in svg or 'class="ico"' not in svg:
            out.append(f"diagrams/{n} has no header icon or title")
        elif HEADER not in svg:
            out.append(f"diagrams/{n} draws its header off the common geometry")
        out += _overflow(n, svg)
        off = _off_palette(svg)
        if off:
            out.append(f"diagrams/{n} uses colours outside the design tokens: {', '.join(off)}")
    return out


# The header every diagram opens with. Identical to the pixel across all of
# them, so a set of sixteen reads as one set rather than sixteen drawings.
HEADER = ('<rect x="24" y="16" width="56" height="56" rx="16" fill="#22D3EE" fill-opacity="0.16" stroke="#A5E9F4"/>'
          '<g class="ico" transform="translate(36,28) scale(1.3333)">')


def _off_palette(svg):
    """Colour literals that are not design tokens.

    A diagram drawn in a near-but-not-equal grey reads as an off-brand tint
    against the page it sits in, and nothing else would catch it.
    """
    sources = [ROOT / "build-docs.py", ROOT / "theme.css"]
    tokens = {c.upper() for s in sources if s.exists()
              for c in re.findall(r"#[0-9A-Fa-f]{6}", s.read_text(encoding="utf-8"))}
    tokens.add("#FFFFFF")
    used = {c.upper() for c in re.findall(r"#[0-9A-Fa-f]{6}", svg)}
    return sorted(used - tokens)


# Advance widths as a fraction of font size, calibrated against rendered output.
# SVG does not wrap text, so a caption edited to be longer runs off the canvas
# silently — nothing errors, the words are simply not there.
ADVANCE = {"mono": 0.63, "caps": 0.62, "sans": 0.46}


def _overflow(name, svg):
    m = re.search(r'viewBox="0 0 ([\d.]+)', svg)
    if not m:
        return []
    width = float(m.group(1))
    styles = dict(re.findall(r"\.[\w-]+ \.([\w-]+)\{([^}]*)\}", svg))
    out = []
    for t in re.finditer(r'<text class="([^"]*)"[^>]*x="([\d.]+)"[^>]*>([^<]*)</text>', svg):
        cls, x, txt = t.group(1), float(t.group(2)), t.group(3)
        style = styles.get(cls.split()[0], "")
        size = re.search(r"font-size:([\d.]+)px", style)
        size = float(size.group(1)) if size else 13.0
        k = ADVANCE["mono"] if "mono" in style else \
            ADVANCE["caps"] if "letter-spacing" in style else ADVANCE["sans"]
        if x + len(txt) * size * k > width - 6:
            out.append(f'diagrams/{name}: "{txt[:44]}…" runs past the canvas edge')
    return out


@breaks("L0.11")
def _(c):
    c.diagrams["three-planes.svg"] = c.diagrams["three-planes.svg"].replace(
        '<text class="nm i-nm"', '<text class="nm" fill="#FFFFFF"', 1)
    return c


# Tokens a page must inherit rather than declare. A page that sets its own is
# not styled by the design system; it merely resembles it until one changes.
OWNED_TOKENS = ("--ground:", "--ink:", "--accent:", "--spot:", "--r-pill:", "--sh-card:")


@check("L0.12", 0, "Every page inherits the design system from theme.css")
def _(c):
    theme = ROOT / "theme.css"
    if not theme.exists():
        return ["theme.css is missing — nothing declares the design system"]
    css = theme.read_text(encoding="utf-8")
    missing = [t for t in OWNED_TOKENS if t not in css]
    if missing:
        return [f"theme.css declares no {', '.join(missing)}"]

    out = []
    for name, text in c.proto.items():
        if 'href="../theme.css"' not in text:
            out.append(f"prototypes/{name} does not link ../theme.css")
        own = [t for t in OWNED_TOKENS if t in text]
        if own:
            out.append(f"prototypes/{name} declares its own {', '.join(own)} instead of inheriting")
        if "fonts.googleapis.com" in text:
            out.append(f"prototypes/{name} loads its own web font; theme.css imports it")
    # The built page is one artefact, so it inlines the file rather than linking it.
    if c.html_exists and "--spot:#22D3EE" not in c.html:
        out.append("index.html does not carry the design tokens")
    return out


@breaks("L0.12")
def _(c):
    c.proto["verifier.html"] = c.proto["verifier.html"].replace(
        '<link rel="stylesheet" href="../theme.css">', "", 1)
    return c


# ── L1 · document consistency ────────────────────────────────────────────────


@check("L1.1", 1, "Every table has a header separator and a uniform column count")
def _(c):
    out = []
    for name, text in c.docs.items():
        lines = text.split("\n")
        for i, line in enumerate(lines):
            if not SEPARATOR.match(line) or i == 0:
                continue
            width = len(lines[i - 1].strip().strip("|").split("|"))
            j = i + 1
            while j < len(lines) and lines[j].strip().startswith("|"):
                got = len(lines[j].strip().strip("|").split("|"))
                if got != width:
                    out.append(f"{name} line {j+1}: {got} columns, header has {width}")
                j += 1
    return out


@breaks("L1.1")
def _(c):
    c.docs["01-overview.md"] += "\n\n| a | b |\n|---|---|\n| 1 | 2 | 3 |\n"
    return c


@check("L1.2", 1, "Every fenced code block is closed")
def _(c):
    return [f"{n} has an unclosed code fence" for n, t in c.docs.items() if t.count("```") % 2]


@breaks("L1.2")
def _(c):
    c.docs["01-overview.md"] += "\n\n```solidity\nunclosed\n"
    return c


@check("L1.3", 1, "Every document ends with a Related section linking at least one other")
def _(c):
    out = []
    for n, t in c.docs.items():
        parts = re.split(r"^## Related", t, flags=re.M)
        if len(parts) < 2:
            out.append(f"{n} has no Related section")
        elif not re.search(r"\]\((?:\.\./)?(?:docs/)?[\w.-]+\.md", parts[-1]):
            out.append(f"{n} has a Related section that links nothing")
    return out


@breaks("L1.3")
def _(c):
    c.docs["99-lonely.md"] = "# 99 — Lonely\n\nNo Related section here.\n"
    c.readme += "\n| 99 | [Lonely](docs/99-lonely.md) |\n"
    return c


@check("L1.4", 1, "No document references a registry ID that does not exist in 24")
def _(c):
    known = set(c.registry_ids())
    if not known:
        return ["the work registry has no parsable IDs"]
    out = []
    for name, text in c.docs.items():
        if name.startswith("24-"):
            continue
        for rid in sorted(set(re.findall(r"`([A-Z]{2}-\d{2})`", text))):
            if rid not in known:
                out.append(f"{name} references {rid}, which is not in the registry")
    return out


@breaks("L1.4")
def _(c):
    c.docs["01-overview.md"] += "\n\nSee `ZZ-99`.\n"
    return c


@check("L1.5", 1, "Registry IDs are unique")
def _(c):
    ids = c.registry_ids()
    return [f"registry ID {i} appears {ids.count(i)} times" for i in sorted(set(ids)) if ids.count(i) > 1]


@breaks("L1.5")
def _(c):
    c.docs["24-work-registry.md"] += "\n| ID | Item | Status |\n|---|---|---|\n| IF-01 | Duplicate | Ready |\n"
    return c


@check("L1.6", 1, "Every registry item has a status from the declared vocabulary")
def _(c):
    out = []
    for r in table_rows(c.d("24")):
        if not re.match(r"^[A-Z]{2}-\d{2}$", re.sub(r"[`*]", "", r[0]).strip()):
            continue
        cells = [re.sub(r"[`*]", "", x).strip() for x in r[1:]]
        if not any(x in STATUSES for x in cells):
            out.append(f"{r[0]} has no status from {sorted(STATUSES)}")
    return out


@breaks("L1.6")
def _(c):
    c.docs["24-work-registry.md"] += "\n| ID | Item | Status |\n|---|---|---|\n| IF-99 | Invented | Nearly done |\n"
    return c


@check("L1.7", 1, "Artifact register totals match the row counts they claim")
def _(c):
    inv = c.d("27")
    m = re.search(r"\*\*Totals:(.+?)=\s*(\d+)\s*\n?artifacts", inv, re.S)
    if not m:
        return ["the artifact register states no total"]
    claimed, actual = int(m.group(2)), len(c.first_col(inv, r"^[A-F]-\d{2}$"))
    per = dict((w, int(n)) for n, w in re.findall(
        r"(\d+)\s+(specification|code|test|interface|operational|governance)", m.group(1)))
    out = []
    if claimed != actual:
        out.append(f"the register claims {claimed} artifacts; {actual} rows exist")
    if sum(per.values()) != claimed:
        out.append(f"per-register figures sum to {sum(per.values())}, but the total claims {claimed}")
    for letter, word in zip("ABCDEF", ["specification", "code", "test", "interface", "operational", "governance"]):
        n = len(c.first_col(inv, rf"^{letter}-\d{{2}}$"))
        if word in per and per[word] != n:
            out.append(f"register {letter} claims {per[word]} {word} artifacts, has {n}")
    return out


@breaks("L1.7")
def _(c):
    c.docs["27-model-inventory.md"] = c.docs["27-model-inventory.md"].replace(
        "| F-06 |", "| F-07 | Uncounted | Files | Done | Author | none |\n| F-06 |", 1)
    return c


# ── L2 · cross-model consistency ─────────────────────────────────────────────


def _contracts_of(c):
    """Doc 03 split into (documented in 07, documented in 10)."""
    d3 = c.d("03")
    rules = set(c.first_col(section(d3, "Rule contracts"), r"^[A-Z]\w+$"))
    api = set()
    for head in ("Top-level contracts", "Token facets", "Identity adapters",
                 "Factory facets", "Offering registry facets"):
        api |= set(c.first_col(section(d3, head), r"^[A-Z]\w+$"))
    return api - rules, rules


@check("L2.1", 2, "Every contract and facet in 03 appears in 07; every rule appears in 10")
def _(c):
    api, rules = _contracts_of(c)
    if not api or not rules:
        return ["doc 03 declares no contracts — its section headings have moved"]
    d7, d10 = c.d("07"), c.d("10")
    out = [f"{k} is in doc 03 but absent from the function reference" for k in sorted(api) if k not in d7]
    out += [f"rule {k} is in doc 03 but absent from doc 10" for k in sorted(rules) if k not in d10]
    return out


@breaks("L2.1")
def _(c):
    c.docs["03-contracts.md"] = c.docs["03-contracts.md"].replace(
        "| `FeeFacet` |", "| `PhantomFacet` | Nothing |\n| `FeeFacet` |", 1)
    return c


@check("L2.2", 2, "Every storage struct in 04 is owned by a contract in 03")
def _(c):
    structs = set(re.findall(r"\b(\w+Storage)\b", c.d("04")))
    if not structs:
        return ["doc 04 declares no storage structs"]
    d3 = c.d("03")
    return [f"{s} has no owning contract in doc 03" for s in sorted(structs) if s not in d3]


@breaks("L2.2")
def _(c):
    c.docs["04-storage.md"] += "\n\n`OrphanStorage` is owned by nothing.\n"
    return c


@check("L2.3", 2, "Every role in 05 is used as an access level in 07")
def _(c):
    roles = {r for r in re.findall(r"\b([A-Z][A-Z_]{5,})\b", c.d("05"))
             if r.endswith(("ADMIN", "OPERATOR", "OFFICER", "ATTESTOR"))}
    if not roles:
        return ["doc 05 declares no roles"]
    d7 = c.d("07")
    return [f"role {r} is defined but never required in the function reference" for r in sorted(roles) if r not in d7]


@breaks("L2.3")
def _(c):
    c.docs["05-roles.md"] += "\n\n`PHANTOM_ADMIN` guards nothing.\n"
    return c


@check("L2.4", 2, "Every access level in 07 is a role defined in 05")
def _(c):
    used = {r for r in re.findall(r"\b([A-Z][A-Z_]{5,})\b", c.d("07"))
            if r.endswith(("ADMIN", "OPERATOR", "OFFICER", "ATTESTOR"))}
    if not used:
        return ["doc 07 names no access levels"]
    d5 = c.d("05")
    return [f"doc 07 requires {r}, which doc 05 does not define" for r in sorted(used) if r not in d5]


@breaks("L2.4")
def _(c):
    c.docs["07-functions.md"] += "\n\n| `x()` | does y | INVENTED_OPERATOR | because |\n"
    return c


@check("L2.5", 2, "Every entity in 29 names an owning contract or store")
def _(c):
    rows = [r for r in table_rows(c.d("29")) if re.match(r"^E-\d{2}$", r[0])]
    if not rows:
        return ["doc 29 declares no entities"]
    return [f"{r[0]} names no owner" for r in rows if len(r) < 3 or not r[2].strip()]


@breaks("L2.5")
def _(c):
    c.docs["29-data-model.md"] = c.docs["29-data-model.md"].replace(
        "| E-01 | **Token** | `uRWAToken` |", "| E-01 | **Token** |  |", 1)
    return c


@check("L2.6", 2, "Every entity has at least one stated invariant")
def _(c):
    d29 = c.d("29")
    declared = set(c.first_col(d29, r"^E-\d{2}$"))
    if not declared:
        return ["doc 29 declares no entities"]
    detail = section(d29, "Entity detail")
    detailed = set()
    for head in re.findall(r"^### (.+)$", detail, re.M):
        detailed |= set(re.findall(r"E-\d{2}", head))
    for a, b in re.findall(r"(E-\d{2})…(E-\d{2})", detail):
        detailed |= {f"E-{n:02d}" for n in range(int(a[2:]), int(b[2:]) + 1)}
    return [f"entity {e} has no stated invariant" for e in sorted(declared - detailed)]


@breaks("L2.6")
def _(c):
    c.docs["29-data-model.md"] = c.docs["29-data-model.md"].replace(
        "| E-23 |", "| E-99 | **Ghost** | nowhere | none | never |\n| E-23 |", 1)
    return c


@check("L2.7", 2, "Every actor in 28 has at least one job")
def _(c):
    d28 = c.d("28")
    actors = set(c.first_col(d28, r"^P-\d{2}$"))
    if not actors:
        return ["doc 28 declares no actors"]
    jobs = d28.split("## Jobs", 1)[-1].split("## Value flows", 1)[0]
    return [f"actor {a} has no job" for a in sorted(actors - set(re.findall(r"\bP-\d{2}\b", jobs)))]


@breaks("L2.7")
def _(c):
    c.docs["28-product-model.md"] = c.docs["28-product-model.md"].replace(
        "\n## Jobs", "| P-99 | **Decorative** | nobody | nothing | nothing |\n\n## Jobs", 1)
    return c


@check("L2.8", 2, "Every job names a surface and a contract path")
def _(c):
    rows = [r for r in table_rows(c.d("28")) if re.match(r"^J-\d{2}$", r[0])]
    if not rows:
        return ["doc 28 declares no jobs"]
    out = []
    for r in rows:
        if len(r) < 6:
            out.append(f"{r[0]} has {len(r)} columns; a job needs an actor, a surface, a path and a done-when")
        elif not r[3].strip() or not r[4].strip():
            out.append(f"{r[0]} is missing a surface or a contract path")
    return out


@breaks("L2.8")
def _(c):
    c.docs["28-product-model.md"] += (
        "\n\n| ID | Job | Actor | Surface | Path | Done when |\n|---|---|---|---|---|---|\n"
        "| J-99 | Vague | P-01 |  |  | never |\n")
    return c


@check("L2.9", 2, "Every surface in 28 appears in 21")
def _(c):
    surfaces = [re.sub(r"[`*]", "", r[0]).strip()
                for r in table_rows(section(c.d("28"), "Surfaces")) if r and r[0].strip()]
    if not surfaces:
        return ["doc 28 declares no surfaces"]
    d21 = c.d("21").lower()
    return [f"surface “{s}” is not specified in doc 21" for s in surfaces if s.lower() not in d21]


@breaks("L2.9")
def _(c):
    # Anchored on the surfaces table header, not on a cell value: "Public verifier"
    # also appears as a cell in the jobs tables, where L2.9 does not read.
    header = "| Surface | Actors | Auth | Public | Jobs |\n|---|---|---|---|---|\n"
    c.docs["28-product-model.md"] = c.docs["28-product-model.md"].replace(
        header, header + "| Holographic console | P-01 | Wallet | ❌ | J-01 |\n", 1)
    return c


@check("L2.10", 2, "Every call named in 30 exists in 07")
def _(c):
    callees = r"token|passport|factory|Factory|AtomicDvP|AgentAuthority|OfferingRegistry|Treasury|PolicySet|IIdentityRegistry|paymentToken"
    calls = set(re.findall(rf"\b(?:{callees})\.(\w+)", c.d("30")))
    if not calls:
        return ["doc 30 names no calls"]
    d7 = c.d("07")
    return [f"doc 30 calls {fn}, which the function reference does not document"
            for fn in sorted(calls) if fn not in d7]


@breaks("L2.10")
def _(c):
    c.docs["30-interaction-model.md"] += "\n```\ntoken.teleport(to, amount)\n```\n"
    return c


CLAIM_KEY = r"`((?:urwa|us|eu|aml|iso17442)\.[\w.]+)`"


@check("L2.11", 2, "Every rule in 10 reads a claim key declared in 09")
def _(c):
    keys = set(re.findall(CLAIM_KEY, c.d("09")))
    if not keys:
        return ["doc 09 declares no claim keys"]
    unknown = set(re.findall(CLAIM_KEY, c.d("10"))) - keys
    return [f"doc 10 reads claim key {k}, which doc 09 does not declare" for k in sorted(unknown)]


@breaks("L2.11")
def _(c):
    c.docs["10-rules.md"] += "\n| GhostRule | `urwa.not.declared` | invented |\n"
    return c


@check("L2.12", 2, "Every claim key in 09 is read by a rule, or is marked reporting-only")
def _(c):
    d9 = c.d("09")
    keys = set(re.findall(CLAIM_KEY, d9))
    if not keys:
        return ["doc 09 declares no claim keys"]
    read = set(re.findall(CLAIM_KEY, c.d("10"))) | set(re.findall(CLAIM_KEY, c.d("03")))
    exempt = {re.sub(r"`", "", r[0]) for r in table_rows(d9)
              if len(r) > 2 and "reporting only" in r[2].lower()}
    return [f"claim key {k} is declared but nothing reads it, and it is not marked reporting-only"
            for k in sorted(keys - read - exempt)]


@breaks("L2.12")
def _(c):
    c.docs["09-identity-did.md"] += "\n| `urwa.unused.key` | bool | Holder caps |\n"
    return c


@check("L2.13", 2, "Every state in 06 is entered by a named function and left by one")
def _(c):
    rows = [r for r in table_rows(c.d("06")) if len(r) >= 3 and re.match(r"^[`*]*[A-Z]\w+", r[0])]
    if not rows:
        return ["doc 06 declares no states"]
    return [f"state {r[0]} has no entry or no exit" for r in rows if not r[1].strip() or not r[2].strip()]


@breaks("L2.13")
def _(c):
    c.docs["06-states.md"] += "\n\n| State | Entered by | Left by |\n|---|---|---|\n| Trapped |  |  |\n"
    return c


@check("L2.14", 2, "Every artifact in 27 names an owner and a check")
def _(c):
    rows = [r for r in table_rows(c.d("27")) if re.match(r"^[A-F]-\d{2}$", r[0])]
    if not rows:
        return ["doc 27 declares no artifacts"]
    out = []
    for r in rows:
        if len(r) < 6:
            out.append(f"{r[0]} has {len(r)} columns; an artifact needs an owner and a check")
        elif not r[4].strip() or not r[5].strip():
            out.append(f"{r[0]} names no owner or no check")
    return out


@breaks("L2.14")
def _(c):
    c.docs["27-model-inventory.md"] = c.docs["27-model-inventory.md"].replace(
        "| A-01 |", "| A-99 | Unowned | Document | Done |  |  |\n| A-01 |", 1)
    return c


@check("L2.15", 2, "Every glossary term in 18 is used somewhere else")
def _(c):
    d18 = c.d("18")
    # Only the definitions. The role-name and interface-id sections are lookup
    # tables, not vocabulary, and are covered by L2.3 and the standards matrix.
    defs = re.split(r"^## Role names", d18, flags=re.M)[0]
    terms = [t for t in (re.sub(r"[`*]", "", r[0]).strip() for r in table_rows(defs)) if len(t) > 3]
    if not terms:
        return ["doc 18 declares no terms"]
    rest = "\n".join(t for n, t in c.docs.items() if not n.startswith("18-")).lower()
    out = []
    for t in terms:
        # A term counts as used under inflection: "fail closed" ↔ "fails closed",
        # "immutable selector" ↔ "immutable selectors".
        stem = re.sub(r"(es|s)$", "", t.lower())
        pattern = r"\w*\s+".join(re.escape(w) for w in stem.split())
        if not re.search(pattern, rest):
            out.append(f"glossary term “{t}” is used nowhere else")
    return out


@breaks("L2.15")
def _(c):
    c.docs["18-glossary.md"] = c.docs["18-glossary.md"].replace(
        "\n## Role names", "| Hyperconvergent tranche | A term nobody uses |\n\n## Role names", 1)
    return c


@check("L2.16", 2, "Every check in 31 exists in verify.py, and the reverse")
def _(c):
    documented = set(re.findall(r"`(L[0-5]\.\d+)`", c.d("31")))
    if not documented:
        return ["doc 31 lists no checks"]
    deferred = {"L3.6", "L3.7"} | {f"L4.{i}" for i in range(1, 16)} | {f"L5.{i}" for i in range(1, 6)}
    implemented = {ch["id"] for ch in CHECKS}
    out = [f"{k} is documented but not implemented" for k in sorted(documented - implemented - deferred)]
    out += [f"{k} is implemented but not documented in doc 31" for k in sorted(implemented - documented)]
    return out


@breaks("L2.16")
def _(c):
    c.docs["31-verification.md"] += "\n| `L0.99` | A check nobody wrote |\n"
    return c



@check("L3.1", 3, "Every function in 07 exists in the interfaces")
def _(c):
    if not c.solidity:
        return ["no Solidity sources found"]
    declared = sol_functions(c.solidity)
    missing = sorted(n for n in doc_table_functions(c.d("07")) if n not in declared)
    return [f"doc 07 documents {n}(), which no interface declares" for n in missing]


@breaks("L3.1")
def _(c):
    c.solidity = c.solidity.replace("function canSend(", "function canSendX(")
    return c


@check("L3.2", 3, "Every interface function is documented in 07")
def _(c):
    if not c.solidity:
        return ["no Solidity sources found"]
    documented = doc_table_functions(c.d("07")) | doc_functions(c.d("07"))
    # The API surface is: every interface declaration (they end in `;`) plus
    # every external or public function of a contract. Block-matching by regex
    # was tried and is wrong — a non-greedy block capture runs past the end of
    # one file into the next and swallows whatever lies between.
    api = set(re.findall(r"\bfunction\s+(\w+)\s*\([^;{]*\)[^;{]*;", c.solidity, re.S))
    api |= set(
        re.findall(r"\bfunction\s+(\w+)\s*\([^;{]*?\b(?:external|public)\b[^;{]*\{", c.solidity, re.S)
    )
    # A leading underscore marks an internal helper by convention throughout
    # this codebase, and no such function is part of the documented surface.
    out = []
    for name in sorted(n for n in api if not n.startswith("_")):
        if name not in documented:
            out.append(f"{name}() is declared in Solidity but absent from the function reference")
    return out


@breaks("L3.2")
def _(c):
    # Multi-line: the check reads `interface` blocks, and the block regex needs
    # a newline before the closing brace.
    c.solidity += "\ninterface IGhost {\n    function undocumentedFunction() external;\n}\n"
    return c


@check("L3.3", 3, "Every storage struct matches 04 field for field, in order")
def _(c):
    code = sol_structs(c.solidity)
    spec = sol_structs(c.d("04"))
    if not code or not spec:
        return ["no storage structs found in the code or the specification"]
    out = []
    for name, fields in spec.items():
        if name not in code:
            out.append(f"{name} is specified in doc 04 but declared nowhere in src/")
        elif code[name] != fields:
            out.append(f"{name} fields differ from doc 04: {fields} vs {code[name]}")
    # The reverse direction covers src/storage/ only: doc 04 is about storage,
    # while calldata and memory structs are specified where they are used.
    stored = sol_structs("\n".join(v for k, v in c.sol.items() if k.startswith("src/storage/")))
    for name in sorted(set(stored) - set(spec)):
        out.append(f"{name} is stored but not specified in doc 04")
    return out


@breaks("L3.3")
def _(c):
    # `c.solidity` is what the check reads; mutating only `c.sol` would leave
    # the check inspecting the unmodified corpus.
    c.solidity = c.solidity.replace("uint256 totalSupply;", "uint256 totalSupplyRenamed;", 1)
    return c


@check("L3.4", 3, "Slot constants derive from the documented strings")
def _(c):
    code = dict(re.findall(r'(\w+)\s*=\s*keccak256\("(urwa\.storage\.[\w.]+)"\)',
                           c.sol.get("src/storage/Slots.sol", "")))
    spec = set(re.findall(r'keccak256\("(urwa\.storage\.[\w.]+)"\)', c.d("04")))
    if not code or not spec:
        return ["no slot constants found in the code or the specification"]
    used = set(code.values())
    out = [f"doc 04 documents slot {s}, which Slots.sol does not declare" for s in sorted(spec - used)]
    out += [f"Slots.sol declares {s}, which doc 04 does not document" for s in sorted(used - spec)]
    return out


@breaks("L3.4")
def _(c):
    c.sol["src/storage/Slots.sol"] = c.sol["src/storage/Slots.sol"].replace(
        "urwa.storage.core.v1", "urwa.storage.core.v2", 1)
    return c


@check("L3.5", 3, "Events and errors agree between 14 and Solidity, both ways")
def _(c):
    doc = c.d("14")
    if not c.solidity or not doc:
        return ["no Solidity sources or no event catalogue"]
    out = []
    for keyword, label in (("event", "event"), ("error", "error")):
        in_code = sol_named(c.solidity, keyword)
        in_doc = sol_named(doc, keyword)
        out += [f"{label} {n} is in doc 14 but not in Solidity" for n in sorted(in_doc - in_code)]
        out += [f"{label} {n} is in Solidity but not in doc 14" for n in sorted(in_code - in_doc)]
    return out


@breaks("L3.5")
def _(c):
    c.solidity += "\ninterface IGhostEvents { event NeverDocumented(uint256 x); }\n"
    return c


# ── L3 · code against specification ──────────────────────────────────────────
#
# These read the Solidity source rather than the compiled ABI, so `verify.py`
# stays dependency-free and runnable without a toolchain. Foundry checks the
# other direction — that what is declared here actually compiles and behaves.


def sol_functions(text):
    """Every function name declared in Solidity."""
    return set(re.findall(r"\bfunction\s+([a-zA-Z_]\w*)\s*\(", text))


def sol_named(text, keyword):
    """Every event or error name declared in Solidity."""
    return set(re.findall(rf"\b{keyword}\s+([A-Z]\w*)\s*\(", text))


def sol_structs(text):
    """Struct name → its field names, in declaration order."""
    out = {}
    for m in re.finditer(r"\bstruct\s+(\w+)\s*\{(.*?)\n\s*\}", text, re.S):
        fields = []
        for line in m.group(2).split("\n"):
            line = re.sub(r"//.*", "", line).strip().rstrip(";")
            if not line or line.startswith("/") or line.startswith("*"):
                continue
            name = line.split()[-1]
            if name.isidentifier():
                fields.append(name)
        out[m.group(1)] = fields
    return out


def doc_table_functions(text):
    """Function names from the first column of the reference tables.

    Prose mentions a great many names; the tables are the actual claim about
    what exists, so `L3.1` reads those and nothing else.
    """
    names = set()
    for row in table_rows(text):
        for m in re.finditer(r"`([A-Za-z_]\w*)\(", row[0]):
            names.add(m.group(1))
    return names


def doc_functions(text):
    """Function names the documentation claims exist."""
    names = set()
    for m in re.finditer(r"`([a-z_]\w*)\(", text):
        names.add(m.group(1))
    return names


def doc_named(text, pattern):
    return set(re.findall(pattern, text))


# ── runner ───────────────────────────────────────────────────────────────────


def run(verbose=False):
    c = Corpus()
    results = [(ch, ch["fn"](c)) for ch in CHECKS]
    failed = sum(1 for _, p in results if p)

    for level in (0, 1, 2, 3):
        rows = [(ch, p) for ch, p in results if ch["level"] == level]
        if not rows:
            continue
        print(f"\n{BOLD}L{level}{RESET}  {DIM}{LEVEL_NAMES[level]}{RESET}")
        for ch, problems in rows:
            if problems:
                print(f"  {RED}✕ {ch['id']}{RESET}  {ch['desc']}")
                for p in problems[:8]:
                    print(f"      {p}")
                if len(problems) > 8:
                    print(f"      {DIM}… and {len(problems) - 8} more{RESET}")
            elif verbose:
                print(f"  {GREEN}✓ {ch['id']}{RESET}  {DIM}{ch['desc']}{RESET}")
        if not verbose:
            print(f"  {GREEN}✓{RESET} {sum(1 for _, p in rows if not p)} of {len(rows)} passed")

    print(f"\n{BOLD}{len(results) - failed}/{len(results)} checks passed{RESET}")
    print(f"{DIM}L4 runs in Foundry · L5: verify.py --self-test{RESET}")
    return 1 if failed else 0


def self_test(verbose=False):
    """L5. A check that passes its own broken input is dead."""
    print(f"\n{BOLD}L5{RESET}  {DIM}verifying the checks themselves{RESET}\n")
    bad = set()
    c = Corpus()

    for ch in CHECKS:
        # L5.1 — every check has a known-bad fixture
        if ch["break"] is None:
            bad.add(ch["id"])
            print(f"  {RED}✕ {ch['id']}{RESET}  no known-bad fixture            {DIM}L5.1{RESET}")
            continue
        # L5.2 — the check must fail on that fixture
        found = ch["fn"](ch["break"](Corpus()))
        if not found:
            bad.add(ch["id"])
            print(f"  {RED}✕ {ch['id']}{RESET}  passed its own broken input     {DIM}L5.2 · dead check{RESET}")
            continue
        # L5.3 — a check whose input parsed to nothing can never fail honestly
        if any(re.search(r"declares no|lists no|names no|have moved|no parsable", p) for p in ch["fn"](c)):
            bad.add(ch["id"])
            print(f"  {RED}✕ {ch['id']}{RESET}  inspects an empty set           {DIM}L5.3{RESET}")
            continue
        if verbose:
            print(f"  {GREEN}✓ {ch['id']}{RESET}  {DIM}{found[0][:66]}{RESET}")

    # L5.4 — every level has at least one check
    for lv in (0, 1, 2, 3):
        if not any(ch["level"] == lv for ch in CHECKS):
            bad.add(f"L{lv}")
            print(f"  {RED}✕ L5.4{RESET}  level L{lv} has no checks")

    # L5.5 — this file and doc 31 agree; L2.16 read from the other side
    for d in next(ch for ch in CHECKS if ch["id"] == "L2.16")["fn"](c):
        bad.add("L5.5")
        print(f"  {RED}✕ L5.5{RESET}  {d}")

    n = len(CHECKS)
    if not bad:
        print(f"  {GREEN}every check is alive{RESET} — {n} checks, each fails on its own fixture")
    print(f"\n{BOLD}{n - len(bad)}/{n} checks verified{RESET}")
    return 1 if bad else 0


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Documentation and model verifier")
    ap.add_argument("--self-test", action="store_true", help="L5: verify the checks themselves")
    ap.add_argument("--verbose", "-v", action="store_true")
    a = ap.parse_args()
    sys.exit(self_test(a.verbose) if a.self_test else run(a.verbose))
