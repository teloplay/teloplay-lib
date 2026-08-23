// Direct YouTube page scraper — no library dependency
// Works in Cloudflare Workers (no eval/new Function needed)
// Scrapes ytInitialPlayerResponse from YouTube's HTML (like yt-dlp)

const USER_AGENTS = [
  "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
  "Mozilla/5.0 (Macintosh; Intel Mac OS X 14_2) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.2 Safari/605.1.15",
  "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36",
];

// The Android InnerTube client currently returns direct adaptive URLs while
// the public watch page often returns SABR-only format metadata.
const ANDROID_USER_AGENT =
  "com.google.android.youtube/20.10.38 (Linux; U; Android 13) gzip";

async function fetchYouTubePage(videoId) {
  const ua = USER_AGENTS[Math.floor(Math.random() * USER_AGENTS.length)];
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 10000);

  try {
    const response = await fetch(`https://www.youtube.com/watch?v=${videoId}`, {
      headers: {
        "User-Agent": ua,
        "Accept": "text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8",
        "Accept-Language": "en-US,en;q=0.9",
      },
      signal: ctrl.signal,
    });

    if (!response.ok) throw new Error(`YouTube page HTTP ${response.status}`);
    const html = await response.text();
    if (html.length < 1000) throw new Error(`Response too short (${html.length} bytes)`);
    if (!html.includes("ytInitialPlayerResponse")) throw new Error("ytInitialPlayerResponse not found in HTML");
    return html;
  } catch (e) {
    if (e.name === "AbortError") throw new Error("YouTube page fetch timeout (>10s)");
    throw e;
  } finally {
    clearTimeout(t);
  }
}

async function fetchAndroidPlayer(videoId) {
  const ctrl = new AbortController();
  const t = setTimeout(() => ctrl.abort(), 10000);
  const body = {
    context: {
      client: {
        clientName: "ANDROID",
        clientVersion: "20.10.38",
        userAgent: ANDROID_USER_AGENT,
        hl: "en",
        gl: "US",
        platform: "MOBILE",
        osName: "Android",
        osVersion: "13",
      },
    },
    videoId,
    contentCheckOk: true,
    racyCheckOk: true,
    playbackContext: {
      contentPlaybackContext: { signatureTimestamp: 20000 },
    },
  };

  try {
    const response = await fetch(
      "https://www.youtube.com/youtubei/v1/player?prettyPrint=false",
      {
        method: "POST",
        headers: {
          "Content-Type": "application/json",
          "User-Agent": ANDROID_USER_AGENT,
          "X-YouTube-Client-Name": "3",
        },
        body: JSON.stringify(body),
        signal: ctrl.signal,
      },
    );
    if (!response.ok) throw new Error(`YouTube Android player HTTP ${response.status}`);
    const player = await response.json();
    if (!player?.streamingData) {
      throw new Error(`Android player has no streamingData (${player?.playabilityStatus?.status || "unknown"})`);
    }
    return player;
  } catch (e) {
    if (e.name === "AbortError") throw new Error("YouTube Android player timeout (>10s)");
    throw e;
  } finally {
    clearTimeout(t);
  }
}

function extractPlayerResponse(html) {
  // Find ytInitialPlayerResponse = { ... };
  const marker = "ytInitialPlayerResponse = ";
  const start = html.indexOf(marker);
  if (start === -1) {
    // Try window.ytInitialPlayerResponse = { ... };
    const marker2 = "window.ytInitialPlayerResponse = ";
    const start2 = html.indexOf(marker2);
    if (start2 === -1) return null;
    return extractJsonBlock(html, start2 + marker2.length);
  }
  return extractJsonBlock(html, start + marker.length);
}

function extractJsonBlock(html, jsonStart) {
  let depth = 0;
  let end = -1;
  for (let i = jsonStart; i < html.length; i++) {
    const ch = html[i];
    if (ch === "{") depth++;
    else if (ch === "}") {
      depth--;
      if (depth === 0) { end = i + 1; break; }
    }
  }
  if (end === -1) return null;
  try {
    return JSON.parse(html.substring(jsonStart, end));
  } catch (e) {
    return null;
  }
}

function pickAudioFormat(adaptiveFormats, safari) {
  if (!Array.isArray(adaptiveFormats) || !adaptiveFormats.length) return null;

  const audioFormats = adaptiveFormats.filter((f) => {
    const mime = (f.mimeType || "").toLowerCase();
    return mime.includes("audio") && !mime.includes("video");
  });

  if (!audioFormats.length) return null;

  const scored = audioFormats.map((f) => {
    const mime = (f.mimeType || "").toLowerCase();
    const codec = (f.codecs || f.encoding || "").toLowerCase();
    const br = Number(f.bitrate) || 0;
    const aac = mime.includes("mp4") || codec.includes("mp4a") || codec.includes("aac");
    const opus = codec.includes("opus") || mime.includes("webm");
    let pts = br;
    if (safari) {
      pts += aac ? 10000000 : -5000000;
    } else {
      pts += opus ? 1000000 : aac ? 50000 : 0;
    }
    return { format: f, pts };
  });

  scored.sort((a, b) => b.pts - a.pts);
  return scored[0].format;
}

function extractUrl(format) {
  // Direct URL
  if (format.url) return format.url;

  // signatureCipher
  if (format.signatureCipher) {
    try {
      const params = new URLSearchParams(format.signatureCipher);
      const url = params.get("url");
      const sp = params.get("sp") || "signature";
      const sig = params.get("s");
      if (url) {
        if (sig) return url + "&" + sp + "=" + encodeURIComponent(sig);
        return url;
      }
    } catch (e) {}
  }

  // cipher
  if (format.cipher) {
    try {
      const params = new URLSearchParams(format.cipher);
      const url = params.get("url");
      const sp = params.get("sp") || "signature";
      const sig = params.get("s");
      if (url) {
        if (sig) return url + "&" + sp + "=" + encodeURIComponent(sig);
        return url;
      }
    } catch (e) {}
  }

  return null;
}

export async function resolveInnertube(videoId, safari) {
  // Android is used first because YouTube's current web watch response can
  // expose formats without URLs and rely on the SABR protocol. Android still
  // returns regular range-readable googlevideo URLs for the same public video.
  try {
    const androidResponse = await fetchAndroidPlayer(videoId);
    const androidResult = resolveFromPlayerResponse(androidResponse, safari, "youtube-android-innertube");
    if (androidResult) return androidResult;
  } catch (androidError) {
    // Keep the direct HTML path as a compatibility fallback when Android's
    // anonymous client is rate-limited or changes its response shape.
  }

  const html = await fetchYouTubePage(videoId);
  const playerResponse = extractPlayerResponse(html);
  const result = resolveFromPlayerResponse(playerResponse, safari, "youtube-page-scrape");
  if (!result) throw new Error("Could not extract a direct audio URL");
  return result;
}

function resolveFromPlayerResponse(playerResponse, safari, source) {
  if (!playerResponse) throw new Error("No playerResponse found");
  if (!playerResponse.streamingData) throw new Error("No streamingData in playerResponse");

  const playability = playerResponse.playabilityStatus || {};
  if (playability.status !== "OK" && playability.status !== "LIVE_STREAM") {
    throw new Error(`YouTube says: ${playability.reason || playability.status}`);
  }

  const adaptiveFormats = playerResponse.streamingData.adaptiveFormats || [];
  const picked = pickAudioFormat(adaptiveFormats, safari);
  if (!picked) throw new Error("No audio format found");

  const url = extractUrl(picked);
  if (!url) return null;

  return {
    url,
    mimeType: picked.mimeType || "audio/mp4",
    source,
  };
}
