# civics × sql — RAG practice lab

A small, real RAG (Retrieval-Augmented Generation) system built to practice the
mechanics hands-on — not a tutorial toy, an actual Cloudflare Worker answering
real questions against real embedded content.

**Live demo:** see `index.html` (deploy via GitHub Pages, or open locally against the deployed Worker).

## What it does

Two modes over one Vectorize index, separated by metadata filtering:

- **Civics** — grounded in all 128 official USCIS 2025 naturalization test questions (M-1778)
- **SQL** — grounded in real hands-on SQL practice sessions, including real mistakes and their fixes (e.g. a timezone double-conversion bug caught mid-session)

Ask a question in any mode, in any language — it retrieves the most relevant
chunks by embedding similarity, then Claude Haiku 4.5 answers strictly from
that retrieved context (not from the model's general knowledge).

## Stack

| Layer | Tech |
|---|---|
| Embeddings | `@cf/baai/bge-m3` via Cloudflare Workers AI (1024-dim, multilingual) |
| Vector store | Cloudflare Vectorize (cosine similarity, metadata-filtered by `category`) |
| Generation | Claude Haiku 4.5 (Anthropic API) |
| Backend | Cloudflare Worker (`worker/worker.js`) |
| Rate limiting | Cloudflare KV (per-IP + global daily caps) |
| Frontend | Static HTML/JS (`index.html`) |

## Why this project exists

Built specifically to turn RAG from a memorized concept ("vector DB + chunks")
into hands-on intuition: chunking strategy, metadata filtering pitfalls
(Vectorize silently returns zero matches on an unindexed metadata field —
`wrangler vectorize create-metadata-index` is required before `filter` works),
retrieval score tuning (`MIN_SCORE` threshold), and how chunk *boundaries*
matter more than chunk *size* (each civics chunk = one question; each SQL
chunk = one complete lesson, never split mid-explanation).

## Repo layout

```
worker/
  worker.js              # Cloudflare Worker: /ask, /admin/ingest, /admin/debug-query, /stats
  wrangler.toml          # bindings: KV (rate limit), Vectorize, Workers AI
  rag/
    build_corpus.py      # civics_128_qa.md + sql/*.sql -> corpus.jsonl
    ingest.py            # POSTs corpus.jsonl to /admin/ingest (embeds + upserts)
    corpus.jsonl         # generated — chunked, tagged {id, source, category, text}
    civics/civics_128_qa.md
    sql/session_*.sql    # real practice sessions, added incrementally
index.html               # frontend
```

## Growing the corpus

The SQL side is meant to grow as practice continues (JOINs, subqueries,
window functions...). To add a new session:

1. Drop `session_0N_topic.sql` into `worker/rag/sql/`, following the existing
   `-- LESSON N: <title>` header convention.
2. `python worker/rag/build_corpus.py` — regenerates `corpus.jsonl` (idempotent, existing ids untouched).
3. `ADMIN_KEY=... python worker/rag/ingest.py` — upserts only what changed.

## Deploy

```
cd worker
npx wrangler deploy
npx wrangler secret put ADMIN_KEY
npx wrangler secret put ANTHROPIC_API_KEY
```

Vectorize requires an explicit metadata index before `filter` queries work:

```
npx wrangler vectorize create-metadata-index civics-sql-corpus-m3 --property-name=category --type=string
```
