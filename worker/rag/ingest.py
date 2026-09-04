"""
Reads corpus.jsonl and POSTs it in batches to the Worker's /admin/ingest route,
which embeds each chunk via Workers AI and upserts it into Vectorize.

Re-runnable: upsert by id, so patching in new SQL sessions later (session_03,
session_04...) just means adding the file, rerunning build_corpus.py, and
rerunning this script — existing chunks are untouched, new ones get added.

Usage:
    ADMIN_KEY=... python ingest.py
"""

import json
import os
import sys
import time
import urllib.request

WORKER_URL = "https://evgeniimatveev-civics-sql.evgeniimatveevusa.workers.dev/admin/ingest"
CORPUS_FILE = os.path.join(os.path.dirname(__file__), "corpus.jsonl")
BATCH_SIZE = 10


def load_chunks():
    chunks = []
    with open(CORPUS_FILE, encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line:
                chunks.append(json.loads(line))
    return chunks


def post_batch(batch, admin_key):
    payload = json.dumps({"chunks": batch}).encode("utf-8")
    req = urllib.request.Request(
        WORKER_URL,
        data=payload,
        headers={
            "Content-Type": "application/json",
            "X-Admin-Key": admin_key,
            "User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64)",
        },
        method="POST",
    )
    with urllib.request.urlopen(req, timeout=60) as resp:
        return json.loads(resp.read().decode("utf-8"))


def main():
    admin_key = os.environ.get("ADMIN_KEY")
    if not admin_key:
        print("Set ADMIN_KEY env var first.", file=sys.stderr)
        sys.exit(1)

    chunks = load_chunks()
    print(f"Loaded {len(chunks)} chunks.")

    total_upserted = 0
    for i in range(0, len(chunks), BATCH_SIZE):
        batch = chunks[i : i + BATCH_SIZE]
        try:
            result = post_batch(batch, admin_key)
            total_upserted += result.get("upserted", 0)
            print(f"[{i + len(batch)}/{len(chunks)}] upserted={result.get('upserted')}")
        except Exception as e:
            print(f"[{i + len(batch)}/{len(chunks)}] FAILED: {e}", file=sys.stderr)
        time.sleep(0.3)

    print(f"Done. Total upserted: {total_upserted}")


if __name__ == "__main__":
    main()
