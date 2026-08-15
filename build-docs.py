#!/usr/bin/env python3
"""Build index.html — the whole documentation as one page — from README.md + docs/*.md.

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
OUT = ROOT / "index.html"
THEME = ROOT / "theme.css"


def source_digest():
    """Digest of every input to this build.

    Stamped into the output so verify.py L0.6 can tell a stale build from a
    current one by content. File timestamps cannot do that — a fresh git
    checkout gives every file the same mtime.
    """
    h = hashlib.sha256()
    for p in sorted(DOCS.glob("*.md")) + [ROOT / "build-docs.py", THEME]:
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
/* landing cards and page-to-page navigation */
.cards{display:grid;grid-template-columns:repeat(auto-fill,minmax(238px,1fr));gap:10px;margin:8px 0 30px}
.cards .card{display:flex;align-items:baseline;gap:11px;padding:14px 16px;border:1px solid var(--rule);
  border-radius:var(--r-lg);background:var(--surface);text-decoration:none;transition:border-color .14s,background .14s}
.cards .card:hover{border-color:var(--rule-strong);background:var(--ground)}
.cards .card .n{font-family:var(--mono);font-size:11px;color:var(--faint);flex:none}
.cards .card .l{font-size:14.5px;font-weight:500;color:var(--ink);line-height:1.35}
.allnote{font-size:14px;color:var(--muted);padding-top:20px;border-top:1px solid var(--rule)}
.pnav{display:flex;flex-wrap:wrap;gap:10px;justify-content:space-between;margin:44px 0 8px;
  padding-top:22px;border-top:1px solid var(--rule)}
.pnav .pn{font-size:14px;color:var(--muted);text-decoration:none;padding:9px 14px;
  border:1px solid var(--rule);border-radius:var(--r-pill);transition:border-color .14s,color .14s}
.pnav .pn:hover{color:var(--ink);border-color:var(--rule-strong)}
.pnav .pn.n{margin-left:auto}
nav.toc a[aria-current="page"]{color:var(--ink);background:var(--sunk);font-weight:600}
nav.toc a.home{font-weight:600;color:var(--ink);margin-bottom:10px;padding-bottom:12px;border-bottom:1px solid var(--rule);border-radius:0}

/* Page styles for the documentation site. Tokens, controls, containers, marks
   and the site navigation come from theme.css, which is inlined above this
   block at build time — never restate them here. */
body{font-size:17.5px;line-height:1.7}
/* the bar's brand lines up with the contents heading below it */
nav.sitenav{padding-left:clamp(18px,2.2vw,40px);padding-right:clamp(18px,2.2vw,40px)}
.shell{max-width:none;margin:0;padding:clamp(24px,2.5vw,44px) clamp(18px,2.2vw,40px) 120px;display:grid;grid-template-columns:250px minmax(0,1fr) 268px;gap:clamp(24px,2.6vw,56px);align-items:start}
@media(max-width:1180px){.shell{grid-template-columns:236px minmax(0,1fr)}aside.rail{display:none}.relmob{display:block}}
@media(max-width:900px){.shell{grid-template-columns:1fr}nav.toc{position:static!important;max-height:min(42vh,320px)!important;overflow-y:auto!important;border-right:0!important;border-bottom:1px solid var(--rule);padding:0 0 16px!important;-webkit-mask-image:linear-gradient(to bottom,#000 calc(100% - 36px),transparent);mask-image:linear-gradient(to bottom,#000 calc(100% - 36px),transparent)}}
nav.toc{position:sticky;top:86px;max-height:calc(100vh - 116px);overflow-y:auto;border-right:1px solid var(--rule);padding-right:20px}
nav.toc .t{font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--faint);margin:0 0 14px}
nav.toc .t.s{margin:22px 0 10px;padding-top:18px;border-top:1px solid var(--rule)}
figure.dg{margin:34px 0;padding:0;background:var(--surface);border:1px solid var(--rule);border-radius:var(--r-lg);overflow:hidden;box-shadow:var(--sh-card)}
figure.dg svg{display:block;width:100%;height:auto;max-width:100%}
figure.dg figcaption{font-size:13.5px;line-height:1.6;color:var(--muted);padding:13px 20px 15px;border-top:1px solid var(--rule);background:var(--ground)}
figure.dg figcaption strong{color:var(--ink-2);font-weight:600}
p.missing{color:var(--crit);font-family:var(--mono);font-size:13px}
nav.toc a{display:block;font-size:14.5px;font-weight:500;color:var(--muted);text-decoration:none;padding:7px 12px;border-radius:var(--r-pill);transition:background .18s,color .18s}
nav.toc a:hover{color:var(--ink);background:var(--sunk)}
nav.toc a[aria-current="true"]{color:var(--accent);background:var(--spot-wash);font-weight:600;box-shadow:inset 0 0 0 1px var(--spot-edge)}
nav.toc a[aria-current="true"] .n{color:var(--accent)}
nav.toc a:focus-visible{outline:2px solid var(--accent);outline-offset:2px;box-shadow:var(--sh-focus)}
nav.toc a .n{font-family:var(--mono);font-size:11px;color:var(--faint);margin-right:9px}
aside.rail{position:sticky;top:86px;max-height:calc(100vh - 116px);overflow-y:auto;border-left:1px solid var(--rule);padding-left:22px}
aside.rail .railt{font-size:11px;font-weight:700;letter-spacing:.1em;text-transform:uppercase;color:var(--faint);margin:0 0 10px}
aside.rail .railt.s{margin-top:26px;padding-top:20px;border-top:1px solid var(--rule)}
aside.rail a{display:block;font-size:13.5px;line-height:1.45;color:var(--muted);text-decoration:none;padding:6px 10px;border-radius:var(--r);transition:background .18s,color .18s}
aside.rail a:hover{color:var(--ink);background:var(--sunk)}
aside.rail a:focus-visible{outline:2px solid var(--accent);outline-offset:2px;box-shadow:var(--sh-focus)}
aside.rail .railsec{display:none}
aside.rail .railsec.on{display:block}
aside.rail .empty{font-size:13px;color:var(--faint);margin:0;padding:0 10px}
.relmob{display:none}
header.mast{border-bottom:1px solid var(--rule);padding-bottom:38px;margin-bottom:10px}
header.mast h1{font-family:var(--display);font-weight:700;font-size:clamp(44px,7vw,84px);line-height:1.02;letter-spacing:-.038em;margin:0 0 18px;text-wrap:balance}
header.mast p{color:var(--muted);max-width:58ch;margin:0 0 28px;font-size:23px;line-height:1.45;letter-spacing:-.015em}
header.mast .meta{display:flex;flex-wrap:wrap;gap:8px}
header.mast .meta span{font-size:12.5px;color:var(--muted);background:var(--surface);border:1px solid var(--rule);border-radius:var(--r-pill);padding:6px 15px}
header.mast .meta b{color:var(--ink);font-weight:600;margin-right:6px}
header.mast .meta span:first-child{background:var(--spot);border-color:var(--spot);color:var(--spot-ink);font-weight:600}
header.mast .meta span:first-child b{color:var(--spot-ink)}
article{min-width:0}
@media(min-width:1181px){article h3[id$="-related-documents"],article h3[id$="-related-documents"]+ul,article h3[id$="-related"],article h3[id$="-related"]+ul{display:none}}
.hero{border-bottom:1px solid var(--rule);padding-bottom:48px;margin-bottom:8px}
.hero .q{font-size:clamp(24px,2.8vw,34px);line-height:1.2;font-weight:700;letter-spacing:-.032em;margin:0 0 30px;max-width:22ch;text-wrap:balance}
.hero .q em{font-style:normal;color:var(--muted);display:block;font-size:17.5px;font-weight:400;line-height:1.6;margin-top:20px;letter-spacing:-.005em;max-width:62ch}
.wxy{display:grid;grid-template-columns:repeat(2,minmax(0,1fr));gap:14px;margin:0 0 30px}
.wxy>div{padding:24px 26px;border:1px solid var(--rule);border-radius:var(--r-lg);background:var(--surface);box-shadow:var(--sh-card)}
@media(max-width:640px){.wxy{grid-template-columns:1fr}}
.wxy h4{margin:0 0 10px;font-size:11.5px;letter-spacing:.1em;text-transform:uppercase;color:var(--muted);font-weight:700}
.wxy p{margin:0;font-size:15.5px;line-height:1.6;color:var(--ink-2);max-width:none}
.wxy strong,.wxy b{color:var(--ink)}
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
section.doc{margin-top:72px;padding-top:56px;border-top:1px solid var(--rule);scroll-margin-top:86px}
section.doc:first-of-type{margin-top:44px}
h2{font-family:var(--display);font-weight:700;font-size:clamp(30px,3.6vw,44px);line-height:1.08;letter-spacing:-.034em;margin:0 0 26px;text-wrap:balance;scroll-margin-top:86px}
h3{font-family:var(--display);font-weight:700;font-size:21px;letter-spacing:-.024em;margin:42px 0 12px;text-wrap:balance;scroll-margin-top:86px}
h4{font-family:var(--display);font-weight:700;font-size:17px;letter-spacing:-.016em;margin:32px 0 10px;scroll-margin-top:86px}
h5{font-weight:700;font-size:12.5px;margin:26px 0 8px;color:var(--faint);letter-spacing:.1em;text-transform:uppercase;scroll-margin-top:86px}
p{margin:0 0 17px;max-width:74ch;text-wrap:pretty}
article{--measure:74ch}
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
details.faq{border:1px solid var(--rule);border-radius:var(--r-md);background:var(--surface);margin:0 0 8px;box-shadow:var(--sh-card)}
details.faq>summary{cursor:pointer;list-style:none;padding:15px 52px 15px 20px;font-family:var(--display);font-size:16.5px;font-weight:600;letter-spacing:-.016em;position:relative;border-radius:var(--r-md)}
details.faq>summary::-webkit-details-marker{display:none}
details.faq>summary::after{content:"";position:absolute;right:20px;top:50%;width:9px;height:9px;margin-top:-6px;border-right:2px solid var(--faint);border-bottom:2px solid var(--faint);transform:rotate(45deg);transition:transform .18s}
details.faq[open]>summary::after{transform:rotate(-135deg);margin-top:-2px}
details.faq>summary:hover{background:var(--sunk)}
details.faq>summary:focus-visible{outline:2px solid var(--accent);outline-offset:2px;box-shadow:var(--sh-focus)}
details.faq[open]>summary{border-bottom:1px solid var(--rule);border-radius:var(--r-md) var(--r-md) 0 0}
details.faq p{margin:0;padding:16px 20px 18px;font-size:16px;color:var(--ink-2);max-width:74ch}
@media(prefers-reduced-motion:reduce){details.faq>summary::after{transition:none}}
hr.soft{border:0;border-top:1px solid var(--rule);margin:32px 0}
footer{margin-top:76px;padding-top:26px;border-top:1px solid var(--rule);font-size:14px;color:var(--faint)}
footer p{max-width:76ch;margin:0 0 8px}
@media(prefers-reduced-motion:reduce){.startat a:active{transform:none}}
"""


# A 33-entry contents list with nothing marked tells the reader nothing about
# where they are. This marks the section being read; without JavaScript the
# list behaves exactly as it did before.
SPY = """<script>
(() => {
  const nav = document.querySelector("nav.toc");
  const secs = [...document.querySelectorAll("section.doc")];
  if (!nav || !secs.length) return;

  const links = new Map();
  document.querySelectorAll('nav.toc a[href^="#sec-"]').forEach(a =>
    links.set(a.getAttribute("href").slice(1), a));

  let current = null;
  const mark = id => {
    if (id === current) return;
    const prev = links.get(current);
    if (prev) prev.removeAttribute("aria-current");
    document.querySelectorAll("aside.rail .railsec.on").forEach(b => b.classList.remove("on"));
    const block = document.querySelector('aside.rail .railsec[data-sec="' + id + '"]');
    if (block) block.classList.add("on");
    const next = links.get(id);
    if (next) {
      next.setAttribute("aria-current", "true");
      // Keep the mark inside the contents list without scrolling the page.
      const r = next.getBoundingClientRect(), n = nav.getBoundingClientRect();
      if (r.top < n.top || r.bottom > n.bottom) nav.scrollTop += r.top - n.top - n.height / 3;
    }
    current = id;
  };

  // The section whose top has passed a line a quarter down the viewport is the
  // one being read. Plain geometry: no observer, no dependency, and it settles
  // correctly on load, on resize, and after a jump to an anchor.
  const pick = () => {
    const line = window.innerHeight * 0.25;
    let id = secs[0].id;
    for (const sec of secs) {
      if (sec.getBoundingClientRect().top > line) break;
      id = sec.id;
    }
    mark("sec-" + id.replace("doc-", ""));
  };

  const frame = window.requestAnimationFrame || (fn => setTimeout(fn, 16));
  let queued = false;
  const onScroll = () => {
    if (queued) return;
    queued = true;
    frame(() => { queued = false; pick(); });
  };
  addEventListener("scroll", onScroll, { passive: true });
  addEventListener("resize", onScroll, { passive: true });
  addEventListener("hashchange", onScroll);

  // A click moves the mark at once, before the scroll settles.
  links.forEach((a, id) => a.addEventListener("click", () => mark(id)));

  pick();
})();
</script>"""


def rail_block(sec, heads, rel):
    """One section's reference column: where you are, and where to go next."""
    out = [f'<div class="railsec" data-sec="sec-{sec}">']
    if heads:
        out.append('<p class="railt">On this page</p>')
        out += [f'<a href="#{a}">{html.escape(t)}</a>' for a, t in heads]
    if rel:
        out.append(f'<p class="railt{" s" if heads else ""}">Related</p>')
        out += [link(label, href) for label, href in rel]
    if not heads and not rel:
        out.append('<p class="empty">No further reading for this section.</p>')
    out.append("</div>")
    return "".join(out)


def accordion(body):
    """Turn each question into a disclosure.

    Fifty-odd questions as a flat wall of headings is a document nobody scans.
    As disclosures the whole set fits on one screen and the reader opens what
    they came for. The anchor moves onto the <details>, so links still resolve.
    """
    parts = re.split(r'(<h4 id="[^"]*">.*?</h4>)', body)
    out = [parts[0]]
    for i in range(1, len(parts), 2):
        head = parts[i]
        rest = parts[i + 1] if i + 1 < len(parts) else ""
        m = re.search(r"<h3\b", rest)
        tail = ""
        if m:
            rest, tail = rest[: m.start()], rest[m.start() :]
        anchor = re.search(r'id="([^"]*)"', head).group(1)
        label = re.sub(r"</?h4[^>]*>", "", head)
        out.append(f'<details class="faq" id="{anchor}"><summary>{label}</summary>{rest}</details>{tail}')
    return "".join(out)


def related(md):
    """The links a document points at, for the reference rail."""
    m = re.search(r"^##\s+Related.*?$\n(.*?)(?=^##\s|\Z)", md, re.M | re.S)
    if not m:
        return []
    return re.findall(r"^-\s+\[([^\]]+)\]\(([^)]+)\)", m.group(1), re.M)


def subheads(body):
    """Second-level headings of a rendered section, for "on this page"."""
    out = []
    for anchor, label in re.findall(r'<h3 id="([^"]+)">(.*?)</h3>', body, re.S):
        if anchor.endswith("-related") or anchor.endswith("-related-documents"):
            continue
        out.append((anchor, re.sub(r"<[^>]+>", "", label)))
    return out

def title_of(md, fallback):
    m = re.search(r"^#\s+(.*)$", md, re.M)
    return m.group(1) if m else fallback


PAGES = ROOT / "pages"
ALL = ROOT / "all.html"


def page_file(sec, rel):
    """The file name a document gets as its own page."""
    if sec == "readme":
        return "index.html"
    if sec == "author":
        return "author.html"
    return Path(rel).stem + ".html"


def to_pages(body, files, prefix=""):
    """Rewrite combined-mode section anchors into links between pages."""
    def sub(m):
        target = files.get(m.group(1))
        return f'href="{prefix}{target}"' if target else m.group(0)

    return re.sub(r'href="#sec-([\w-]+)"', sub, body)


def main():
    sections, toc, rails = [], [], []
    docs, files = {}, {}
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
        heads = subheads(body)
        if sec == "32":
            body = accordion(body)
        sections.append(f'<section class="doc" id="doc-{sec}">{body}</section>')
        rail = rail_block(sec, heads, related(md))
        rails.append(rail)
        files[sec] = page_file(sec, rel)
        docs[sec] = {"label": label, "title": raw, "body": body, "rail": rail}
        print(f"  {rel}  →  {files[sec]}")

    nav = "\n".join(
        f'<a href="#sec-{s}"><span class="n">{s if s.isdigit() else "—"}</span>{html.escape(t)}</a>'
        for s, t in toc
    )

    def shell(BODY, NAV, RAIL, TITLE):
        return f"""<!DOCTYPE html>
<html lang="en">
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>{TITLE}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Inter:wght@400;500;600;700&display=swap">
<style>{THEME.read_text(encoding="utf-8")}{STYLE}</style>
<nav class="sitenav" aria-label="Documentation">
<a class="home" href="#top">uRWA Factory</a>
<span class="div"></span>
<a href="#sec-00">Start</a>
<a href="#sec-04">Mechanics</a>
<a href="#sec-15">Standards</a>
<a href="#sec-21">Interfaces</a>
<a href="#sec-27">Models</a>
<a href="#sec-32">FAQ</a>
<a href="#sec-author">Author</a>
<span class="div"></span>
<a href="prototypes/index.html">Prototypes</a>
<a class="push" href="https://github.com/StoboxTechnologies/uRWA-Factory">GitHub</a>
</nav>
<div class="shell" id="top">
<nav class="toc" aria-label="Contents">
<p class="t">Contents</p>
{NAV}
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

{BODY}
<footer>
<p>Generated by <code>build-docs.py</code> from <code>README.md</code> and <code>docs/*.md</code>.
Edit the Markdown, not this file.</p>
<p>Stobox is a software and infrastructure provider. This documentation describes product
architecture and is not legal, financial or investment advice.</p>
</footer>
</article>
<aside class="rail" aria-label="Section reference">
{RAIL}
<div class="railfix">
<p class="railt s">Reference</p>
<a href="prototypes/">Prototypes</a>
<a href="https://github.com/StoboxTechnologies/uRWA-Factory">Source on GitHub</a>
<a href="https://eips.ethereum.org/EIPS/eip-7943">ERC-7943 on eips.ethereum.org</a>
<a href="LICENSE">Licence — MIT</a>
</div>
</aside>
</div>
{SPY}
<!-- source-digest: {source_digest()} -->
"""
    # ── the combined corpus ──────────────────────────────────────────────
    # Kept because splitting the site costs full-corpus Ctrl+F, which is how
    # people actually find a term across thirty-three documents. Also what
    # prints, and what reads offline.
    ALL.write_text(shell("".join(sections), nav, "".join(rails),
                         "uRWA Factory — Complete Documentation"), encoding="utf-8")

    # ── one page per document ────────────────────────────────────────────
    PAGES.mkdir(exist_ok=True)
    for old_page in PAGES.glob("*.html"):
        old_page.unlink()

    order = [s for s, _ in toc]
    for i, sec in enumerate(order):
        d = docs[sec]
        page_nav = "\n".join(
            f'<a href="{files[s]}"{" aria-current=\"page\"" if s == sec else ""}>'
            f'<span class="n">{s if s.isdigit() else "—"}</span>{html.escape(lbl)}</a>'
            for s, lbl in toc
        )
        page_nav = ('<a class="home" href="../index.html">'
                    '<span class="n">↑</span>All documentation</a>\n' + page_nav)
        prev_next = []
        if i:
            prev_next.append(f'<a class="pn p" href="{files[order[i-1]]}">← {html.escape(docs[order[i-1]]["label"])}</a>')
        if i + 1 < len(order):
            prev_next.append(f'<a class="pn n" href="{files[order[i+1]]}">{html.escape(docs[order[i+1]]["label"])} →</a>')
        body = d["body"] + f'<nav class="pnav" aria-label="Adjacent documents">{"".join(prev_next)}</nav>'
        page = shell(f'<section class="doc" id="doc-{sec}">{body}</section>',
                     page_nav, d["rail"], f'{d["title"]} — uRWA Factory')
        # Rewrite across the whole page, not just the body: the masthead and the
        # rail carry section anchors too, and a page has no other section to
        # anchor into.
        page = to_pages(page, files)
        page = page.replace('href="prototypes/', 'href="../prototypes/')
        page = page.replace('href="LICENSE"', 'href="../LICENSE"')
        page = page.replace('<style>', '<base href=".">\n<style>', 1)
        (PAGES / files[sec]).write_text(page, encoding="utf-8")

    # ── the landing page ─────────────────────────────────────────────────
    cards = "".join(
        f'<a class="card" href="pages/{files[s]}"><span class="n">{s if s.isdigit() else "—"}</span>'
        f'<span class="l">{html.escape(lbl)}</span></a>'
        for s, lbl in toc if s != "readme"
    )
    index_nav = "\n".join(
        f'<a href="pages/{files[s]}"><span class="n">{s if s.isdigit() else "—"}</span>{html.escape(lbl)}</a>'
        for s, lbl in toc
    )
    landing = (f'<div class="cards">{cards}</div>'
               f'<p class="allnote">Every document on one page, for searching and printing: '
               f'<a href="all.html">the complete documentation</a>.</p>')
    index = shell(landing, index_nav, "", "uRWA Factory — Documentation")
    index = to_pages(index, files, prefix="pages/")
    OUT.write_text(index, encoding="utf-8")

    print(f"\n  wrote {OUT.name}, {ALL.name} and {len(order)} pages in {PAGES.name}/")


if __name__ == "__main__":
    main()
