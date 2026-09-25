#!/usr/bin/env python3
"""Assemble stobox-orbit.html – the whole of Stobox Orbit on one page – from the seven
architecture pages plus two sections that exist only here: the rulings and the roadmap.

Run from docs/architecture/:  python3 build-master.py
The seven pages stay the sources; this file is generated and committed."""
import re, datetime, pathlib

HERE = pathlib.Path(__file__).parent
PAGES = ['stv4', 'orbit', 'identity', 'terms', 'offering', 'intelligence', 'functions']
VERSION = 'v1.0'
DATE = '25 Sep 2026'

src = {p: (HERE / f'{p}.html').read_text(encoding='utf-8') for p in PAGES}


def style(p):
    return re.search(r'<style>(.*?)</style>', src[p], re.S).group(1)


def sections(p):
    """id -> section html, in document order."""
    out = {}
    for m in re.finditer(r'<section aria-labelledby="([^"]+)">.*?</section>', src[p], re.S):
        out[m.group(1)] = m.group(0)
    return out


def prefix_ids(html, p):
    html = re.sub(r'\bid="([^"]+)"', lambda m: f'id="{p}-{m.group(1)}"', html)
    html = re.sub(r'aria-labelledby="([^"]+)"', lambda m: f'aria-labelledby="{p}-{m.group(1)}"', html)
    html = re.sub(r'aria-describedby="([^"]+)"', lambda m: f'aria-describedby="{p}-{m.group(1)}"', html)
    html = re.sub(r'href="#([^"]+)"', lambda m: f'href="#{p}-{m.group(1)}"', html)
    html = re.sub(r'url\(#([^)]+)\)', lambda m: f'url(#{p}-{m.group(1)})', html)
    # cross-page links become in-document anchors
    for q in PAGES:
        html = re.sub(rf'href="{q}\.html#([^"]+)"', lambda m: f'href="#{q}-{m.group(1)}"', html)
        html = html.replace(f'href="{q}.html"', f'href="#part-{q}"')
    return html


def renumber(html, part):
    def k(m):
        t = m.group(1)
        t2 = re.sub(r'^(\d+[ab]?) · ', lambda n: f'{part}{n.group(1)} · ', t)
        if t2 == t:
            t2 = f'{part} · {t}'
        return f'<span class="kicker">{t2}</span>'
    return re.sub(r'<span class="kicker">([^<]+)</span>', k, html)


# ---------------------------------------------------------------- style: union
base = style('stv4')
extra = []
for p in PAGES[1:]:
    for line in style(p).splitlines():
        if line not in base and line not in extra and not line.startswith(('.four{', 'table{', 'th,td{', '.card ul{', 'pre{')):
            extra.append(line)
master_css = base + '\n' + '\n'.join(extra) + '''
.card ul,.card ol{margin:0;padding-left:18px;display:grid;gap:6px}
.card .big{font:700 28px/1 var(--display);color:var(--ink)}
td code{white-space:nowrap}
.part{margin-top:96px;padding-top:40px;border-top:3px solid var(--accent);display:grid;gap:8px}
.part .kicker{color:var(--accent)}
.part h2{font-size:clamp(24px,3.2vw,34px)}
.part p{max-width:70ch;color:var(--ink-2);font-size:17px}
nav.toc{display:grid;gap:6px;background:var(--surface);border:1px solid var(--rule);border-radius:10px;padding:18px 20px}
nav.toc ol{margin:0;padding-left:22px;display:grid;gap:5px;columns:1}
nav.toc li{font-size:14.5px;color:var(--ink-2)}
nav.toc a{text-decoration:none}
nav.toc a:hover{text-decoration:underline}
nav.toc .sub{font:12.5px var(--mono);color:var(--muted);margin-left:6px}
.gantt .bar{fill:var(--surface);stroke-width:1.6}
.gantt .bar.p0{stroke:var(--gap);fill:color-mix(in srgb,var(--gap) 10%,var(--surface))}
.gantt .bar.crit{stroke:var(--accent);fill:color-mix(in srgb,var(--accent) 12%,var(--surface))}
.gantt .bar.par{stroke:var(--pending);stroke-dasharray:6 4}
.gantt .bar.later{stroke:var(--ready);stroke-dasharray:2 3}
.gantt .bar.gate{stroke:var(--option);stroke-dasharray:2 3;fill:var(--region)}
.gantt .wk{font:500 10.5px var(--mono);fill:var(--muted)}
.gantt .grid{stroke:var(--rule);stroke-width:1}
.gantt .ms{stroke:var(--accent);stroke-width:1.6;stroke-dasharray:4 3}
.gantt .msl{font:600 10.5px var(--body);fill:var(--accent);paint-order:stroke;stroke:var(--surface);stroke-width:4px;stroke-linejoin:round}
.gantt .lbl{font:600 13px var(--body);fill:var(--ink)}
.gantt .sub{font:400 10.5px var(--mono);fill:var(--muted);paint-order:stroke;stroke:var(--surface);stroke-width:4px;stroke-linejoin:round}
'''

# ---------------------------------------------------------------- new sections
RULINGS = '''
<section aria-labelledby="rul-h">
  <div class="head">
    <span class="kicker">A0 · Rulings</span>
    <h2 id="rul-h">What Gene has ruled, 25 September 2026</h2>
    <p class="prose">Every decision the pages below rest on, in the order it was taken. A ruling is canon until Gene changes it; where a page says "as ruled", this is the list it means.</p>
  </div>
  <div class="tbl">
  <table>
    <thead><tr><th>#</th><th>Ruling</th><th>Where it lands</th></tr></thead>
    <tbody>
      <tr><td class="v">R1</td><td><b>STV4 is the uRWA Factory on Base</b>, every STV3 facet rebuilt, not copied; Intelligence facet and Stobox Oracle on top; Stobox DID under every record.</td><td>Part B</td></tr>
      <tr><td class="v">R2</td><td><b>STBX</b>: 1,415,000 tokens, each an economic interest in one Class C share held by Stobox Tokenized Equities Ltd (BVI); moves to Base; reference price = Eqvista Real-Time Valuation, raw, as often as Eqvista updates; no US persons; the Reg D perk removed; no STBX token exists on Base yet.</td><td>Part C · Offering §5</td></tr>
      <tr><td class="v">R3</td><td><b>Compass Board</b>: a manual bulletin board in BVI operated by Stobox Innovations Ltd, escrow lots, USDC straight to the seller, no treasury, no fees today, no ATS, no matching. A Compass function (Compass = Issue · Price · Board).</td><td>Part C · Offering §5, Part E §12</td></tr>
      <tr><td class="v">R4</td><td><b>One subject-keyed identity registry on Base</b>; holder rights exactly as the SPA gives them; Terms precedence term-by-term; <code>corporate.action</code> structured and executable ("autonomous assets for real").</td><td>Part C · Identity, Terms, Intelligence</td></tr>
      <tr><td class="v">R5</td><td><b>An attested figure is signed by the client and by Stobox</b>, with signer roles for named third parties per channel; trust scoping as securities law requires – a universal base gate, issuer-scoped claims in every securities preset.</td><td>Part C · Intelligence §4b, Identity §4</td></tr>
      <tr><td class="v">R6</td><td><b>The name is Stobox Orbit</b>: one name over the open-source uRWA Factory, the hosted Factory, Intelligence, the oracle and the agents; inner names stay canon; trademark and domain checks before public use.</td><td>Everywhere</td></tr>
      <tr><td class="v">R7</td><td><b>The Safe topology is deferred</b>: a separate technical Safe later, not a blocker, not to be re-raised. Instead: every role transferable by a two-step handover, the technical role split from the issuer role.</td><td>Part D §3b, Part E §5</td></tr>
      <tr><td class="v">R8</td><td><b>No custodians, banks or transfer agents today – but ready for them by design.</b> One factory whose tokens meet institutional requirements without re-architecture; a hook per tomorrow's party now, the partner when it comes. Sequence: concept and know-how → uRWA Factory → tokens. First client STBX, operated by Gene alone.</td><td>Part D §3</td></tr>
      <tr><td class="v">R9</td><td><b>Start soon</b>; the team to be named. The roadmap runs from the day the team is named.</td><td>Part G</td></tr>
      <tr><td class="v">R10</td><td><b>A-05 and the Board as recommended</b>: institutional hooks design-only in Phase 2 and built in Phases 4–5; the Board with a display-only fallback if the perimeter opinion is late.</td><td>Part G</td></tr>
      <tr><td class="v">R11</td><td><b>Assurance on demand.</b> No money on an external audit, an auditor or any paid assurance now – "we spend nothing now". The internal adversarial audit plus formal verification with free tooling is the launch gate; an external audit when a client or a regulator asks.</td><td>Part F §6, Part G Phase 3</td></tr>
      <tr><td class="v">R12</td><td><b>Fees.</b> Stobox charges no bps and no transaction fee today and the bps row stays out of the price list – but the infrastructure must be able to charge, because clients, or Stobox under a future regulation, will. A configurable fee policy per token and per Board, flat or bps, recipient named, zero by default.</td><td>Part E §14, Part G Phase 0</td></tr>
    </tbody>
  </table>
  </div>
</section>
'''


def gantt():
    # weeks from the day the team is named
    W = 40
    x0, x1 = 250, 1160
    wx = lambda w: x0 + (x1 - x0) * w / W
    rows = [
        ('0 · Foundation', 'money paths · roles · delay · emergency · fee policy', 0, 4, 'p0'),
        ('1a · Identity and evidence', 'registry · DID migration · events · invariants · auditor pack', 4, 10, 'crit'),
        ('1b · Data and operations', 'attestors · oracle · identifiers · monitoring', 4, 8, 'par'),
        ('2 · Market, migration, counsel', 'MigrationClaim · Board · presets · counsel package', 10, 15, 'crit'),
        ('3 · Assurance and launch', 'freeze · internal audit · verification · STBX on Base', 15, 20, 'crit'),
        ('4 · Corporate actions and terms', 'payout · consent · ROFR · passport · ISO 20022', 20, 28, 'later'),
        ('5 · Connectors and agents', 'Eqvista · Xero · Plaid · AgentAuthority · MCP', 28, 36, 'later'),
        ('6 · Institutional operation', 'partner-gated', 36, 40, 'gate'),
    ]
    y0, rh = 60, 56
    H = y0 + rh * len(rows) + 30
    s = [f'<svg viewBox="0 0 1180 {H}" role="img" aria-labelledby="gantt-t"><title id="gantt-t">Roadmap by week from the day the team is named</title>']
    for w in range(0, W + 1, 4):
        s.append(f'<line class="grid" x1="{wx(w):.0f}" y1="{y0-14}" x2="{wx(w):.0f}" y2="{H-24}"/>')
        s.append(f'<text class="wk" x="{wx(w):.0f}" y="{y0-20}" text-anchor="middle">W{w}</text>')
    for i, (name, sub, a, b, cls) in enumerate(rows):
        y = y0 + i * rh
        s.append(f'<text class="lbl" x="0" y="{y+19}">{name}</text>')
        s.append(f'<rect class="bar {cls}" x="{wx(a):.0f}" y="{y+2}" width="{wx(b)-wx(a):.0f}" height="26" rx="6"/>')
        s.append(f'<text class="sub" x="{wx(a):.0f}" y="{y+42}">{sub}</text>')
    ms = [(0, 'team named · start'), (10, 'counsel deadline'), (15, 'code freeze'), (20, 'STBX on Base')]
    for w, l in ms:
        s.append(f'<line class="ms" x1="{wx(w):.0f}" y1="{y0-6}" x2="{wx(w):.0f}" y2="{H-24}"/>')
        s.append(f'<text class="msl" x="{wx(w)+4:.0f}" y="{H-8}">{l}</text>')
    s.append('</svg>')
    return '\n'.join(s)


ROADMAP_INTRO = f'''
<section aria-labelledby="rm-h">
  <div class="head">
    <span class="kicker">G0 · Roadmap</span>
    <h2 id="rm-h">Eight phases on one line, from the day the team is named</h2>
    <p class="prose">The critical path is 0 → 1a → 2 → 3: <b>18–21 weeks</b> with two Solidity engineers and one full-stack engineer, STBX on Base in week 20. Phase 1b runs beside 1a; Phases 4–6 follow launch and are not on STBX's path. With one engineer the same phases take about twice as long. Weeks count from the day Gene names the team (ruling R9); if that day is 06.10.2026, freeze falls in mid-January and STBX lands on Base in February 2027. Nothing on this line costs money beyond salaries: no external audit, no paid tooling, no registrations before a client asks (R11).</p>
  </div>
  <figure class="gantt">
    <div class="scroll">{gantt()}</div>
    <figcaption>Solid blue: the critical path. Red: Phase 0, where everything in the immutable core becomes final. Dashed amber: parallel work. Dotted violet: after launch. Grey: partner-gated, no date. Milestones: team named, counsel deadline at the end of 1a, code freeze, STBX on Base.</figcaption>
    <p class="hint">Scroll sideways on a phone.</p>
  </figure>
  <div class="four">
    <div class="card"><h3>Phase 0 · weeks 0–4</h3><p>Money paths and roles. Fee policy configurable, zero for Stobox. Two-step role handover. Emergency facet. Everything in the immutable core final.</p></div>
    <div class="card"><h3>Phases 1a + 1b · weeks 4–10</h3><p>The identity registry and the DID migration; the oracle with attestors; events and invariants; the auditor pack; monitoring and runbooks.</p></div>
    <div class="card"><h3>Phase 2 · weeks 10–15</h3><p>Migration claim, Compass Board, binding regime presets, institutional hooks as interfaces, and the counsel package that must exist before launch.</p></div>
    <div class="card"><h3>Phase 3 · weeks 15–20</h3><p>Freeze, internal adversarial audit, formal verification, STBX paused on Arbitrum, issued on Base, claims open, Board open.</p></div>
  </div>
  <p class="note">What must come from Gene, and when: the team and the start day (before week 0); the fee policy defaults for STBX and the Board (Phase 0); Merkle claim or voucher and whether the 24-month lock-up lives in code (before Phase 2, after counsel's SPA 5.1 answer); the operations owner after the first third-party issuer (Phase 5).</p>
</section>
'''

# ---------------------------------------------------------------- assemble
S = {p: sections(p) for p in PAGES}


def take(p, ids, part):
    out = []
    for i in ids:
        if i not in S[p]:
            raise SystemExit(f'{p}.html has no section {i}')
        out.append(renumber(prefix_ids(S[p][i], p), part))
    return '\n'.join(out)


def all_but_changelog(p):
    return [i for i in S[p] if i not in ('cl-h', 'dec-h')] + (['dec-h'] if 'dec-h' in S[p] else [])


def part(letter, pid, title, lede):
    return f'''
<div class="part" id="part-{pid}">
  <span class="kicker">Part {letter}</span>
  <h2>{title}</h2>
  <p>{lede}</p>
</div>'''


hub = S['stv4']
body = []
body.append(part('A', 'rulings', 'The rulings', 'The decisions every page below is built on. Nothing here is derived; all of it was said by Gene on 25 September 2026.'))
body.append(RULINGS)

body.append(part('B', 'stv4', 'The system', 'What Stobox Orbit is: every STV3 facet rebuilt on the uRWA Factory on Base, one flow through identity, compliance and the oracle, the four layers on top. Read from the live STBX diamond and from src/.'))
body.append(take('stv4', ['map-h', 'flow-h', 'f-h', 'ly-h'], 'B'))

body.append(part('C', 'layers', 'The four layers', 'Identity, Terms, Offering, Intelligence. Each layer is a page in its own right; here they follow one another, decisions included, so a reader has the whole of every layer before the institutional view.'))
body.append(f'<div class="part" id="part-identity" style="border-top-width:1px;margin-top:64px"><span class="kicker">C · Layer 1</span><h2>Identity</h2><p>One subject-keyed registry on Base; every product reads it; a client\'s own KYC plugs in at one of three levels; privacy by construction.</p></div>')
body.append(take('identity', all_but_changelog('identity'), 'C1.'))
body.append(f'<div class="part" id="part-terms" style="border-top-width:1px;margin-top:64px"><span class="kicker">C · Layer 2</span><h2>Terms</h2><p>From clause to code: the 38 clauses of the STBX paper, each classed enforceable, executable, attested or disclosed; the Terms model on the passport; what agents may read and execute.</p></div>')
body.append(take('terms', all_but_changelog('terms'), 'C2.'))
body.append(f'<div class="part" id="part-offering" style="border-top-width:1px;margin-top:64px"><span class="kicker">C · Layer 3</span><h2>Offering</h2><p>Regimes as binding presets; the contract-to-law table; the role boundary Stobox never crosses; STBX\'s own stack on Base.</p></div>')
body.append(take('offering', all_but_changelog('offering'), 'C3.'))
body.append(f'<div class="part" id="part-intelligence" style="border-top-width:1px;margin-top:64px"><span class="kicker">C · Layer 4</span><h2>Intelligence</h2><p>The record is the source; the oracle attests figures to the chain; agents act within mandates; every client system plugs into the same intake as documents do.</p></div>')
body.append(take('intelligence', all_but_changelog('intelligence'), 'C4.'))

body.append(part('D', 'orbit', 'Institutional readiness', 'The system as a custodian, an auditor, a compliance officer, an enterprise buyer, an infrastructure architect and an asset-class specialist read it – and the hook the Factory carries today for each party that arrives tomorrow.'))
orbit_ids = [i for i in S['orbit'] if i not in ('cl-h', 'dec-h', 'ord-h', 'o-h')]
body.append(take('orbit', orbit_ids + (['dec-h'] if 'dec-h' in S['orbit'] else []), 'D'))

body.append(part('E', 'functions', 'The functions', 'Every principal function of Stobox Orbit, module by module: what exists in src/ today, what changes, what is new, what is dropped. The status is the function\'s, not the module\'s.'))
body.append(take('functions', [i for i in S['functions'] if i != 'cl-h'], 'E'))

body.append(part('F', 'analysis', 'Analysis, gaps and criteria', 'Where the code stands against the design, the gap register G1–G23, and the four levels of acceptance, delivery, audit and enterprise-grade – with assurance on demand as ruled.'))
body.append(take('stv4', ['an-h', 'c-h'], 'F'))

body.append(part('G', 'roadmap', 'The roadmap', 'Eight phases, each with what it builds, when it is accepted and what it delivers; the calendar from the day the team is named; the decisions taken and the ones still open.'))
body.append(ROADMAP_INTRO)
body.append(take('stv4', ['o-h', 'dec-h'], 'G'))

CHANGELOG = f'''
<section aria-labelledby="mcl-h">
  <div class="head"><span class="kicker">Changelog</span><h2 id="mcl-h">Versions of this document</h2></div>
  <div class="tbl"><table>
    <thead><tr><th>Version</th><th>Date</th><th>Change</th></tr></thead>
    <tbody>
      <tr><td class="v">{VERSION}</td><td>{DATE}</td><td>First assembly of the whole of Stobox Orbit on one page, from hub v2.2, Orbit v0.4, Identity / Terms / Offering / Intelligence v0.3 and Functions v0.3, with the rulings register and the roadmap that exist only here. Generated by <code>build-master.py</code>; edit the source pages, then rebuild.</td></tr>
    </tbody>
  </table></div>
</section>
'''
body.append(CHANGELOG)

html_body = '\n'.join(body)

# table of contents from the parts and the h2 of every section
toc = []
for m in re.finditer(r'<div class="part" id="(part-[^"]+)"[^>]*>\s*<span class="kicker">([^<]+)</span>\s*<h2>([^<]+)</h2>', html_body):
    toc.append(f'<li><a href="#{m.group(1)}"><b>{m.group(2)}</b> · {m.group(3)}</a></li>')
TOC = '<nav class="toc" aria-label="Contents"><span class="kicker">Contents</span><ol>' + ''.join(toc) + '</ol></nav>'

# strip page-local "Hub: … siblings: …" meta lines (now in-document)
html_body = re.sub(r'<p class="meta">(Hub|Layers|Product|Companion)[^<]*(<a [^>]*>[^<]*</a>[^<]*)*</p>', '', html_body)

head = src['stv4'][:src['stv4'].index('<style>')].replace('<title>STV4</title>', '<title>Stobox Orbit</title>')

sources = []
for p in PAGES:
    m = re.search(r'<footer>(.*?)</footer>', src[p], re.S)
    if m:
        sources.append(f'<details><summary class="meta">Sources and uncertainties · {p}.html</summary>{m.group(1)}</details>')

doc = f'''{head}<style>{master_css}</style>

<main>
<header>
  <div class="eyebrow">Stobox · internal architecture · the master document · {VERSION} · {DATE}</div>
  <h1>Stobox Orbit</h1>
  <p class="lede">The whole system on one page: the rulings it rests on, the architecture read from the live code and chain, the four layers, the institutional view, every function, every gap, the criteria, and the roadmap from the day the team is named. Seven pages assembled into one so that nothing has to be looked up elsewhere.</p>
  <div class="legend" aria-label="Status legend">
    <span><i class="sw live"></i>Live on chain or in production</span>
    <span><i class="sw ready"></i>Code and tests ready, not deployed</span>
    <span><i class="sw pending"></i>Planned, not built or created yet</span>
    <span><i class="sw gap"></i>Gap: missing, blocks a feature</span>
    <span><i class="sw option"></i>Optional</span>
  </div>
  {TOC}
</header>
{html_body}
<footer>
  <span class="meta">Generated {datetime.date.today().isoformat()} by build-master.py from the seven architecture pages in this folder. Edit the pages, not this file.</span>
  {''.join(sources)}
</footer>
</main>
'''
(HERE / 'stobox-orbit.html').write_text(doc, encoding='utf-8')
ids = re.findall(r'\bid="([^"]+)"', doc)
dup = {i for i in ids if ids.count(i) > 1}
print(f'stobox-orbit.html: {len(doc)//1024} KB, {len(re.findall("<section", doc))} sections, duplicate ids: {sorted(dup) or "none"}')
