export const PIPED = [
  "https://api.piped.private.coffee",
  "https://pipedapi.kavin.rocks",
  "https://pipedapi-libre.kavin.rocks",
  "https://pipedapi.leptons.xyz",
  "https://pipedapi.adminforge.de",
];

export async function fetchJson(url, ms = 10000) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), ms);
  try {
    const r = await fetch(url, {
      signal: ctrl.signal,
      headers: { Accept: "application/json" },
    });
    if (!r.ok) throw new Error(`HTTP ${r.status}`);
    return await r.json();
  } finally {
    clearTimeout(t);
  }
}

export function extractVideoId(input) {
  if (!input) return null;
  if (/^[a-zA-Z0-9_-]{11}$/.test(input)) return input;
  const m = String(input).match(/[?&]v=([a-zA-Z0-9_-]{11})/);
  return m ? m[1] : null;
}

function pickAudio(streams, safari) {
  const scored = streams.filter((s) => s && s.url).map((s) => {
    const mime = String(s.mimeType || "").toLowerCase();
    const codec = String(s.codec || s.encoding || "").toLowerCase();
    const br = Number(s.bitrate) || 0;
    const aac = mime.includes("mp4") || codec.includes("mp4a") || codec.includes("aac");
    const opus = mime.includes("webm") || codec.includes("opus");
    let pts = br;
    if (safari) {
      pts += aac ? 10000000 : -5000000;
    } else {
      pts += opus ? 500000 : aac ? 50000 : 0;
    }
    return { ...s, _pts: pts };
  });
  scored.sort((a, b) => b._pts - a._pts);
  return scored[0] || null;
}

export async function resolvePiped(videoId, safari) {
  const jobs = PIPED.map((base) =>
    fetchJson(`${base}/streams/${videoId}`, 12000).then((data) => {
      const streams = Array.isArray(data.audioStreams) ? data.audioStreams : [];
      if (!streams.length) throw new Error(`empty audioStreams from ${base}`);
      const picked = pickAudio(streams, safari);
      if (!picked?.url) throw new Error(`no picked url from ${base}`);
      return {
        url: picked.url,
        mimeType: picked.mimeType || "audio/mp4",
        source: `piped/${new URL(base).hostname}`,
      };
    }),
  );
  return await firstOk(jobs);
}

function firstOk(jobs) {
  return new Promise((resolve, reject) => {
    let pending = jobs.length;
    let last;
    if (!pending) {
      reject(new Error("no backends"));
      return;
    }
    for (const job of jobs) {
      job.then(resolve, (err) => {
        last = err;
        pending -= 1;
        if (pending === 0) reject(last || new Error("all piped backends failed"));
      });
    }
  });
}
