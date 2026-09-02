import asyncio
import logging
import os
import re
from typing import Any

import yt_dlp
from fastapi import FastAPI, HTTPException, Query
from fastapi.middleware.cors import CORSMiddleware

logging.basicConfig(
    level=logging.INFO,
    format="%(asctime)s %(levelname)s [teloplay-render] %(message)s",
)
logger = logging.getLogger("teloplay-render")

app = FastAPI(title="TeloPlay Render API", version="1.0.0")
app.add_middleware(
    CORSMiddleware,
    allow_origins=["*"],
    allow_methods=["GET", "OPTIONS"],
    allow_headers=["*"],
)

VIDEO_ID_RE = re.compile(r"^[A-Za-z0-9_-]{11}$")


def normalize_video_id(value: str) -> str:
    value = value.strip()
    if VIDEO_ID_RE.fullmatch(value):
        return value
    match = re.search(r"(?:v=|youtu\.be/|/shorts/|/embed/)([A-Za-z0-9_-]{11})", value)
    if match:
        return match.group(1)
    raise HTTPException(status_code=400, detail="Invalid YouTube video ID")


def ytdlp_options() -> dict[str, Any]:
    return {
        "quiet": True,
        "no_warnings": True,
        "noplaylist": True,
        "skip_download": True,
        "format": "bestaudio[ext=m4a]/bestaudio/best",
        "extractor_args": {
            "youtube": {
                "player_client": ["android_vr", "ios", "web"],
            },
        },
        "http_headers": {
            "User-Agent": (
                "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
                "AppleWebKit/605.1.15 (KHTML, like Gecko) "
                "Version/18.0 Safari/605.1.15"
            ),
            "Accept-Language": "en-US,en;q=0.9",
        },
    }


def search_sync(query: str, limit: int) -> list[dict[str, Any]]:
    options = ytdlp_options()
    options.update({"extract_flat": True, "format": "best"})
    logger.info("search start query=%r limit=%s", query, limit)

    with yt_dlp.YoutubeDL(options) as ydl:
        info = ydl.extract_info(f"ytsearch{limit}:{query}", download=False)

    results: list[dict[str, Any]] = []
    for entry in info.get("entries", []) if info else []:
        if not entry or not entry.get("id"):
            continue
        video_id = entry["id"]
        results.append(
            {
                "videoId": video_id,
                "title": entry.get("title") or "Unknown Title",
                "author": entry.get("channel") or entry.get("uploader") or "Unknown Artist",
                "thumbnail": entry.get("thumbnail") or f"https://i.ytimg.com/vi/{video_id}/hqdefault.jpg",
                "duration": entry.get("duration") or 0,
            }
        )
    logger.info("search done query=%r results=%s", query, len(results))
    return results


def resolve_sync(value: str) -> dict[str, Any]:
    video_id = normalize_video_id(value)
    target = f"https://www.youtube.com/watch?v={video_id}"
    logger.info("resolve start video_id=%s", video_id)

    try:
        with yt_dlp.YoutubeDL(ytdlp_options()) as ydl:
            info = ydl.extract_info(target, download=False)
    except yt_dlp.utils.DownloadError as exc:
        message = str(exc)
        logger.exception("resolve failed video_id=%s error=%s", video_id, message)
        raise HTTPException(
            status_code=502,
            detail={
                "error_type": "YTDLP_RESOLVE_FAILED",
                "message": message,
                "videoId": video_id,
            },
        ) from exc

    stream_url = info.get("url") if info else None
    if not stream_url:
        logger.error("resolve returned no URL video_id=%s", video_id)
        raise HTTPException(status_code=502, detail={"error_type": "NO_STREAM_URL", "videoId": video_id})

    result = {
        "ok": True,
        "videoId": video_id,
        "url": stream_url,
        "title": info.get("title"),
        "author": info.get("channel") or info.get("uploader"),
        "mimeType": info.get("mime_type"),
        "ext": info.get("ext"),
        "bitrate": info.get("abr"),
        "duration": info.get("duration") or 0,
        "expiresInSeconds": info.get("expires_in_seconds"),
    }
    logger.info("resolve success video_id=%s ext=%s abr=%s", video_id, result["ext"], result["bitrate"])
    return result


@app.get("/health")
async def health() -> dict[str, str]:
    return {"status": "ok", "service": "teloplay-render-api"}


@app.get("/api/search")
async def search(
    q: str = Query(min_length=1, max_length=200),
    limit: int = Query(default=25, ge=1, le=50),
) -> dict[str, Any]:
    try:
        results = await asyncio.to_thread(search_sync, q.strip(), limit)
        return {"ok": True, "results": results}
    except HTTPException:
        raise
    except Exception as exc:
        logger.exception("search unexpected error query=%r", q)
        raise HTTPException(status_code=500, detail="Search failed") from exc


@app.get("/api/resolve")
async def resolve(id: str = Query(..., min_length=11, max_length=200)) -> dict[str, Any]:
    return await asyncio.to_thread(resolve_sync, id)


@app.get("/api/suggest")
async def suggest(q: str = Query(default="", max_length=200)) -> dict[str, Any]:
    return {"ok": True, "suggestions": [] if not q.strip() else [q.strip()]}


@app.get("/api/errors")
async def errors() -> dict[str, Any]:
    return {"ok": True, "message": "Use Render Logs for complete live errors."}


if __name__ == "__main__":
    import uvicorn

    uvicorn.run("main:app", host="0.0.0.0", port=int(os.getenv("PORT", "10000")))