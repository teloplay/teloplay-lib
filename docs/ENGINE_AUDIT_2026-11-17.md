# TeloPlay Multi-Platform Engine — অডিট + লাইভ টেস্ট + ফিক্স রিপোর্ট

তারিখ: ২০২৬-১১-১৭ · Scope: Windows CLI, Android Native, Web Worker
পদ্ধতি: স্ট্যাটিক কোড রিডিং + লাইভ কল (primary + backup + CLI daemon) + field-by-field compare
**কোনো ফিক্স apply করা হয়নি** — শুধু fix list।

---

## ০. TL;DR

| # | Severity | সমস্যা | ইঞ্জিন | লাইভ প্রমাণ |
|---|---|---|---|---|
| 1 | **P0** | `/api/resolve` + `/api/stream/*` সম্পূর্ণ ভাঙা | Worker (primary/verify) | cross-request promise error |
| 2 | **P0** | CLI daemon nested `params` ইগনোর করে | CLI | `params.videoId` → `videoId missing` |
| 3 | **P0** | response `id` echo-কে overwrite করে | CLI | playlist response-এ request id হারায় |
| 4 | **P0** | `/api/artist-items` ৫০০ crash | Worker (দুইটাই) | `reading 'header'` |
| 5 | **P1** | resolve-এ SongItem মেটাডেটা null | Worker | title/author/duration/thumbnail = null |
| 6 | **P1** | album tracklist-এ artist হারায় | Worker | `Unknown Artist`, `allArtistIds:[null]` |
| 7 | **P1** | invalid ID-তে `ok:true` + dead URL | Worker | resolve/song/album |
| 8 | **P1** | দুই worker আলাদা কোড চলছে | Deploy | related/enrich/resolve drift |
| 9 | **P1** | mirror `teloplay/worker/src` sync-ভাঙা | Repo | ৬+ ফাইল missing |
| 10 | **P2** | empty suggest-এ `suggestions` key নেই | Worker | CLI দেয়, Worker দেয় না |

> ⚠️ টেস্ট ডেটা সংশোধন: `NoucUuveKJ8` = Thoda Thoda Pyaar (245s), `OPf0YbXqDm0` = Uptown Funk (271s)। ঠিক আছে: `YAmSm4IXMlA` = Thodi Jagah (219s), `fsiPzT50ZiM` = Tum Hi Ho (262s)।

---

## ১. Inventory

| ইঞ্জিন | পাথ |
|---|---|
| CLI | `H:\\OpenTune\\innertube-cli\\...\\Main.kt` (2472 LOC) |
| Core | `H:\\OpenTune\\innertube\\...\\core\\` (YouTube.kt, lyrics, metadata, saavn, match) |
| Android | `H:\\TeloPlay\\teloplay\\android\\...\\MainActivity.kt` |
| Worker | `H:\\TeloPlay\\worker\\src\\*.js` (canonical) |
| Mirror | `H:\\TeloPlay\\teloplay\\worker\\src\\` (**out of sync**) |
| JAR | `assets/innertube-cli.jar` (2026-11-17); Android `libs/innertube.jar` (2026-11-11; **match/ নেই**) |

Live URLs: primary `teloplay-verify.workers.dev` (V), backup `teloplay.workers.dev` (B).

## ২. Phase 1 — Static Audit

### 2.1 Schema parity (লাইভ যাচাইকৃত)

| Endpoint | CLI | Worker | Gap |
|---|---|---|---|
| resolve | ৩৫+ keys, metadata filled | keys আছে কিন্তু **metadata null** | P1 |
| search | `{ok,results}` ২১ fields | + continuation + **`_rawIndex` leak** | P2 |
| suggest | ৪ array keys | empty-তে `suggestions` missing | P2 |
| search-sections | ৭ sections | একই | ✅ |
| smart-search | topResult+5 lists | একই | ✅ |
| song/details | full set | + watchVideoId/watchPlaylistId | P2 (CLI missing) |
| related | `{ok,videoId,relatedCount,songs,...}` | **`{v,id,status,items}`** | **P0 schema split** |
| album | full | tracks artist broken | P1 |
| artist | full | + artist/sectionsMap/more* | P2 richer Worker |
| playlist | full + `id` | full + `id` | P0 echo collision |
| lyrics | full + words[] | identical | ✅ |
| next | full | CLI relatedBrowseId null | P1 |
| home/explore/moods/charts/browse | ok | ok | ✅ |
| enrich | v2 | + waveform/releaseDate/label | type mismatch P1 |
| resolve-artist-ids | ok | POST ok | ✅ |

### 2.2 Field type check

| Field | Expected | Result |
|---|---|---|
| allArtistNames | List\<String\> | ✅ সব ইঞ্জিন |
| explicit | Boolean | ✅ |
| duration | Int sec | ✅ |
| albumId | String? | ✅ |
| translation | String? only if targetLang | ✅ |
| match | {accepted,reason,scoreMilli,jiosaavnId} | ✅; Android score hardcode 1000 |
| gainDb / gainCentiDb | Float? / Int? | ✅ −7.9 / −790 |

Extra: `bpm` CLI=0 vs Worker=null; `wikiSummary`/`artistBio` CLI null String vs Worker Object (Flutter cast crash risk); album `allArtistIds:[null]`.

### 2.3 Error handling
- বেশিরভাগ: try/catch + `{ok:false,error}` ✅
- browse.js: `res.ok` নেই + shelf null-guard নেই → 500
- stream-resolver.js: module-level Innertube promise cache → cross-request fail
- Worker invalid IDs → `ok:true`; CLI → `ok:false`

### 2.4 Missing features
| Feature | CLI | Android | Worker |
|---|---|---|---|
| auth CRUD | ✅ | ✅ | ❌ by design |
| enrich / search-sections / resolve-artist-ids / saavn | ✅ | ✅ | ✅ |
| transcript | ❌ | ✅ | ❌ |
| media-info | ✅ | ✅ | ❌ |
| lyrics translation | ✅ | ✅ | ✅ (verify deploy ভাঙা) |
| JioSaavn 320k resolve | ✅ | ✅ (score hardcode) | ✅ |
| Android jar `match/` | — | ❌ | — |


## ৩. Phase 2 — লাইভ টেস্ট ফলাফল

### ৩.১ P0-1: `/api/resolve` primary worker-এ ১০০% ব্যর্থ
- Call: `GET https://teloplay-stream-service.teloplay-verify.workers.dev/api/resolve?id=YAmSm4IXMlA&title=Thodi%20Jagah&artists=Arijit%20Singh&durationMs=219000`
- Result: `{"ok":false,"error":"This promise was created by a request that has since ended..."}`
- Backup worker-এ: `{"v":1,"ok":true,"source":"jiosaavn",...,"bitrateKbps":320}` ✅
- Stream proxy: verify → 503/promise error; backup → 206 audio/mp4 (Range ok)
- Root cause: `stream-resolver.js:8-31` module-level `cachedVisionInstance` promise.

### ৩.২ P0-2: CLI daemon nested `params` ইগনোর
- Input: `{"id":"1","cmd":"resolve","params":{"videoId":"YAmSm4IXMlA"}}` → `{"id":"1","ok":false,"error":"videoId missing"}`
- Input: `{"id":"1","cmd":"resolve","videoId":"YAmSm4IXMlA"}` → `{"id":"1","ok":true,...}`
- Root cause: `Main.kt:2390` `handleCommand(cmd, req)` — পুরো request পাস করছে, `req["params"]` নয়।

### ৩.৩ P0-3: CLI response `id` overwrite
- Request: `{"id":"pp","cmd":"playlist","playlistId":"PL4fGSI1pDJn6O1LS0XSdF3RyO0Rq_LDeI"}`
- Response: `{"id":"PL4fGSI1pDJn6O1LS0XSdF3RyO0Rq_LDeI", ...}` — request id `"pp"` হারিয়ে যায়।
- Root cause: `Main.kt:2390-2394` `result.forEach { (k, v) -> put(k, v) }` `getPlaylistTracks()`-এর নিজস্ব `id` ফিল্ড দ্বারা request id overwrite হয়।

### ৩.৪ P0-4: `/api/artist-items` ৫০০ ক্র্যাশ
- Call: `GET /api/artist-items?browseId=UCDxKh1gFWeYsqePvgVzmPoQ&params=ggMGKgQIARAA`
- Result: 500 `{"ok":false,"error":"Cannot read properties of undefined (reading 'header')"}`
- Root cause: `browse.js:123-143` `shelf.header?...` — `shelf` null check নেই।

### ৩.৫ P1: Worker resolve-এ SongItem মেটাডেটা null
- `title`, `cleanTitle`, `author`, `thumbnail`, `highResThumbnail`, `duration`, `albumId`, `albumName` সব null। CLI একই গানে সব ভরে দেয়।
- Root cause: `resolve-v2.js:133-168` ও `:194-228` field-গুলো hardcode `null`।

### ৩.৬ P1: Album tracklist-এ artist হারানো
- Call: `/api/album?id=MPREb_5KHfi43dABa`
- Header: `artists: [{name:"Arijit Singh",id:"UCDxKh..."}, {name:"Tanishk Bagchi",...}]`
- `tracks[0]`: `author:"Unknown Artist"`, `artistId:null`, `allArtistIds:[null]`, `artists:[{name:"Unknown Artist",id:null}]`
- Root cause: `album.js:86` `if (artists.length > 0 && parsed.artists.length === 0)` — `formatSongItem` সবসময় অন্তত ১টা artist synthesize করে, তাই guard কখনো true হয় না।

### ৩.৭ P1: Invalid ID-তে `ok:true` + dead URL
- `/api/album?id=MPREb_INVALID` → `200 ok:true` (CLI → `ok:false, ALBUM_NOT_FOUND`)
- `/api/song?id=aaaaaaaaaaa` → `200 ok:true` (CLI → `ok:false, DETAILS_FAILED`)
- `/api/resolve?id=xxxxxxxxxxx` → `200 ok:true`, streamUrl = dead proxy URL.

### ৩.৮ P1: দুই worker deploy drift
- verify: পুরনো schema (related/enrich), resolve ভাঙা, translation ভাঙা
- backup: নতুন v2, resolve কাজ করে, translation কাজ করে

### ৩.৯ ৪টি গানের লাইভ resolve ফলাফল
1. `YAmSm4IXMlA` (Thodi Jagah) → JioSaavn 320k (accepted, score 1000, jiosaavnId `rjgU9D7m`)
2. `fsiPzT50ZiM` (Tum Hi Ho) → JioSaavn 320k (accepted, score 1000, jiosaavnId `aRZbUYD7`)
3. `NoucUuveKJ8` (Thoda Thoda Pyaar) → JioSaavn 320k (accepted, score 1000, jiosaavnId `rjkrTnma`)
4. `OPf0YbXqDm0` (Uptown Funk) → YouTube fallback 130kbps (rejected, `artist_mismatch`, score 475)

### ৩.১০ Lyrics লাইভ ফলাফল (YAmSm4IXMlA + targetLang=bn)
- CLI: KuGou word_by_word, 28 lines, 28 translated, 5 words/line, 4 sources ✅
- Worker (backup): হুবহু একই ✅
- Worker (verify): `translatedLang:null`, withT=0 ❌ (পুরনো deploy)


## ৪. Phase 3 — Prioritized Fix List

### 🔴 P0 (crash / break)

#### P0-1: Worker `/api/resolve` cross-request promise
- **ফাইল:** `H:\TeloPlay\worker\src\stream-resolver.js` (line 8-31)
- **ইঞ্জিন:** Worker
- **Fix:** module-level instance cache বাদ দিয়ে per-request তৈরি করুন অথবা `wrangler.toml`-এ compatibility flag দিন:
```toml
compatibility_flags = ["nodejs_compat", "handle_cross_request_promise_resolution"]
```
সঠিক সমাধান: `stream-resolver.js`-এ instance cache না করে `resolveAudioStream`-এর data cache (STREAM_CACHE) রাখুন।

#### P0-2: CLI daemon nested `params` ইগনোর
- **ফাইল:** `H:\OpenTune\innertube-cli\src\main\kotlin\com\piyas\innertubecli\Main.kt` (line 2390)
- **ইঞ্জিন:** CLI
- **Before:**
```kotlin
val result = handleCommand(cmd, req)
```
- **After:**
```kotlin
val params = req["params"]?.jsonObject ?: req
val result = handleCommand(cmd, params)
```

#### P0-3: CLI response `id` overwrite
- **ফাইল:** `Main.kt` line 2390-2394 ও line 637
- **ইঞ্জিন:** CLI
- **Before:**
```kotlin
buildJsonObject {
    put("id", id)
    result.forEach { (k, v) -> put(k, v) }
}
```
- **After:**
```kotlin
buildJsonObject {
    result.forEach { (k, v) -> if (k != "id") put(k, v) }
    put("id", id)
}
```

#### P0-4: `/api/artist-items` ৫০০ crash
- **ফাইল:** `H:\TeloPlay\worker\src\browse.js` (line 23-29, 123-143)
- **ইঞ্জিন:** Worker
- **Before:**
```js
for (const s of sectionContents) {
  const shelf = s.musicShelfRenderer || s.musicCarouselShelfRenderer || s.musicPlaylistShelfRenderer;
  const shelfTitle = shelf.header?...
```
- **After:**
```js
for (const s of sectionContents) {
  const shelf = s.musicShelfRenderer || s.musicCarouselShelfRenderer || s.musicPlaylistShelfRenderer;
  if (!shelf) continue;
  const shelfTitle = shelf.header?...
```
সাথে line 27-এ: `if (!res.ok) return { ok: false, error: 'HTTP ' + res.status };`।

#### P0-5: `related` endpoint schema split
- **ফাইল:** `H:\TeloPlay\worker\src\worker.js` (line 171-188)
- **ইঞ্জিন:** Worker
- **Fix:** canonical v2 ও legacy Flutter schema দুটোই merge করে return করুন যাতে কোনো ক্লায়েন্ট না ভাঙে:
```js
const relData = await getRelatedTracks(id, 'US', 'en');
return jsonResponse({
  ...relData,
  ok: true,
  videoId: id,
  relatedCount: (relData.items || []).length,
  songs: (relData.items || []).map(formatCanonicalTrackToSongItem),
  relatedSongs: [], albums: [], artists: [], similarArtists: [], playlists: [],
});
```

---

### 🟠 P1 (wrong value / type)

#### P1-1: Worker resolve-এ SongItem মেটাডেটা null
- **ফাইল:** `H:\TeloPlay\worker\src\resolve-v2.js` (line 133-168, 194-228)
- **ইঞ্জিন:** Worker
- **Fix:** `resolveAudioStream(id)` থেকে `title`, `author`, `duration`, `thumbnail` মেটাডেটা নিয়ে JioSaavn এবং YouTube দুই branch-েই merge করুন।

#### P1-2: Album tracklist-এ artist হারানো
- **ফাইল:** `H:\TeloPlay\worker\src\album.js` (line 86-90)
- **ইঞ্জিন:** Worker
- **Before:**
```js
if (artists.length > 0 && parsed.artists.length === 0) {
```
- **After:**
```js
const needsArtist = !parsed.artistId || parsed.author === 'Unknown Artist';
if (artists.length > 0 && needsArtist) {
  parsed.artists = artists;
  parsed.author = artists[0].name;
  parsed.allArtistNames = artists.map(a => a.name);
  parsed.allArtistIds = artists.map(a => a.id || null);
  parsed.artistId = artists[0].id || null;
}
```

#### P1-3: Invalid ID-তে `ok:true` + dead URL
- **ফাইল:** `worker\src\album.js`, `song.js`, `resolve-v2.js`
- **ইঞ্জিন:** Worker
- **Fix:** empty/fallback state-এ `ok: false, error: 'Not found'` দিন (CLI-র মতো)।

#### P1-4: Deploy drift
- **Action:** `cd H:\TeloPlay\worker && npx wrangler deploy` চালিয়ে primary (`teloplay-verify`) ও backup (`teloplay`) দুটোতেই একই commit deploy করুন।

#### P1-5: Mirror directory out-of-sync
- **Action:** `H:\TeloPlay\worker\src\` থেকে `H:\TeloPlay\teloplay\worker\src\`-এ সব ফাইল কপি করুন (robocopy /MIR)।

#### P1-6: `enrich` field type mismatch
- **ফাইল:** `Main.kt:2278` ও `enrich-v2.js`
- **Fix:** `bpm` CLI-তে 0-এর বদলে null দিন; `wikiSummary` ও `artistBio` দুজনেই string অথবা দুজনেই `{text,url}` রাখুন।

#### P1-7: CLI `next.relatedBrowseId` সবসময় null
- **ফাইল:** `Main.kt` `next` handler
- **Fix:** `nextResult.relatedEndpoint?.browseId` populate করুন।

#### P1-8: Android `match.scoreMilli` hardcode 1000
- **ফাইল:** `MainActivity.kt:495`
- **Fix:** Android `libs/innertube.jar`-এ `com/piyas/teloplay/core/match/` অন্তর্ভুক্ত করে real matcher চালান।

---

### 🟡 P2 (missing feature)
- **P2-1:** Worker `/api/suggest?q=`-এ `suggestions: []` দিন (`worker.js:254`)।
- **P2-2:** Worker `search.js`-এ `delete item._rawIndex` দিন।
- **P2-3:** CLI `search` response-এ `continuation` দিন।
- **P2-4:** CLI `song/details`-এ `watchVideoId`, `watchPlaylistId` দিন।
- **P2-5:** Worker `new-releases`-এ `items: albums` alias দিন।
- **P2-6:** CLI `explore`-এ `moodCategories` দিন।
- **P2-7:** CLI `moods-and-genres`-এ `categories` দিন।
- **P2-8:** CLI `enrich`-এ `waveform`, `releaseDate`, `label` key দিন।
- **P2-9:** CLI-তে `transcript` যোগ করুন (Android-এ ইতিমধ্যে আছে)।
- **P2-10:** Worker-এ `media-info` যোগ করুন।

---

### 🔵 P3 (enhancement)
- **P3-1:** `MainActivity.kt` থেকে `songToFullMap` মুছে `songToMap` ব্যবহার করুন (duplicate)।
- **P3-2:** Worker browse/album/artist/playlist-এ `AbortSignal.timeout(8000)` দিন।
- **P3-3:** CLI unknown command-এ available list দিন।
- **P3-4:** `new-releases` album item-এ playlistId browseId দিয়ে overwrite বন্ধ করুন (`search.js:527`)।

---

## ৫. Fix করার ক্রম
1. P0-1 (Worker resolve promise) → hotfix
2. P0-2 (CLI params) → ১ লাইন
3. P0-3 (CLI id collision) → ২ লাইন
4. P0-4 (browse.js crash) → ৩ লাইন
5. P0-5 (related schema merge)
6. P1-2 (album artist)
7. P1-1 (resolve metadata)
8. P1-4 + P1-5 (deploy + mirror sync)
9. P1-6, P1-7, P1-8
10. P2/P3

