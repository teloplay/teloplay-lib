# Multi-Platform Engine Parity Report

**Scope:** Compare the 3 TeloPlay "engines" — Windows (`innertube-cli.jar`), Android (`innertube.jar` + `MainActivity.kt`), Web (Cloudflare Worker `teloplay-stream-service`) — at the **engine code level only** (no Dart). Reference libraries: `OpenTune-master` (upstream innertube) and `Square-master`.

**Date:** 2026-11-05 (session)

---

## 1. Engine identity

| Platform | Source | Runtime | Transport |
|---|---|---|---|
| Windows | `H:\OpenTune\innertube-cli\src\...\Main.kt` (94,968 B) | Kotlin/JVM daemon | stdin JSON lines (`{"id","cmd","params"}`) → stdout JSON |
| Android | `H:\TeloPlay\teloplay\android\app\src\main\kotlin\...\MainActivity.kt` (97,367 B) + `innertube.jar` | Kotlin/Android | `MethodChannel "command"` → `handleCommand(cmd, params)` |
| Web | `H:\TeloPlay\worker\src\*.js` (youtubei.js) | Cloudflare Worker | HTTP REST `/api/*` |

Both Kotlin engines share the **same** `com.piyas.teloplay.core` innertube library (forked from `com.arturo254.opentune`); diff against `OpenTune-master\innertube` shows **identical model/page file sets** (TeloPlay has only 1 extra: `CustomIndexColumn.kt`). So Windows↔Android parity is *structurally high*; the real divergence is **Kotlin (InnerTube) vs Web (youtubei.js)**.

---

## 2. Endpoint / command coverage matrix

Legend: ✅ implemented · ❌ missing · ⚠️ partial / different shape.

| Command (Kotlin) / Endpoint (Web) | Windows | Android | Web |
|---|---|---|---|
| `resolve` / `/api/resolve` | ✅ | ✅ | ✅ |
| `search` / `/api/search` | ✅ | ✅ | ✅ |
| `search-filter` / `/api/search-filter` | ✅ | ✅ | ✅ |
| `search-continuation` / `/api/search-continuation` | ✅ | ✅ | ✅ |
| `search-sections` | ✅ | ✅ | ❌ (no `/api/search-sections`) |
| `suggest` / `/api/suggest` | ✅ | ✅ | ✅ |
| `smart-search` | ✅ | ✅ | ❌ |
| `details`/`song`/`track` / `/api/song`,`/api/track` | ✅ | ✅ | ✅ |
| `related` / `/api/related` | ✅ | ✅ | ✅ (inside song.js) |
| `album` / `/api/album` | ✅ | ✅ | ✅ |
| `album-songs` | ✅ | ✅ | ❌ |
| `artist` / `/api/artist` | ✅ | ✅ | ✅ |
| `artist-items` / `/api/artist-items` | ✅ | ✅ | ✅ |
| `artist-items-continuation` | ✅ | ✅ | ❌ |
| `playlist` / `/api/playlist` | ✅ | ✅ | ✅ |
| `playlist-continuation` / `/api/playlist-continuation` | ✅ | ✅ | ✅ |
| `lyrics` (smart-lyrics) / `/api/lyrics` | ✅ | ✅ | ✅ |
| `media-info` | ✅ | ✅ | ❌ |
| `charts` / `/api/charts` | ✅ | ✅ | ✅ |
| `home` / `/api/home` | ✅ | ✅ | ✅ |
| `home-continuation` / `/api/home-continuation` | ✅ | ✅ | ✅ |
| `moods-and-genres` / `/api/moods`,`/api/moods-and-genres` | ✅ | ✅ | ✅ |
| `new-releases` / `/api/new-releases` | ✅ | ✅ | ✅ |
| `explore` / `/api/explore` | ✅ | ✅ | ✅ |
| `browse` / `/api/browse` | ✅ | ✅ | ✅ |
| `raw-browse` | ✅ | ✅ | ❌ |
| `next`/`queue` / `/api/next`,`/api/queue` | ✅ | ✅ | ✅ |
| `transcript` | ✅ | ✅ | ❌ |
| `set-locale`/`get-locale` | ✅ | ✅ | ❌ (worker uses `gl` query param only) |
| `library*` | ✅ | ✅ | ❌ |
| `history` | ✅ | ✅ | ❌ |
| `account-info` | ✅ | ✅ | ❌ |
| `queue` (rich) | ✅ | ✅ | ⚠️ `/api/queue` maps to watch-next |
| `like-video`, `like-playlist`, `subscribe` | ✅ | ✅ | ❌ |
| `channel-id` | ✅ | ✅ | ❌ |
| `playlist-create/delete/rename/add/remove/move/...` | ✅ | ✅ | ❌ |
| `register-playback` | ✅ | ✅ | ❌ |
| `resolve-artist-ids` | ✅ | ✅ | ❌ |
| `/api/stream/:id` proxy | ❌ (resolve gives URL) | ❌ | ✅ web-only |
| `/api/test-client` | ❌ | ❌ | ✅ web-only |

**Conclusion:** Windows and Android command sets are **1:1 identical** (46 commands). Web exposes only ~23 endpoints and is missing **~23 commands** (auth/library/playlist-CRUD/transcript/media-info/smart-* etc.). Web is effectively a **read-only stream + metadata service**, not a full engine.

---

## 3. Field-level output parity

### 3.1 `resolve` (rich)

Windows `handleCommand("resolve")` output fields (26):
`ok, videoId, url, directUrl, clientName, provider, itag, format, bitrate, mimeType, contentLength, audioQuality, loudnessDb, expiresInSeconds, duration, title, cleanTitle, author, thumbnail, highResThumbnail, albumId, albumName, explicit, setVideoId, chartPosition, chartChange, watchVideoId, watchPlaylistId`.

Android `streamInfoToMap` emits the **same 26 fields** (minus `clientVersion`, which is captured in `StreamInfo` but not serialized — matches Windows). ✅ Parity.

Web `resolveAudioStream` emits the same core set **plus**:
- `resolveTimeMs` (extra)
- `cached: true` on cache hit (extra)
- `provider` naming differs: web `innertube_ios` / `innertube_visionos` vs Kotlin `innertube_<client>` (e.g. `innertube_androidmusic`).
- `thumbnail`/`highResThumbnail`: web always `https://i.ytimg.com/vi/{id}/hqdefault.jpg`; Kotlin uses `videoDetails.thumbnail` (may be higher quality / different).
- `expiresInSeconds`: web defaults to `21540` (6h) if no `expire` param; Kotlin uses `playerResponse.streamingData?.expiresInSeconds` (often null).
- `contentLength`: web `Number.parseInt` (can become `NaN`→`null`); Kotlin `Long?`.
- `audioQuality`: web fallback `AUDIO_QUALITY_MEDIUM`; Kotlin `audioFormat.audioQuality` (nullable).
- `bitrate`: web fallback `128000`; Kotlin uses real value.
- Client pool differs: web tries only VISIONOS→IOS; Kotlin tries 12+ clients (ANDROID_MUSIC, IOS_MUSIC, etc.) → **different stream selected**, different `itag`/`bitrate`/`mimeType` possible.

### 3.2 `search`

- Windows/Android: `searchTracks`/`searchTracksInternal` → `SongItem` only, `{ok, results}` where each item has 21 fields (type, id, videoId, title, cleanTitle, author, artistId, allArtistNames, allArtistIds, artists[], thumbnail, highResThumbnail, duration, albumId, albumName, explicit, chartPosition, chartChange, setVideoId, watchVideoId, watchPlaylistId). Android `search` command passes `limit<=0 → Int.MAX_VALUE`. Windows uses `limit` as-is (0 = empty take? Actually `if (limit <= 0) songs else songs.take(limit)` → limit 0 returns ALL songs). ⚠️ Slight semantic difference: Windows default limit param 0 → all; Android default 0 → all (maps 0 to MAX_VALUE). OK same.
- Web `/api/search`: returns `{ok, results, continuation}`. Song items via `formatSongItem` include the same 21 fields ✅. But web artist items set `monthlyListenerCountText: null` always (Kotlin may populate). Web album `year` can be `null` (Kotlin `0`). Web includes extra `album: {name,id}` or `album: null` on non-song items. Web playlist `playlistId` strips `VL` prefix (Kotlin keeps raw id). Web `isEditable` always `false`.

### 3.3 `suggest` / `suggestRich`

Kotlin: `{ok, queries, suggestions, recommended, recommendedItems}` (recommended = ytItemToMap). Web: `{ok, queries, suggestions, recommended, recommendedItems}` ✅ shape matches (web adds `suggestions` alias). Good parity.

### 3.4 Song/album/artist/playlist detail

Kotlin `getVideoDetails` returns many fields (title, author, artists, album, duration, thumbnail, related, etc.). Web `getSongDetails` returns a different structure (queue-based). ⚠️ Field names partially differ; web lacks `media-info`-style loudness/itag. Recommend comparing actual JSON.

### 3.5 `charts`, `home`, `explore`, `moods`, `new-releases`, `browse`, `artist-items`

Structurally same between Windows/Android (both use identical Kotlin functions). Web implements these via youtubei.js with different item shapes (see §3.2). Web `artist-items-continuation` missing entirely.

### 3.6 `search-sections`

Windows returns `{ok, sections}`. Android returns `{ok, query, sections}` (extra `query`). ⚠️ Inconsistent field (minor but breaks strict parity).

---

## 4. Confirmed missing / inconsistent items

1. **Web engine is not at parity**: missing ~23 commands (smart-search, smart-lyrics, media-info, set/get-locale, library*, history, account-info, transcript, like-*, subscribe, channel-id, playlist CRUD, register-playback, resolve-artist-ids, raw-browse, album-songs, artist-items-continuation, search-sections).
2. **`search-sections` response shape** differs: Android adds `query`, Windows doesn't.
3. **Resolve output** differs in thumbnail source, provider naming, expiresInSeconds default, contentLength type, client pool → different stream may be selected.
4. **Web item shapes** differ: artist `monthlyListenerCountText` always null, album `year` null vs 0, extra `album` field, playlistId prefix stripping, `isEditable` always false.
5. **Web resolve** adds `resolveTimeMs` + `cached` extra fields (consumers must tolerate).
6. **Android `resolve` StreamInfo** captures `clientVersion` but doesn't serialize it (harmless, but dead field).
7. **Windows `search` with limit=0** returns all songs; Android converts 0→MAX_VALUE (same result, different code path).

---

## 5. Useful things from OpenTune / Square NOT in engines

### From OpenTune (upstream innertube / app)
- **Canvas / looping video** behind player cover (Square/OpenTune feature) — engine has no canvas endpoint.
- **Music videos in-place switching** (watch video without losing queue) — engine exposes videoId but no dedicated video-stream resolve for video track.
- **Radio from a song / autoplay similar** — engine has `next`/`queue` but no explicit "radio station" endpoint.
- **Lyrics translation** into user language (OpenTune betterlyrics) — engine lyrics endpoint has no `targetLang`/translation field.
- **Local files shelf** — not engine scope.
- **Offline download metadata** — not engine scope.
- **Recent searches management** — app-level.
- **Follow artist / liked songs library** — engine exposes library endpoints but no "like song" toggle beyond `like-video` (YouTube like, not TeloPlay liked-songs).
- **ShazamKit / Kugou / LRCLib / Last.fm / SimpMusic / Spotify sources** — OpenTune has these as separate modules; TeloPlay engines don't. Useful for lyrics fallback & multi-source.
- **Word-by-word synced lyrics** — engine returns LRCLib-style synced lyrics but timing granularity depends on provider.

### From Square (Rust native engine)
- **DJ mode**, **crossfade + skip trailing silence**, **sleep timer**, **speed/pitch/reverb/karaoke** — player features, not engine, but no engine hook for audio-effect metadata.
- **Download dedup across playlists** — app-level.
- **Spotify Connect (remote control)** — different source; not in YouTube engine.
- **Pathfinder (smart search routing)** — could inform `smart-search` enhancement.

---

## 6. Recommendations (for later fix, not applied now)

1. **Decide single source of truth:** Make Web engine call the same Kotlin logic? Not possible (CF). Instead, port the missing 23 commands to Web OR restrict Web to stream+metadata and document scope. Recommend: keep Web as stream service; route library/auth/playlist commands only on native (Windows/Android) via the engine jar.
2. **Normalize resolve output:** align `provider` naming, thumbnail source, `expiresInSeconds` default, `contentLength` type across 3. Add `clientVersion` to serialized output on all if needed.
3. **Fix `search-sections` shape:** drop extra `query` from Android OR add to Windows for parity. Prefer Windows shape (minimal) and add `query` to both (useful). Decide and apply consistently.
4. **Web item shape alignment:** populate `monthlyListenerCountText` from artist browse; use `0` not `null` for album `year`; remove spurious `album: null` from non-song items; keep playlistId raw (no VL strip) OR document stripping.
5. **Lyrics translation:** add `targetLang` param to lyrics endpoint (OpenTune useful).
6. **Media-info on Web:** port `/api/media-info` (loudness/itag) for parity.
7. **smart-search on Web:** port or remove from clients when platform=web.
8. **Remove dead `clientVersion` field** in Android StreamInfo or serialize it.

---

*Report only. No code changes applied.*
