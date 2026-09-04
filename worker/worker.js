// Cloudflare Worker — civics/SQL practice RAG bot.
// Two modes over ONE Vectorize index, separated by a `category` metadata
// filter (civics | sql) instead of two separate indexes — same embedding
// model, same corpus mechanics, cheaper to operate, and it's the more
// realistic pattern (most real RAG systems partition one index by metadata
// rather than standing up a new index per topic).
// Deploy: see README.md

const ALLOWED_ORIGIN = "*"; // personal practice tool, not gated to one site yet
const IP_DAILY_LIMIT = 30;
const GLOBAL_DAILY_LIMIT = 300;
const KV_TTL_SECONDS = 172800; // 2 days — safe buffer past the UTC day boundary
const TOTAL_KEY = "total:questions";

const EMBEDDING_MODEL = "@cf/baai/bge-m3";
const TOP_K = 5;
const MIN_SCORE = 0.3; // below this, a retrieved chunk is probably irrelevant noise

const MODES = {
  civics: {
    identity: `You are a patient USCIS N-400 naturalization interview coach. Answer using ONLY the CONTEXT below, which is retrieved from the official 2025 civics test (128 questions, M-1778). Give the direct answer first, then one sentence of plain-language context if it helps memory. If the question isn't covered by the context, say so and suggest asking about one of the 128 official topics instead. Keep answers short — this mirrors how the actual USCIS interview works. Match the language of the question.`,
  },
  sql: {
    identity: `You are a SQL practice tutor. Answer using ONLY the CONTEXT below, which is retrieved from real hands-on SQL practice sessions (real dataset, real mistakes, real fixes). When the context includes a mistake + correction (like a timezone bug), explain both — what went wrong and why the fix works, not just the final answer. If the question isn't covered by the context yet, say this topic hasn't been practiced yet. Match the language of the question.`,
  },
};

function corsHeaders() {
  return {
    "Access-Control-Allow-Origin": ALLOWED_ORIGIN,
    "Access-Control-Allow-Methods": "GET, POST, OPTIONS",
    "Access-Control-Allow-Headers": "Content-Type, X-Admin-Key",
  };
}

function json(body, status, headers) {
  return new Response(JSON.stringify(body), {
    status: status || 200,
    headers: Object.assign({ "Content-Type": "application/json" }, headers || {}),
  });
}

function detectScriptHint(text) {
  if (/[一-鿿]/.test(text)) return "Reply in Chinese.";
  if (/[぀-ヿ]/.test(text)) return "Reply in Japanese.";
  if (/[Ѐ-ӿ]/.test(text)) return "Reply in Russian.";
  if (/[؀-ۿ]/.test(text)) return "Reply in Arabic.";
  return null;
}

async function embed(env, text) {
  const res = await env.AI.run(EMBEDDING_MODEL, { text: [text] });
  return res.data[0];
}

async function handleAsk(request, env, ctx, cors) {
  let body;
  try {
    body = await request.json();
  } catch (e) {
    return json({ error: "bad_request" }, 400, cors);
  }

  const question = (body && body.question ? String(body.question) : "").trim().slice(0, 300);
  const mode = MODES[body && body.mode] ? body.mode : null;
  if (!question) return json({ error: "empty_question" }, 400, cors);
  if (!mode) return json({ error: "invalid_mode", allowed: Object.keys(MODES) }, 400, cors);

  const ip = request.headers.get("CF-Connecting-IP") || "unknown";
  const today = new Date().toISOString().slice(0, 10);
  const ipKey = `ip:${ip}:${today}`;
  const globalKey = `global:${today}`;

  const [ipCountStr, globalCountStr, totalCountStr] = await Promise.all([
    env.RATE_LIMIT.get(ipKey),
    env.RATE_LIMIT.get(globalKey),
    env.RATE_LIMIT.get(TOTAL_KEY),
  ]);
  const ipCount = parseInt(ipCountStr || "0", 10);
  const globalCount = parseInt(globalCountStr || "0", 10);
  const totalCount = parseInt(totalCountStr || "0", 10);

  if (ipCount >= IP_DAILY_LIMIT) return json({ error: "rate_limited", scope: "ip" }, 429, cors);
  if (globalCount >= GLOBAL_DAILY_LIMIT) return json({ error: "rate_limited", scope: "global" }, 429, cors);

  // --- Retrieval, filtered to this mode's category ---
  let contextBlock = "";
  let debugMatches = [];
  try {
    const queryVector = await embed(env, question);
    const matches = await env.VECTORIZE.query(queryVector, {
      topK: TOP_K,
      returnMetadata: true,
      filter: { category: mode },
    });
    const relevant = (matches.matches || []).filter((m) => m.score >= MIN_SCORE);
    debugMatches = relevant.map((m) => ({ id: m.id, score: m.score }));
    if (relevant.length > 0) {
      contextBlock = relevant
        .map((m) => `[source: ${m.metadata.source}]\n${m.metadata.text}`)
        .join("\n\n");
    }
  } catch (e) {
    contextBlock = "";
  }

  const systemPrompt = contextBlock
    ? `${MODES[mode].identity}\n\nCONTEXT:\n${contextBlock}`
    : `${MODES[mode].identity}\n\n(No relevant context was retrieved for this question.)`;

  const scriptHint = detectScriptHint(question);
  const userContent = scriptHint ? `[${scriptHint}]\n\n${question}` : question;

  let anthropicRes;
  try {
    anthropicRes = await fetch("https://api.anthropic.com/v1/messages", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "x-api-key": env.ANTHROPIC_API_KEY,
        "anthropic-version": "2023-06-01",
      },
      body: JSON.stringify({
        model: "claude-haiku-4-5",
        max_tokens: 500,
        temperature: 0,
        system: systemPrompt,
        messages: [{ role: "user", content: userContent }],
      }),
    });
  } catch (e) {
    return json({ error: "upstream_unreachable" }, 502, cors);
  }

  if (!anthropicRes.ok) return json({ error: "upstream_error" }, 502, cors);

  const data = await anthropicRes.json();
  const answer = (data.content || [])
    .filter((b) => b.type === "text")
    .map((b) => b.text)
    .join("")
    .trim();

  const newTotal = totalCount + 1;
  ctx.waitUntil(
    Promise.allSettled([
      env.RATE_LIMIT.put(ipKey, String(ipCount + 1), { expirationTtl: KV_TTL_SECONDS }),
      env.RATE_LIMIT.put(globalKey, String(globalCount + 1), { expirationTtl: KV_TTL_SECONDS }),
      env.RATE_LIMIT.put(TOTAL_KEY, String(newTotal)),
    ])
  );

  return json({ answer, mode, total: newTotal, retrieved: debugMatches.length }, 200, cors);
}

// One-off / re-runnable ingestion endpoint. Body: { chunks: [{id, source, category, text}] }
async function handleIngest(request, env, cors) {
  const adminKey = request.headers.get("X-Admin-Key") || "";
  if (!env.ADMIN_KEY || adminKey !== env.ADMIN_KEY) return json({ error: "forbidden" }, 403, cors);

  let body;
  try {
    body = await request.json();
  } catch (e) {
    return json({ error: "bad_request" }, 400, cors);
  }

  const chunks = Array.isArray(body.chunks) ? body.chunks : [];
  if (chunks.length === 0) return json({ error: "no_chunks" }, 400, cors);

  const vectors = [];
  for (const chunk of chunks) {
    const vec = await embed(env, chunk.text);
    vectors.push({
      id: chunk.id,
      values: vec,
      metadata: { source: chunk.source, category: chunk.category, text: chunk.text },
    });
  }

  await env.VECTORIZE.upsert(vectors);
  return json({ upserted: vectors.length }, 200, cors);
}

// Debug route — inspect retrieval quality without a generation call.
async function handleDebugQuery(request, env, cors) {
  const adminKey = request.headers.get("X-Admin-Key") || "";
  if (!env.ADMIN_KEY || adminKey !== env.ADMIN_KEY) return json({ error: "forbidden" }, 403, cors);

  let body;
  try {
    body = await request.json();
  } catch (e) {
    return json({ error: "bad_request" }, 400, cors);
  }
  const question = (body && body.question ? String(body.question) : "").trim();
  const mode = MODES[body && body.mode] ? body.mode : null;
  if (!question) return json({ error: "empty_question" }, 400, cors);

  const queryVector = await embed(env, question);
  const queryOpts = { topK: 10, returnMetadata: true };
  if (mode) queryOpts.filter = { category: mode };
  const matches = await env.VECTORIZE.query(queryVector, queryOpts);
  return json(
    {
      matches: (matches.matches || []).map((m) => ({
        id: m.id,
        score: m.score,
        category: m.metadata.category,
        source: m.metadata.source,
        text: m.metadata.text.slice(0, 200),
      })),
    },
    200,
    cors
  );
}

export default {
  async fetch(request, env, ctx) {
    const cors = corsHeaders();
    const url = new URL(request.url);

    if (request.method === "OPTIONS") return new Response(null, { headers: cors });

    if (request.method === "GET" && url.pathname === "/stats") {
      const totalStr = await env.RATE_LIMIT.get(TOTAL_KEY);
      return json({ total: parseInt(totalStr || "0", 10) }, 200, cors);
    }

    if (request.method !== "POST") return json({ error: "method_not_allowed" }, 405, cors);

    if (url.pathname === "/admin/ingest") return handleIngest(request, env, cors);
    if (url.pathname === "/admin/debug-query") return handleDebugQuery(request, env, cors);
    if (url.pathname === "/ask") return handleAsk(request, env, ctx, cors);

    return json({ error: "not_found" }, 404, cors);
  },
};
