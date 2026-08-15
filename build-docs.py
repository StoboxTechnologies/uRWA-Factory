#!/usr/bin/env python3
"""Build urwa-documentation.html from README.md + docs/*.md.

No dependencies. A deliberately small Markdown subset is supported — exactly the
constructs used in this documentation set: headings, tables, fenced code, lists,
task lists, blockquotes, horizontal rules, and inline code/bold/em/links.
"""

import hashlib
import html
import re
from pathlib import Path

ROOT = Path(__file__).parent
DOCS = ROOT / "docs"
OUT = ROOT / "urwa-documentation.html"


def source_digest():
    """Digest of every input to this build.

    Stamped into the output so verify.py L0.6 can tell a stale build from a
    current one by content. File timestamps cannot do that — a fresh git
    checkout gives every file the same mtime.
    """
    h = hashlib.sha256()
    for p in sorted(DOCS.glob("*.md")) + [ROOT / "build-docs.py"]:
        h.update(p.name.encode())
        h.update(p.read_bytes())
    return h.hexdigest()

ORDER = [f"docs/{p.name}" for p in sorted(DOCS.glob("*.md"))]

# ── inline ──────────────────────────────────────────────────────────────────

CODE_TOKEN = "\x00CODE%d\x00"


def inline(text):
    """Inline formatting. Code spans are extracted first so their contents are
    never re-processed as emphasis or links."""
    spans = []

    def stash(m):
        spans.append(html.escape(m.group(1)))
        return CODE_TOKEN % (len(spans) - 1)

    text = re.sub(r"`([^`]+)`", stash, text)
    text = html.escape(text)
    text = re.sub(r"!\[([^\]]*)\]\([^)]*\)", "", text)
    text = re.sub(r"\[([^\]]+)\]\(([^)]+)\)", lambda m: link(m.group(1), m.group(2)), text)
    text = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", text)
    text = re.sub(r"(?<![\w*])\*([^*\n]+)\*(?![\w*])", r"<em>\1</em>", text)
    for i, c in enumerate(spans):
        text = text.replace(CODE_TOKEN % i, f"<code>{c}</code>")
    return text


def link(label, href):
    """Rewrite intra-repo Markdown links to in-page anchors."""
    m = re.match(r"^(?:docs/)?(\d{2})-[\w-]+\.md(#.*)?$", href)
    if m:
        return f'<a href="#sec-{m.group(1)}">{label}</a>'
    if href.startswith("#"):
        return f'<a href="{href}" data-scoped="1">{label}</a>'
    return f'<a href="{html.escape(href)}">{label}</a>'


def cells(row):
    row = row.strip()
    if row.startswith("|"):
        row = row[1:]
    if row.endswith("|"):
        row = row[:-1]
    return [c.strip() for c in row.split("|")]


def aligns(sep):
    out = []
    for c in cells(sep):
        left, right = c.startswith(":"), c.endswith(":")
        out.append("center" if left and right else "right" if right else "left")
    return out


# ── block ───────────────────────────────────────────────────────────────────


def figure(caption, rel):
    """Inline an SVG diagram as a <figure>.

    Inlined rather than linked so the built page is one self-contained file and
    the diagrams scale with the reader's text size. The same Markdown renders as
    an ordinary image on GitHub, so both surfaces show the diagram from one
    source file.
    """
    path = DOCS / rel
    if not path.exists():
        return f'<p class="missing">Diagram not found: {html.escape(rel)}</p>'
    svg = path.read_text(encoding="utf-8")
    svg = re.sub(r"<\?xml[^>]*\?>\s*", "", svg)
    svg = re.sub(r"<!--.*?-->", "", svg, flags=re.S)
    # Scale to the column; the viewBox carries the aspect ratio.
    svg = re.sub(r"<svg\b", '<svg role="img" preserveAspectRatio="xMidYMid meet"', svg, count=1)
    svg = re.sub(r'\s(?:width|height)="[\d.]+"', "", svg, count=2)
    label = inline(caption) if caption else ""
    cap = f"<figcaption>{label}</figcaption>" if label else ""
    return f'<figure class="dg">{svg}{cap}</figure>'


def render(md, sec):
    lines = md.split("\n")
    out, i, n = [], 0, len(lines)
    list_stack = []

    def close_lists():
        while list_stack:
            out.append(f"</{list_stack.pop()}>")

    while i < n:
        line = lines[i]

        # diagram — inlined, never fetched, so the page stays self-contained
        m = re.match(r"^!\[([^\]]*)\]\((diagrams/[\w.-]+\.svg)\)\s*$", line.strip())
        if m:
            close_lists()
            out.append(figure(m.group(1), m.group(2)))
            i += 1
            continue

        # fenced code
        if line.startswith("```"):
            close_lists()
            i += 1
            buf = []
            while i < n and not lines[i].startswith("```"):
                buf.append(lines[i])
                i += 1
            i += 1
            out.append("<pre>" + html.escape("\n".join(buf)) + "</pre>")
            continue

        # table
        if line.lstrip().startswith("|") and i + 1 < n and re.match(r"^\s*\|[\s:|-]+\|\s*$", lines[i + 1]):
            close_lists()
            head = cells(line)
            al = aligns(lines[i + 1])
            i += 2
            rows = []
            while i < n and lines[i].lstrip().startswith("|"):
                rows.append(cells(lines[i]))
                i += 1
            th = "".join(
                f'<th style="text-align:{al[j] if j < len(al) else "left"}">{inline(c)}</th>'
                for j, c in enumerate(head)
            )
            body = []
            for r in rows:
                td = "".join(
                    f'<td style="text-align:{al[j] if j < len(al) else "left"}">{inline(c)}</td>'
                    for j, c in enumerate(r)
                )
                body.append(f"<tr>{td}</tr>")
            out.append(
                '<div class="tscroll"><table><thead><tr>'
                + th
                + "</tr></thead><tbody>"
                + "".join(body)
                + "</tbody></table></div>"
            )
            continue

        # heading
        m = re.match(r"^(#{1,4})\s+(.*)$", line)
        if m:
            close_lists()
            lvl, txt = len(m.group(1)), m.group(2)
            if lvl == 1:
                if sec == "readme":
                    # The page masthead already carries this title; emitting it
                    # again reads as a duplication bug. Keep only the anchor.
                    out.append(f'<span id="sec-{sec}"></span>')
                else:
                    out.append(f'<h2 id="sec-{sec}">{inline(txt)}</h2>')
            else:
                # demote one level: the file's `#` is the section title, so `##`
                # must nest under it rather than sit beside it.
                tag = f"h{min(lvl + 1, 6)}"
                anchor = re.sub(r"[^a-z0-9]+", "-", txt.lower()).strip("-")
                out.append(f'<{tag} id="{sec}-{anchor}">{inline(txt)}</{tag}>')
            i += 1
            continue

        # hr
        if re.match(r"^\s*---+\s*$", line):
            close_lists()
            out.append('<hr class="soft">')
            i += 1
            continue

        # blockquote — a bare ">" is a paragraph break inside the quote, not the
        # end of it, so a multi-paragraph quote stays one block
        if line.startswith(">"):
            close_lists()
            paras, buf = [], []
            while i < n and lines[i].startswith(">"):
                text = lines[i][1:].strip()
                if text:
                    buf.append(text)
                elif buf:
                    paras.append(" ".join(buf))
                    buf = []
                i += 1
            if buf:
                paras.append(" ".join(buf))
            body = "".join(f"<p>{inline(p)}</p>" for p in paras)
            out.append(f"<blockquote>{body}</blockquote>")
            continue

        # task list
        m = re.match(r"^\s*-\s+\[([ xX])\]\s+(.*)$", line)
        if m:
            if not list_stack or list_stack[-1] != "ul":
                close_lists()
                out.append('<ul class="task">')
                list_stack.append("ul")
            box = "☑" if m.group(1).lower() == "x" else "☐"
            out.append(f'<li><span class="box">{box}</span> {inline(m.group(2))}</li>')
            i += 1
            continue

        # unordered / ordered list
        m = re.match(r"^\s*([-*])\s+(.*)$", line)
        if m:
            if not list_stack or list_stack[-1] != "ul":
                close_lists()
                out.append("<ul>")
                list_stack.append("ul")
            out.append(f"<li>{inline(m.group(2))}</li>")
            i += 1
            continue
        m = re.match(r"^\s*\d+\.\s+(.*)$", line)
        if m:
            if not list_stack or list_stack[-1] != "ol":
                close_lists()
                out.append("<ol>")
                list_stack.append("ol")
            out.append(f"<li>{inline(m.group(1))}</li>")
            i += 1
            continue

        # raw html block — skip, the site supplies its own chrome
        if re.match(r"^\s*</?(div|table|tr|td|th|img|p|br|span)\b", line):
            close_lists()
            i += 1
            continue

        # blank
        if not line.strip():
            close_lists()
            i += 1
            continue

        # paragraph
        close_lists()
        buf = [line]
        i += 1
        while i < n and lines[i].strip() and not re.match(r"^(#{1,4}\s|```|\s*[-*]\s|\s*\d+\.\s|>\s|\s*\|)", lines[i]):
            buf.append(lines[i])
            i += 1
        out.append(f"<p>{inline(' '.join(buf))}</p>")

    close_lists()
    return "\n".join(out)


# ── assemble ────────────────────────────────────────────────────────────────

STYLE = """
:root{
  --ground:#F5F5F7;--surface:#FFFFFF;--sunk:#F0F2F8;--dark:#0C0C0F;
  --ink:#1D1D1F;--ink-2:#3C3C43;--muted:#6E6E73;--faint:#86868B;
  --rule:#E2E4E9;--rule-strong:#D2D5DB;
  --accent:#0C0C0F;--accent-2:#1D1D1F;--accent-wash:#F5F5F7;--accent-edge:#E2E4E9;
  --spot:#22D3EE;--spot-2:#0EBDD9;--spot-ink:#0C2E33;--spot-text:#0E7490;
  --spot-wash:rgba(34,211,238,.22);--spot-edge:#A5E9F4;
  --ok:#0F7A5F;--warn:#B45309;--crit:#B42318;
  --display:-apple-system,system-ui,'SF Pro Display','Segoe UI',Inter,Roboto,Helvetica,Arial,sans-serif;
  --body:-apple-system,system-ui,'SF Pro Display','SF Pro Text','Segoe UI',Inter,Roboto,Helvetica,Arial,sans-serif;
  --mono:'JetBrains Mono',ui-monospace,'SF Mono','IBM Plex Mono',Menlo,Consolas,monospace;
  --r:10px;--r-md:12px;--r-lg:20px;--r-pill:980px;
  --sh:0 1px 3px rgba(0,0,0,.08),0 4px 12px rgba(0,0,0,.04);
  --sh-lg:0 8px 20px -4px rgba(0,0,0,.1),0 4px 8px -2px rgba(0,0,0,.05);
  --sh-card:0 10px 30px -24px rgba(0,0,0,.3);
  --sh-focus:0 0 0 3px rgba(34,211,238,.45);
}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);font-family:var(--body);font-size:17.5px;line-height:1.7;-webkit-font-smoothing:antialiased;letter-spacing:-.005em}
.hl{background:var(--spot);color:var(--spot-ink);border-radius:8px;padding:1px 10px;-webkit-box-decoration-break:clone;box-decoration-break:clone}
.shell{max-width:1240px;margin:0 auto;padding:clamp(30px,4vw,72px) clamp(18px,3vw,36px) 110px;display:grid;grid-template-columns:250px minmax(0,1fr);gap:clamp(28px,4vw,64px);align-items:start}
@media(max-width:900px){.shell{grid-template-columns:1fr}nav.toc{position:static!important;max-height:none!important;border-right:0!important;border-bottom:1px solid var(--rule);padding-bottom:20px}}
nav.toc{position:sticky;top:28px;max-height:calc(100vh - 56px);overflow-y:auto;border-right:1px solid var(--rule);padding-right:20px}
nav.toc .t{font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--faint);margin:0 0 14px}
nav.toc .t.s{margin:22px 0 10px;padding-top:18px;border-top:1px solid var(--rule)}
figure.dg{margin:34px 0;padding:0;background:var(--surface);border:1px solid var(--rule);border-radius:var(--r-lg);overflow:hidden;box-shadow:var(--sh-card)}
figure.dg svg{display:block;width:100%;height:auto;max-width:100%}
figure.dg figcaption{font-size:13.5px;line-height:1.6;color:var(--muted);padding:13px 20px 15px;border-top:1px solid var(--rule);background:var(--ground)}
figure.dg figcaption strong{color:var(--ink-2);font-weight:600}
p.missing{color:var(--crit);font-family:var(--mono);font-size:13px}
nav.toc a{display:block;font-size:14.5px;font-weight:500;color:var(--muted);text-decoration:none;padding:7px 12px;border-radius:var(--r-pill);transition:background .18s,color .18s}
nav.toc a:hover{color:var(--ink);background:var(--sunk)}
nav.toc a:focus-visible{outline:2px solid var(--accent);outline-offset:2px;box-shadow:var(--sh-focus)}
nav.toc a .n{font-family:var(--mono);font-size:11px;color:var(--faint);margin-right:9px}
header.mast{border-bottom:1px solid var(--rule);padding-bottom:38px;margin-bottom:10px}
header.mast h1{font-family:var(--display);font-weight:700;font-size:clamp(44px,7vw,84px);line-height:1.02;letter-spacing:-.038em;margin:0 0 18px;text-wrap:balance}
header.mast p{color:var(--muted);max-width:58ch;margin:0 0 28px;font-size:23px;line-height:1.45;letter-spacing:-.015em}
header.mast .meta{display:flex;flex-wrap:wrap;gap:8px}
header.mast .meta span{font-size:12.5px;color:var(--muted);background:var(--surface);border:1px solid var(--rule);border-radius:var(--r-pill);padding:6px 15px}
header.mast .meta b{color:var(--ink);font-weight:600;margin-right:6px}
header.mast .meta span:first-child{background:var(--spot);border-color:var(--spot);color:var(--spot-ink);font-weight:600}
header.mast .meta span:first-child b{color:var(--spot-ink)}
article{min-width:0}
.hero{border-bottom:1px solid var(--rule);padding-bottom:48px;margin-bottom:8px}
.hero .q{font-size:clamp(24px,2.8vw,34px);line-height:1.2;font-weight:700;letter-spacing:-.032em;margin:0 0 30px;max-width:22ch;text-wrap:balance}
.hero .q em{font-style:normal;color:var(--muted);display:block;font-size:17.5px;font-weight:400;line-height:1.6;margin-top:20px;letter-spacing:-.005em;max-width:62ch}
.wxy{display:grid;grid-template-columns:repeat(auto-fit,minmax(228px,1fr));gap:0;border:1px solid var(--rule);border-radius:var(--r-lg);overflow:hidden;background:var(--surface);box-shadow:var(--sh-card);margin:0 0 26px}
.wxy>div{padding:20px 22px;border-right:1px solid var(--rule)}
.wxy>div:last-child{border-right:0}
@media(max-width:820px){.wxy>div{border-right:0;border-bottom:1px solid var(--rule)}.wxy>div:last-child{border-bottom:0}}
.wxy h4{margin:0 0 7px;font-size:11.5px;letter-spacing:.1em;text-transform:uppercase;color:var(--faint);font-weight:700}
.wxy p{margin:0;font-size:15px;line-height:1.6;color:var(--ink-2);max-width:none}
.author{display:flex;gap:20px;align-items:flex-start;border:1px solid var(--rule);border-radius:var(--r-lg);padding:24px 26px;background:var(--surface);box-shadow:var(--sh-card);margin:0 0 26px;flex-wrap:wrap}
.author .ini{width:52px;height:52px;border-radius:var(--r-pill);background:var(--accent);color:#FFF;display:grid;place-items:center;font-size:17px;font-weight:700;flex:none;letter-spacing:-.02em}
.author .b{flex:1;min-width:240px}
.author .nm{font-family:var(--display);font-size:19px;font-weight:700;letter-spacing:-.022em;margin:0 0 2px}
.author .ro{font-size:14.5px;color:var(--muted);margin:0 0 12px}
.author .bio{font-size:14.5px;line-height:1.6;color:var(--ink-2);margin:0 0 14px;max-width:62ch}
.author .lk{display:flex;gap:8px;flex-wrap:wrap}
.author .lk a{font-size:13.5px;font-weight:500;text-decoration:none;border:1px solid var(--rule-strong);border-radius:var(--r-pill);padding:7px 16px;color:var(--ink);transition:background .18s,border-color .18s}
.author .lk a:hover{background:var(--sunk);border-color:var(--rule-strong)}
.startat{display:flex;gap:8px;flex-wrap:wrap;margin:0 0 4px}
.startat a{font-size:14.5px;font-weight:600;text-decoration:none;border:1px solid var(--rule-strong);border-radius:var(--r-pill);padding:9px 20px;color:var(--ink);background:var(--surface);transition:background .18s,border-color .18s,transform .12s}
.startat a:hover{background:var(--sunk);border-color:var(--rule-strong)}
.startat a:active{transform:translateY(1px)}
.startat a.k{background:var(--accent);border-color:var(--accent);color:#FFF}
.startat a.k:hover{background:var(--accent-2);border-color:var(--accent-2)}
section.doc{margin-top:88px;scroll-margin-top:24px}
section.doc:first-of-type{margin-top:52px}
h2{font-family:var(--display);font-weight:700;font-size:clamp(30px,3.6vw,44px);line-height:1.08;letter-spacing:-.034em;margin:0 0 26px;text-wrap:balance;scroll-margin-top:24px}
h3{font-family:var(--display);font-weight:700;font-size:21px;letter-spacing:-.024em;margin:42px 0 12px;text-wrap:balance;scroll-margin-top:24px}
h4{font-family:var(--display);font-weight:700;font-size:17px;letter-spacing:-.016em;margin:32px 0 10px;scroll-margin-top:24px}
h5{font-weight:700;font-size:12.5px;margin:26px 0 8px;color:var(--faint);letter-spacing:.1em;text-transform:uppercase;scroll-margin-top:24px}
p{margin:0 0 17px;max-width:72ch;text-wrap:pretty}
a{color:var(--ink);text-underline-offset:3px;text-decoration-thickness:1px;text-decoration-color:var(--rule-strong)}
a:hover{text-decoration-color:var(--accent)}
a:focus-visible{outline:2px solid var(--accent);outline-offset:3px;border-radius:6px;box-shadow:var(--sh-focus)}
strong{font-weight:600}
code{font-family:var(--mono);font-size:.85em;background:var(--sunk);padding:2px 7px;border-radius:6px;color:var(--ink)}
pre{font-family:var(--mono);font-size:13.5px;line-height:1.7;background:var(--surface);border:1px solid var(--rule);border-radius:var(--r-md);padding:18px 20px;overflow-x:auto;margin:0 0 22px;color:var(--ink-2);box-shadow:var(--sh-card)}
pre code{background:none;padding:0;font-size:inherit}
ul,ol{margin:0 0 15px;padding-left:24px;max-width:74ch}
li{margin-bottom:9px}
li::marker{color:var(--faint)}
ul.task{list-style:none;padding-left:2px}
ul.task .box{font-family:var(--mono);color:var(--ink);margin-right:9px}
blockquote{border:1px solid var(--rule);background:var(--surface);padding:18px 22px;margin:0 0 22px;border-radius:var(--r-md);max-width:74ch;box-shadow:var(--sh-card)}
blockquote p{margin:0 0 14px;max-width:none}
blockquote p:last-child{margin:0}
.tscroll{overflow-x:auto;margin:0 0 22px;border:1px solid var(--rule);border-radius:var(--r-lg);background:var(--surface);box-shadow:var(--sh-card)}
table{border-collapse:collapse;width:100%;font-size:15px;min-width:520px}
th{color:var(--faint);font-size:11px;font-weight:700;letter-spacing:.08em;text-transform:uppercase;padding:14px 16px 11px;border-bottom:1px solid var(--rule);vertical-align:bottom}
td{padding:13px 16px;border-bottom:1px solid var(--rule);vertical-align:top;color:var(--ink-2)}
tbody tr:last-child td{border-bottom:0}
td:first-child{color:var(--ink);font-weight:600}
hr.soft{border:0;border-top:1px solid var(--rule);margin:32px 0}
footer{margin-top:76px;padding-top:26px;border-top:1px solid var(--rule);font-size:14px;color:var(--faint)}
footer p{max-width:76ch;margin:0 0 8px}
"""


def title_of(md, fallback):
    m = re.search(r"^#\s+(.*)$", md, re.M)
    return m.group(1) if m else fallback


def main():
    sections, toc = [], []
    for rel in ORDER:
        path = ROOT / rel
        if not path.exists():
            print(f"  skip (missing): {rel}")
            continue
        md = path.read_text(encoding="utf-8")
        name = Path(rel).name
        m = re.match(r"^(\d{2})-", name)
        sec = m.group(1) if m else Path(name).stem.lower()
        raw = title_of(md, rel)
        if sec == "readme":
            label = "Introduction & index"
        elif sec == "author":
            label = "The author"
        else:
            label = raw.split("—", 1)[1].strip() if "—" in raw else raw
        toc.append((sec, label))
        body = render(md, sec)
        body = re.sub(r'href="#([\w-]+)" data-scoped="1"', lambda m: f'href="#{sec}-{m.group(1)}"', body)
        sections.append(f'<section class="doc" id="doc-{sec}">{body}</section>')
        print(f"  {rel}  →  #sec-{sec}")

    nav = "\n".join(
        f'<a href="#sec-{s}"><span class="n">{s if s.isdigit() else "—"}</span>{html.escape(t)}</a>'
        for s, t in toc
    )

    doc = f"""<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>uRWA Factory — Complete Documentation</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap">
<style>{STYLE}</style>
<div class="shell">
<nav class="toc" aria-label="Contents">
<p class="t">Contents</p>
{nav}
<p class="t s">Surfaces</p>
<a href="prototypes/"><span class="n">—</span>All prototypes</a>
<a href="prototypes/deploy-console.html"><span class="n">—</span>Deploy console</a>
<a href="prototypes/token-console.html"><span class="n">—</span>Token console</a>
<a href="prototypes/verifier.html"><span class="n">—</span>Public verifier</a>
<a href="prototypes/investor.html"><span class="n">—</span>Investor page</a>
<p class="t s">Repository</p>
<a href="https://github.com/StoboxTechnologies/uRWA-Factory"><span class="n">—</span>Source on GitHub</a>
<a href="LICENSE"><span class="n">—</span>Licence — MIT</a>
</nav>
<article>
<header class="mast">
<h1>uRWA Factory</h1>
<p>An open-source factory for real-world-asset security tokens that enforce their own compliance — free, MIT, and built on ERC-7943.</p>
<div class="meta">
<span><b>Status</b> Specification · no code yet</span>
<span><b>Licence</b> MIT</span>
<span><b>Chain</b> Base</span>
<span><b>Standard</b> ERC-7943 · 0x3edbb4c4</span>
</div>
</header>

<div class="hero">

<p class="q">May this specific person hold this specific asset, <span class="hl">right now, in this amount?</span>
<em>Every security token has to answer that correctly, on every transfer, forever. An ordinary ERC-20 cannot answer it at all. This is a complete, free implementation that can.</em></p>

<div class="wxy">
<div><h4>What it is</h4><p>A factory that deploys compliant security tokens. One transaction produces the token, its treasury and its rule set — and the rules are enforced on chain, not in a spreadsheet afterwards.</p></div>
<div><h4>How it works</h4><p>Three layers with different rules about what may change: an <b>immutable</b> ledger, a <b>replaceable</b> policy layer, and an <b>extensible</b> claims layer. A compliance bug can stop trading; it can never corrupt supply.</p></div>
<div><h4>Why it exists</h4><p>ERC-7943 is Final, but there is no reference issuance stack for it. A standard with one implementer is not a standard, so the tooling is given away rather than sold.</p></div>
<div><h4>Who it is for</h4><p>Issuers deploying an asset, investors who need to know the rules before buying, and integrators who want one interface that works across every conformant token.</p></div>
</div>

<div class="author">
<div class="ini">GD</div>
<div class="b">
<p class="nm">Gene Deyev</p>
<p class="ro">Founder &amp; CEO, Stobox Technologies — released here in a personal capacity</p>
<p class="bio">Founded Stobox in 2018 and has led it since. Author of the Stobox Tokenization Framework and co-author of one of the earliest practitioner guides to security token offerings, registered with the U.S. Copyright Office in 2019. Public backer of ERC-7943.<br><br>Copyright is held personally; the repository is hosted under the Stobox organisation for continuity, not ownership. Stobox Technologies is one user of this software among others. The affiliation is stated because you should know who wrote your compliance layer and what their interests are.</p>
<div class="lk">
<a href="https://stobox.io/team/gene-deyev">Profile</a>
<a href="https://github.com/genedeyev">GitHub</a>
<a href="mailto:gd@stoboxplatform.com">Email</a>
<a href="https://stobox.io">Stobox</a>
</div>
</div>
</div>

<div class="startat">
<a class="k" href="#sec-00">Why this exists</a>
<a href="#sec-02">Architecture</a>
<a href="#sec-07">Function reference</a>
<a href="prototypes/">Prototypes</a>
<a href="https://github.com/StoboxTechnologies/uRWA-Factory">Repository</a>
</div>

</div>

{"".join(sections)}
<footer>
<p>Generated by <code>build-docs.py</code> from <code>README.md</code> and <code>docs/*.md</code>.
Edit the Markdown, not this file.</p>
<p>Stobox is a software and infrastructure provider. This documentation describes product
architecture and is not legal, financial or investment advice.</p>
</footer>
</article>
</div>
<!-- source-digest: {source_digest()} -->
"""
    OUT.write_text(doc, encoding="utf-8")
    print(f"\n  wrote {OUT.relative_to(ROOT)}  ({len(doc):,} bytes, {len(sections)} sections)")


if __name__ == "__main__":
    main()
