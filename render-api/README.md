# TeloPlay Render API

Render Web Service backend for TeloPlay. It provides YouTube search and
server-side yt-dlp stream URL resolution. The browser receives the signed
media URL and loads the audio directly from YouTube's media host.

## Render settings

```text
Language: Python
Root Directory: render-api
Build Command: pip install -r requirements.txt
Start Command: uvicorn main:app --host 0.0.0.0 --port $PORT
Plan: Free
```

## Endpoints

```text
GET /health
GET /api/search?q=artist%20song&limit=25
GET /api/resolve?id=VIDEO_ID
GET /api/suggest?q=artist
```

Do not put YouTube cookies or other credentials in this repository. Check
Render Logs for the complete live resolver error.