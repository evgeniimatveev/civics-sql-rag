"""Static checks, standard library only (no network, no Cloudflare).

* the Python scripts compile (warnings are errors)
* worker/rag/corpus.jsonl is valid: every line is JSON with id, source, category, text; ids unique; categories civics | sql
* the committed corpus is exactly what build_corpus.py produces from civics_128_qa.md and sql/*.sql (nobody forgot to rebuild)
* there are 128 civics chunks (one per official question, q1..q128)
* the chunk count written in the README diagram equals the real number of chunks
* README links that point into this repository lead to existing files
"""
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import urllib.parse
import warnings

problems = []
tracked = [t.strip('"') for t in subprocess.run(["git", "ls-files"], capture_output=True, text=True, check=True, encoding="utf-8").stdout.splitlines()]

warnings.simplefilter("error", SyntaxWarning)
for f in sorted(t for t in tracked if t.endswith(".py")):
    with open(f, encoding="utf-8") as fh:
        try:
            compile(fh.read(), f, "exec")
        except (SyntaxError, SyntaxWarning) as exc:
            problems.append(f"{f}: does not compile: {exc}")

CORPUS = "worker/rag/corpus.jsonl"
with open(CORPUS, encoding="utf-8") as fh:
    raw_lines = [l for l in fh.read().replace("\r\n", "\n").split("\n") if l.strip()]
rows = []
for i, line in enumerate(raw_lines, 1):
    try:
        row = json.loads(line)
    except json.JSONDecodeError as exc:
        problems.append(f"{CORPUS}:{i}: not valid JSON: {exc}")
        continue
    rows.append(row)
    if set(row) != {"id", "source", "category", "text"}:
        problems.append(f"{CORPUS}:{i}: unexpected keys {sorted(row)}")
    if row.get("category") not in ("civics", "sql"):
        problems.append(f"{CORPUS}:{i}: category is {row.get('category')!r}")
    if not str(row.get("text", "")).strip():
        problems.append(f"{CORPUS}:{i}: empty text")
ids = [r.get("id") for r in rows]
if len(ids) != len(set(ids)):
    problems.append("corpus ids are not unique")
civics = [r for r in rows if r.get("category") == "civics"]
if sorted(r["id"] for r in civics) != sorted(f"civics:q{n}" for n in range(1, 129)):
    problems.append(f"civics chunks are not exactly q1..q128 ({len(civics)} found)")

# the corpus must be reproducible from its sources
tmp = tempfile.mkdtemp()
try:
    shutil.copytree("worker/rag", os.path.join(tmp, "rag"))
    subprocess.run([sys.executable, os.path.join(tmp, "rag", "build_corpus.py")], check=True, capture_output=True)
    with open(os.path.join(tmp, "rag", "corpus.jsonl"), encoding="utf-8") as fh:
        rebuilt = [l for l in fh.read().replace("\r\n", "\n").split("\n") if l.strip()]
    if rebuilt != raw_lines:
        problems.append("corpus.jsonl differs from what build_corpus.py produces: rebuild and commit it")
finally:
    shutil.rmtree(tmp, ignore_errors=True)

with open("README.md", encoding="utf-8") as fh:
    readme = fh.read()
for n in re.findall(r"(\d+) chunks", readme):
    if int(n) != len(rows):
        problems.append(f"README says {n} chunks, the corpus has {len(rows)}")
n_links = 0
for target in re.findall(r"\]\(((?:[^()\s]|\([^)]*\))+)\)", readme):
    if re.match(r"^(https?:|#|mailto:)", target):
        continue
    n_links += 1
    if urllib.parse.unquote(target.split("#")[0]) not in tracked:
        problems.append(f"README: link to a missing file: {target}")

print(f"Checked {len(rows)} chunks ({len(civics)} civics, {len(rows) - len(civics)} sql), the rebuild, README figures and {n_links} links; {len(problems)} problem(s)")
for p in problems:
    print("FAIL ", p)
sys.exit(1 if problems else 0)
