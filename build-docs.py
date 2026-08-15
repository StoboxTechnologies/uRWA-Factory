#!/usr/bin/env python3
"""Build urwa-documentation.html from README.md + docs/*.md.

No dependencies. A deliberately small Markdown subset is supported — exactly the
constructs used in this documentation set: headings, tables, fenced code, lists,
task lists, blockquotes, horizontal rules, and inline code/bold/em/links.
"""

import html
import re
from pathlib import Path

ROOT = Path(__file__).parent
DOCS = ROOT / "docs"
OUT = ROOT / "urwa-documentation.html"

ORDER = ["README.md"] + [f"docs/{p.name}" for p in sorted(DOCS.glob("*.md"))]

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


def render(md, sec):
    lines = md.split("\n")
    out, i, n = [], 0, len(lines)
    list_stack = []

    def close_lists():
        while list_stack:
            out.append(f"</{list_stack.pop()}>")

    while i < n:
        line = lines[i]

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

        # blockquote
        if line.startswith("> "):
            close_lists()
            buf = []
            while i < n and lines[i].startswith("> "):
                buf.append(lines[i][2:])
                i += 1
            out.append(f"<blockquote>{inline(' '.join(buf))}</blockquote>")
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
  --ground:#FAFAFC;--surface:#FFFFFF;--sunk:#F4F5F9;
  --ink:#0E1017;--ink-2:#3A4050;--muted:#666E80;--faint:#949BAB;
  --rule:#EFF1F6;--rule-strong:#E2E5EE;
  --accent:#4338CA;--accent-2:#312BA0;--accent-wash:#F0F1FE;--accent-edge:#CFD2F9;
  --display:-apple-system,BlinkMacSystemFont,'SF Pro Display','Inter','Segoe UI',Roboto,Helvetica,Arial,sans-serif;
  --body:-apple-system,BlinkMacSystemFont,'SF Pro Text','Inter','Segoe UI',Roboto,Helvetica,Arial,sans-serif;
  --mono:ui-monospace,'SF Mono','JetBrains Mono','IBM Plex Mono',Menlo,Consolas,monospace;
  --r:10px;--r-lg:14px;--r-pill:999px;
  --sh:0 1px 2px rgba(14,16,23,.05),0 1px 3px rgba(14,16,23,.03);
}
*{box-sizing:border-box}
body{margin:0;background:var(--ground);color:var(--ink);font-family:var(--body);font-size:16px;line-height:1.68;-webkit-font-smoothing:antialiased;letter-spacing:-.003em}
.shell{max-width:1240px;margin:0 auto;padding:clamp(30px,4vw,72px) clamp(18px,3vw,36px) 110px;display:grid;grid-template-columns:238px minmax(0,1fr);gap:clamp(28px,4vw,64px);align-items:start}
@media(max-width:900px){.shell{grid-template-columns:1fr}nav.toc{position:static!important;max-height:none!important;border-right:0!important;border-bottom:1px solid var(--rule);padding-bottom:20px}}
nav.toc{position:sticky;top:28px;max-height:calc(100vh - 56px);overflow-y:auto;border-right:1px solid var(--rule);padding-right:20px}
nav.toc .t{font-size:11px;font-weight:600;letter-spacing:.1em;text-transform:uppercase;color:var(--faint);margin:0 0 14px}
nav.toc a{display:block;font-size:13.5px;color:var(--muted);text-decoration:none;padding:6px 10px;border-radius:var(--r);transition:background .14s,color .14s}
nav.toc a:hover{color:var(--ink);background:var(--sunk)}
nav.toc a:focus-visible{outline:2px solid var(--accent);outline-offset:2px}
nav.toc a .n{font-family:var(--mono);font-size:11px;color:var(--faint);margin-right:9px}
header.mast{border-bottom:1px solid var(--rule);padding-bottom:34px;margin-bottom:10px}
header.mast h1{font-family:var(--display);font-weight:600;font-size:clamp(34px,5.4vw,54px);line-height:1.03;letter-spacing:-.032em;margin:0 0 16px;text-wrap:balance}
header.mast p{color:var(--muted);max-width:62ch;margin:0 0 22px;font-size:18px;line-height:1.6}
header.mast .meta{display:flex;flex-wrap:wrap;gap:8px}
header.mast .meta span{font-size:12.5px;color:var(--muted);background:var(--sunk);border-radius:var(--r-pill);padding:5px 14px}
header.mast .meta b{color:var(--ink);font-weight:600;margin-right:6px}
article{min-width:0}
section.doc{margin-top:76px;scroll-margin-top:24px}
section.doc:first-of-type{margin-top:44px}
h2{font-family:var(--display);font-weight:600;font-size:clamp(24px,3vw,32px);line-height:1.15;letter-spacing:-.026em;margin:0 0 24px;text-wrap:balance;scroll-margin-top:24px}
h3{font-weight:600;font-size:17px;letter-spacing:-.012em;margin:38px 0 12px;text-wrap:balance;scroll-margin-top:24px}
h4{font-weight:600;font-size:15px;margin:30px 0 10px;scroll-margin-top:24px}
h5{font-weight:600;font-size:12.5px;margin:24px 0 8px;color:var(--muted);letter-spacing:.04em;text-transform:uppercase;scroll-margin-top:24px}
p{margin:0 0 15px;max-width:74ch;text-wrap:pretty}
a{color:var(--accent);text-underline-offset:3px;text-decoration-thickness:1px}
a:focus-visible{outline:2px solid var(--accent);outline-offset:3px;border-radius:4px}
strong{font-weight:600}
code{font-family:var(--mono);font-size:.85em;background:var(--sunk);padding:2px 7px;border-radius:6px;color:var(--ink)}
pre{font-family:var(--mono);font-size:12.5px;line-height:1.65;background:var(--surface);border:1px solid var(--rule);border-radius:var(--r-lg);padding:18px 20px;overflow-x:auto;margin:0 0 22px;color:var(--ink-2);box-shadow:var(--sh)}
pre code{background:none;padding:0;font-size:inherit}
ul,ol{margin:0 0 15px;padding-left:24px;max-width:74ch}
li{margin-bottom:8px}
li::marker{color:var(--faint)}
ul.task{list-style:none;padding-left:2px}
ul.task .box{font-family:var(--mono);color:var(--accent);margin-right:9px}
blockquote{border:1px solid var(--accent-edge);background:var(--accent-wash);padding:16px 20px;margin:0 0 22px;border-radius:var(--r-lg);max-width:74ch}
blockquote p{margin:0}
.tscroll{overflow-x:auto;margin:0 0 22px;border:1px solid var(--rule);border-radius:var(--r-lg);background:var(--surface);box-shadow:var(--sh)}
table{border-collapse:collapse;width:100%;font-size:14px;min-width:520px}
th{color:var(--faint);font-size:11px;font-weight:600;letter-spacing:.08em;text-transform:uppercase;padding:14px 16px 11px;border-bottom:1px solid var(--rule);vertical-align:bottom}
td{padding:12px 16px;border-bottom:1px solid var(--rule);vertical-align:top;color:var(--ink-2)}
tbody tr:last-child td{border-bottom:0}
td:first-child{color:var(--ink);font-weight:600}
hr.soft{border:0;border-top:1px solid var(--rule);margin:32px 0}
footer{margin-top:76px;padding-top:26px;border-top:1px solid var(--rule);font-size:13px;color:var(--faint)}
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

    doc = f"""<title>uRWA Factory — Complete Documentation</title>
<style>{STYLE}</style>
<div class="shell">
<nav class="toc" aria-label="Contents">
<p class="t">Contents</p>
{nav}
</nav>
<article>
<header class="mast">
<h1>uRWA Factory</h1>
<p>Complete documentation: architecture, contracts, storage, roles, states, every function, and the
build order. Generated from the Markdown sources so the two never diverge.</p>
<div class="meta">
<span><b>Version</b> specification</span>
<span><b>Licence</b> MIT</span>
<span><b>Chain</b> Base</span>
<span><b>Standard</b> ERC-7943 · 0x3edbb4c4</span>
</div>
</header>
{"".join(sections)}
<footer>
<p>Generated by <code>build-docs.py</code> from <code>README.md</code> and <code>docs/*.md</code>.
Edit the Markdown, not this file.</p>
<p>Stobox is a software and infrastructure provider. This documentation describes product
architecture and is not legal, financial or investment advice.</p>
</footer>
</article>
</div>
"""
    OUT.write_text(doc, encoding="utf-8")
    print(f"\n  wrote {OUT.relative_to(ROOT)}  ({len(doc):,} bytes, {len(sections)} sections)")


if __name__ == "__main__":
    main()
