#!/usr/bin/env python3
"""Parity comparator: native extractor outputs vs the Dart v2 goldens.

Exit code 0 only on full parity — usable as a CI gate.
"""
import argparse
import html
import json
import subprocess
from datetime import datetime, timezone
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
GOLDENS = REPO / "goldens" / "substitution"

ap = argparse.ArgumentParser(description="Compare native extractor outputs against the Dart v2 goldens")
ap.add_argument("kotlin_dir", nargs="?", help="dir with Kotlin extractor *.json output")
ap.add_argument("--kotlin", dest="kotlin_opt", help="same as positional kotlin_dir")
ap.add_argument("--swift", help="dir with Swift extractor *.json output")
ap.add_argument("--out", default="report.html", help="output HTML path (default ./report.html)")
args = ap.parse_args()

IMPLS = {}
if args.kotlin_dir or args.kotlin_opt:
    IMPLS["Kotlin"] = Path(args.kotlin_dir or args.kotlin_opt)
if args.swift:
    IMPLS["Swift"] = Path(args.swift)
if not IMPLS:
    ap.error("provide at least one of: kotlin_dir, --kotlin, --swift")
OUT = Path(args.out)


def diff(path, golden, actual, out):
    """Recursive semantic diff; collects (path, golden, actual) rows."""
    if isinstance(golden, dict) and isinstance(actual, dict):
        for k in sorted(set(golden) | set(actual)):
            diff(f"{path}.{k}" if path else k,
                 golden.get(k, "<missing>"), actual.get(k, "<missing>"), out)
    elif isinstance(golden, list) and isinstance(actual, list):
        if len(golden) != len(actual):
            out.append((f"{path}.length", len(golden), len(actual)))
        for i, (g, a) in enumerate(zip(golden, actual)):
            diff(f"{path}[{i}]", g, a, out)
    elif golden != actual:
        out.append((path, golden, actual))


def jshow(v):
    return html.escape(json.dumps(v, ensure_ascii=False))


fixtures = sorted(p.name.replace(".v2.json", "")
                  for p in GOLDENS.glob("*.v2.json"))
results = {}  # fixture -> impl -> (ok, diffs, actual_json)
for fx in fixtures:
    golden = json.loads((GOLDENS / f"{fx}.v2.json").read_text())["expected"]
    results[fx] = {"golden": golden, "impls": {}}
    for impl, outdir in IMPLS.items():
        f = outdir / f"{fx}.json"
        if not f.exists():
            results[fx]["impls"][impl] = (False, [("<output>", "file", "missing")], None)
            continue
        actual = json.loads(f.read_text())
        diffs = []
        diff("", golden, actual, diffs)
        results[fx]["impls"][impl] = (not diffs, diffs, actual)

total = {impl: sum(1 for fx in fixtures if results[fx]["impls"][impl][0])
         for impl in IMPLS}
all_green = all(total[i] == len(fixtures) for i in IMPLS)

try:
    commit = subprocess.run(
        ["git", "-C", str(REPO), "rev-parse", "--short", "HEAD"],
        capture_output=True, text=True).stdout.strip()
except OSError:
    commit = "?"

now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%M UTC")

rows = []
for fx in fixtures:
    cells = "".join(
        f'<td><span class="chip {"pass" if results[fx]["impls"][i][0] else "fail"}">'
        f'{"MATCH" if results[fx]["impls"][i][0] else str(len(results[fx]["impls"][i][1])) + " diffs"}'
        f"</span></td>"
        for i in IMPLS)
    rows.append(f'<tr><td class="fx"><a href="#{fx}">{fx}</a></td>{cells}</tr>')

sections = []
for fx in fixtures:
    impl_blocks = []
    for impl in IMPLS:
        ok, diffs, actual = results[fx]["impls"][impl]
        if ok:
            impl_blocks.append(
                f'<div class="impl"><h4>{impl} <span class="chip pass">MATCH</span></h4></div>')
            continue
        drows = "".join(
            f"<tr><td class='path'>{html.escape(str(p))}</td>"
            f"<td class='want'>{jshow(g)}</td><td class='got'>{jshow(a)}</td></tr>"
            for p, g, a in diffs[:60])
        more = f"<p class='more'>… {len(diffs) - 60} more</p>" if len(diffs) > 60 else ""
        actual_json = (html.escape(json.dumps(actual, ensure_ascii=False, indent=2))
                       if actual is not None else "<no output>")
        impl_blocks.append(f"""
        <div class="impl">
          <h4>{impl} <span class="chip fail">{len(diffs)} diffs</span></h4>
          <div class="tablewrap"><table class="diffs">
            <thead><tr><th>path</th><th>golden</th><th>{impl.lower()}</th></tr></thead>
            <tbody>{drows}</tbody>
          </table></div>{more}
          <details><summary>full {impl} output</summary><pre>{actual_json}</pre></details>
        </div>""")
    golden_json = html.escape(json.dumps(results[fx]["golden"], ensure_ascii=False, indent=2))
    sections.append(f"""
    <section id="{fx}">
      <h3>{fx}</h3>
      {''.join(impl_blocks)}
      <details><summary>golden (Dart reference)</summary><pre>{golden_json}</pre></details>
    </section>""")

verdict = ('<span class="chip pass big">ALL GREEN — FULL PARITY</span>' if all_green
           else '<span class="chip fail big">DIFFS REMAIN</span>')

OUT.parent.mkdir(exist_ok=True)
OUT.write_text(f"""<title>LGKA Extractor Parity</title>
<style>
:root {{
  --bg: #FAFBFC; --ink: #1B2530; --muted: #5B6875; --line: #D8DEE4;
  --accent: #0E7C7B; --card: #FFFFFF;
  --pass-bg: #E4F2E9; --pass-ink: #22643A; --fail-bg: #F9E4E4; --fail-ink: #A33232;
}}
@media (prefers-color-scheme: dark) {{ :root {{
  --bg: #14181D; --ink: #E6EBF0; --muted: #8B98A5; --line: #2A323B;
  --accent: #3FB5B4; --card: #1B2129;
  --pass-bg: #1C3627; --pass-ink: #7DD09A; --fail-bg: #402124; --fail-ink: #E58A8A;
}} }}
:root[data-theme="light"] {{
  --bg: #FAFBFC; --ink: #1B2530; --muted: #5B6875; --line: #D8DEE4;
  --accent: #0E7C7B; --card: #FFFFFF;
  --pass-bg: #E4F2E9; --pass-ink: #22643A; --fail-bg: #F9E4E4; --fail-ink: #A33232;
}}
:root[data-theme="dark"] {{
  --bg: #14181D; --ink: #E6EBF0; --muted: #8B98A5; --line: #2A323B;
  --accent: #3FB5B4; --card: #1B2129;
  --pass-bg: #1C3627; --pass-ink: #7DD09A; --fail-bg: #402124; --fail-ink: #E58A8A;
}}
body {{ background: var(--bg); color: var(--ink); margin: 0;
  font: 15px/1.55 system-ui, -apple-system, sans-serif; }}
main {{ max-width: 60rem; margin: 0 auto; padding: 2.5rem 1.25rem 5rem; }}
h1 {{ font-size: 1.5rem; margin: 0 0 .25rem; letter-spacing: -.01em; }}
h1 em {{ color: var(--accent); font-style: normal; }}
.meta {{ color: var(--muted); font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: .8rem; margin-bottom: 2rem; }}
.chip {{ display: inline-block; padding: .1rem .55rem; border-radius: 999px;
  font: 600 .72rem/1.5 ui-monospace, SFMono-Regular, Menlo, monospace;
  letter-spacing: .04em; vertical-align: middle; }}
.chip.big {{ font-size: .85rem; padding: .25rem .8rem; }}
.pass {{ background: var(--pass-bg); color: var(--pass-ink); }}
.fail {{ background: var(--fail-bg); color: var(--fail-ink); }}
table {{ border-collapse: collapse; width: 100%; }}
.summary td, .summary th {{ padding: .5rem .75rem; border-bottom: 1px solid var(--line);
  text-align: left; }}
.summary th {{ color: var(--muted); font-size: .72rem; text-transform: uppercase;
  letter-spacing: .08em; }}
.fx a {{ color: var(--accent); text-decoration: none;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .85rem; }}
section {{ margin-top: 3rem; border-top: 2px solid var(--accent); padding-top: 1rem; }}
section h3 {{ font-family: ui-monospace, SFMono-Regular, Menlo, monospace;
  font-size: .95rem; margin: 0 0 1rem; }}
.impl h4 {{ margin: 1.25rem 0 .5rem; font-size: .9rem; }}
.tablewrap {{ overflow-x: auto; border: 1px solid var(--line); border-radius: 6px; }}
.diffs td, .diffs th {{ padding: .35rem .6rem; border-bottom: 1px solid var(--line);
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace; font-size: .78rem;
  text-align: left; vertical-align: top; white-space: pre-wrap; }}
.diffs th {{ color: var(--muted); text-transform: uppercase; font-size: .68rem;
  letter-spacing: .08em; }}
.diffs tr:last-child td {{ border-bottom: none; }}
.path {{ color: var(--accent); }}
.want {{ color: var(--pass-ink); }}
.got {{ color: var(--fail-ink); }}
details {{ margin: .75rem 0; }}
summary {{ cursor: pointer; color: var(--muted); font-size: .8rem;
  font-family: ui-monospace, SFMono-Regular, Menlo, monospace; }}
pre {{ background: var(--card); border: 1px solid var(--line); border-radius: 6px;
  padding: 1rem; overflow-x: auto; font-size: .75rem; line-height: 1.5; }}
.more {{ color: var(--muted); font-size: .8rem; }}
</style>
<main>
<h1>LGKA <em>extractor parity</em> — Kotlin &amp; Swift vs Dart goldens</h1>
<p class="meta">generated {now} · goldens @ {commit} · {len(fixtures)} substitution fixtures</p>
<p>{verdict}</p>
<div class="tablewrap"><table class="summary">
  <thead><tr><th>fixture</th>{''.join(f'<th>{i} ({total[i]}/{len(fixtures)})</th>' for i in IMPLS)}</tr></thead>
  <tbody>{''.join(rows)}</tbody>
</table></div>
{''.join(sections)}
</main>
""")
print(f"report: {OUT}")
for impl in IMPLS:
    print(f"{impl}: {total[impl]}/{len(fixtures)} fixtures match")

import sys
sys.exit(0 if all_green else 1)
