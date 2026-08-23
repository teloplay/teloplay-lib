import { resolveInnertube } from "./yt.js";
import { resolvePiped } from "./piped.js";

const CORS = {
  "Access-Control-Allow-Origin": "*",
  "Access-Control-Allow-Methods": "GET,HEAD,OPTIONS",
  "Access-Control-Allow-Headers": "*",
  "Access-Control-Expose-Headers":
    "Content-Length,Content-Range,Accept-Ranges,Content-Type",
};

// ── URL cache ──────────────────────────────────────────────────────────────
// Before: every /audio range request (seek, buffer refill) re-resolved a new
// googlevideo URL → "URL lottery": some resolves come back throttled
// (205 B/s class) or 502. Fix: keep the resolved URL per (videoId, safari)
// for a short TTL so the browser's many range requests hit the SAME url.
//
// This is a per-isolate in-memory cache (Cloudflare Workers isolate memory),
// deliberately NOT KV: it only needs to outlive one playback session, and it
// avoids the egress-latency/consistency cost of KV on every range request.
const urlCache = new Map();
const CACHE_TTL_MS = 30 * 60 * 1000; // 30 min — googlevideo URLs last ~6h
const CACHE_MAX = 500;

function cacheKey(videoId, safari) {
  return `${videoId}|${safari ? "1" : "0"}`;
}

function cacheGet(videoId, safari) {
  const key = cacheKey(videoId, safari);
  const entry = urlCache.get(key);
  if (!entry) return null;
  if (Date.now() > entry.expiresAt) {
    urlCache.delete(key);
    return null;
  }
  return entry.picked;
}

function cacheEvict(videoId, safari) {
  urlCache.delete(cacheKey(videoId, safari));
}

function cacheSet(videoId, safari, picked) {
  if (urlCache.size >= CACHE_MAX) {
    const oldest = urlCache.keys().next().value;
    if (oldest !== undefined) urlCache.delete(oldest);
  }
  urlCache.set(cacheKey(videoId, safari), {
    picked,
    expiresAt: Date.now() + CACHE_TTL_MS,
  });
}

export default {
  async fetch(request) {
    if (request.method === "OPTIONS") {
      return new Response(null, { status: 204, headers: CORS });
    }
    const url = new URL(request.url);
    const pathname = url.pathname.replace(/\/+$/, "");
    try {
      if (pathname === "/search") return json(await handleSearch(url.searchParams));

      const parts = pathname.split("/").filter(Boolean);
      if (parts[0] === "streams" && parts[1]) {
        const safari = url.searchParams.get("safari") === "1";
        const noCache = url.searchParams.get("nocache") === "1";
        return json(await handleStreams(request, parts[1], safari, noCache));
      }
      if (parts[0] === "audio" && parts[1]) {
        const safari = url.searchParams.get("safari") === "1";
        const noCache = url.searchParams.get("nocache") === "1";
        return await handleAudio(request, parts[1], safari, noCache);
      }
      return json({ ok: true, service: "teloplay-stream" });
    } catch (e) {
      return json({ error: String(e?.message || e), stack: String(e?.stack || "") }, 502);
    }
  },
};

async function handleSearch(params) {
  const q = (params.get("q") || "").trim();
  const limit = Math.min(parseInt(params.get("limit") || "20", 10) || 20, 40);
  if (!q) return { items: [] };

  const PIPED = [
    "https://api.piped.private.coffee",
    "https://pipedapi.kavin.rocks",
    "https://pipedapi-libre.kavin.rocks",
  ];

  const jobs = PIPED.map((base) =>
    fetchJson(`${base}/search?q=${encodeURIComponent(q)}&filter=music_songs`, 5000)
      .then((data) => ({ base, data })),
  );
  const settled = await Promise.allSettled(jobs);
  for (const r of settled) {
    if (r.status !== "fulfilled") continue;
    const data = r.value.data;
    const raw = data.items || data.results || (Array.isArray(data) ? data : []);
    const items = [];
    for (const item of raw) {
      const videoId = extractVideoId(item.url || item.streamUrl || "");
      if (!videoId) continue;
      items.push({
        videoId,
        title: item.title || "Unknown",
        author: item.uploaderName || item.uploader || item.author || "Unknown",
        thumbnail:
          item.thumbnail || `https://img.youtube.com/vi/${videoId}/mqdefault.jpg`,
        duration: item.duration ?? null,
      });
      if (items.length >= limit) break;
    }
    if (items.length) return { items, source: r.value.base };
  }
  throw new Error("search failed");
}

async function handleStreams(request, videoId, safari, noCache) {
  const picked = await resolveAudio(videoId, safari, { useCache: !noCache });
  const origin = new URL(request.url).origin;
  const proxyUrl = `${origin}/audio/${encodeURIComponent(videoId)}${safari ? "?safari=1" : ""}`;

  // Preferred: hand the browser the direct googlevideo URL. <audio>/<video>
  // elements need no CORS, and the browser fetches from the user's own IP —
  // skipping the Cloudflare egress entirely (that egress is where the
  // 205 B/s-class throttling / lottery hits). Fall back to the proxy URL
  // when the format needs JS deciphering (`n` param) or is not https.
  const direct = isDirectPlayable(picked.url);

  return {
    streamUrl: direct ? picked.url : proxyUrl,
    proxyUrl,
    direct,
    mimeType: picked.mimeType || "audio/mp4",
    sourceLabel: picked.source || "innertube-worker",
  };
}

async function handleAudio(request, videoId, safari, noCache) {
  let picked = await resolveAudio(videoId, safari, { useCache: !noCache });
  const headers = {};
  const range = request.headers.get("Range");
  if (range) headers.Range = range;

  // HEAD is useful to browser/player capability probes, but googlevideo does
  // not reliably implement HEAD. Return the resolved media metadata without
  // making an upstream request; ranged GET remains the actual probe/playback
  // path.
  if (request.method === "HEAD") {
    const out = new Headers(CORS);
    out.set("Content-Type", picked.mimeType || "audio/mp4");
    out.set("Accept-Ranges", "bytes");
    return new Response(null, { status: 200, headers: out });
  }

  const upstreamRequest = { headers };
  let upstream = await fetch(picked.url, upstreamRequest);

  // One URL-rotation retry: if the cached/resolved URL died (expired,
  // throttled-to-death, 502), evict it and re-resolve fresh.
  if (!upstream.ok && upstream.status !== 206) {
    cacheEvict(videoId, safari);
    picked = await resolveAudio(videoId, safari, { useCache: false });
    upstream = await fetch(picked.url, upstreamRequest);
  }

  if (!upstream.ok && upstream.status !== 206) {
    throw new Error(`audio upstream ${upstream.status}`);
  }
  const out = new Headers(CORS);
  for (const name of ["content-type", "content-length", "content-range", "accept-ranges"]) {
    const v = upstream.headers.get(name);
    if (v) out.set(name, v);
  }
  if (!out.has("content-type")) out.set("content-type", picked.mimeType || "audio/mp4");
  if (!out.has("accept-ranges")) out.set("accept-ranges", "bytes");
  return new Response(request.method === "HEAD" ? null : upstream.body, {
    status: upstream.status,
    headers: out,
  });
}

async function resolveAudio(videoId, safari, { useCache = true } = {}) {
  if (useCache) {
    const hit = cacheGet(videoId, safari);
    if (hit) return hit;
  }

  // Keep this sequential: Android InnerTube is the preferred source. Piped
  // must not win merely because its request happens to finish first.
  let picked;
  try {
    picked = await resolveInnertube(videoId, safari);
  } catch (innertubeError) {
    picked = await resolvePiped(videoId, safari);
  }

  cacheSet(videoId, safari, picked);
  return picked;
}

// A googlevideo URL is directly playable in a browser only when it carries no
// `n` cipher param (that one needs JS deciphering). Signed `sig`/`sp` URLs are
// fine as-is.
function isDirectPlayable(url) {
  if (!url || typeof url !== "string") return false;
  if (!/^https:\/\//i.test(url)) return false;
  try {
    const u = new URL(url);
    return !u.searchParams.has("n");
  } catch (e) {
    return false;
  }
}

async function fetchJson(url) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 8000);
  try {
    const r = await fetch(url, { signal: ctrl.signal, headers: { Accept: "application/json" } });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return await r.json();
  } finally {
    clearTimeout(t);
  }
}

function extractVideoId(input) {
  if (!input) return null;
  if (/^[a-zA-Z0-9_-]{11}$/.test(input)) return input;
  const m = String(input).match(/[?&]v=([a-zA-Z0-9_-]{11})/);
  return m ? m[1] : null;
}

function json(value, status = 200) {
  const headers = new Headers(CORS);
  headers.set("Content-Type", "application/json; charset=utf-8");
  return new Response(JSON.stringify(value), { status, headers });
}
