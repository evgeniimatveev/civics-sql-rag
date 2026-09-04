"""
Builds corpus.jsonl for the civics/SQL practice RAG bot.

Two very different chunking strategies on purpose — this is the practical
lesson of this project: the right chunk boundary is whatever unit is already
semantically atomic in the source, not a fixed word/token count.

Civics (civics_128_qa.md): each numbered question + its answer choices is
already a complete, self-contained fact. One question = one chunk. Splitting
further would separate a question from its own answer (useless); merging
multiple questions would dilute the embedding with unrelated facts and hurt
retrieval precision for a specific question.

SQL (session_*.sql): each "-- LESSON N: <title>" block is a complete
concept — a rule, an example query, and often a real mistake + correction
(see session_02, Lesson 4: the timezone double-conversion bug). Splitting a
lesson mid-explanation would separate the bug from its fix.

Every chunk carries `category` (civics | sql) so the Worker can filter
Vectorize queries by mode instead of retrieving across both corpora.
"""

import json
import re
from pathlib import Path

RAG_DIR = Path(__file__).parent
CIVICS_FILE = RAG_DIR / "civics" / "civics_128_qa.md"
SQL_DIR = RAG_DIR / "sql"
OUT_FILE = RAG_DIR / "corpus.jsonl"


def build_civics_chunks():
    text = CIVICS_FILE.read_text(encoding="utf-8")
    lines = text.split("\n")

    chunks = []
    category = None       # e.g. "AMERICAN GOVERNMENT"
    subcategory = None     # e.g. "A: Principles of American Government"
    current_q = None
    current_lines = []

    def flush():
        if current_q is not None and current_lines:
            body = "\n".join(current_lines).strip()
            chunks.append({
                "id": f"civics:q{current_q}",
                "source": "USCIS 2025 Civics Test (M-1778)",
                "category": "civics",
                "text": f"[{category} — {subcategory}]\n{body}",
            })

    for line in lines:
        stripped = line.strip()
        if stripped.startswith("## "):
            flush()
            current_q, current_lines = None, []
            category = stripped[3:].strip()
            continue
        if stripped.startswith("### "):
            flush()
            current_q, current_lines = None, []
            subcategory = stripped[4:].strip()
            continue
        m = re.match(r"^(\d+)\.\s+(.*)$", stripped)
        if m:
            flush()
            current_q = int(m.group(1))
            current_lines = [stripped]
            continue
        if stripped and current_q is not None:
            current_lines.append(stripped)
    flush()

    return chunks


def clean_sql_comment_noise(text: str) -> str:
    # Strip the box-drawing / "====" divider lines — pure visual noise for
    # an embedding model, they carry no semantic content.
    text = re.sub(r"^--\s*[─=]{5,}\s*$", "", text, flags=re.MULTILINE)
    text = re.sub(r"\n{3,}", "\n\n", text)
    return text.strip()


def build_sql_chunks():
    chunks = []
    for sql_file in sorted(SQL_DIR.glob("*.sql")):
        raw = sql_file.read_text(encoding="utf-8")
        # Split right before every lesson header; keep the header with its block.
        parts = re.split(r"\n(?=-- LESSON \d+)", raw)
        for part in parts:
            if not part.strip().startswith("-- LESSON"):
                continue
            m = re.match(r"-- LESSON (\d+):\s*(.+)", part.strip())
            lesson_num = m.group(1) if m else "?"
            lesson_title = m.group(2).strip() if m else "untitled"
            cleaned = clean_sql_comment_noise(part)
            if len(cleaned.split()) < 15:
                continue
            chunks.append({
                "id": f"sql:{sql_file.stem}:lesson{lesson_num}",
                "source": f"sql_practice/{sql_file.name}",
                "category": "sql",
                "text": cleaned[:3000],
            })
    return chunks


def main():
    records = build_civics_chunks() + build_sql_chunks()
    with OUT_FILE.open("w", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    civics_n = sum(1 for r in records if r["category"] == "civics")
    sql_n = sum(1 for r in records if r["category"] == "sql")
    print(f"Wrote {len(records)} chunks to {OUT_FILE} ({civics_n} civics, {sql_n} sql)")


if __name__ == "__main__":
    main()
