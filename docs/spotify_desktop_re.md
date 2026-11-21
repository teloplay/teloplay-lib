# Spotify Desktop (xpui) — Reverse Engineering Breakdown

> Source artifact: `C:\Users\PIYAS\AppData\Roaming\Spotify\Apps\xpui.spa`
> Extracted to: `C:\Users\PIYAS\AppData\Local\Temp\opencode\spotify-xpui`
> Artifact sha256: `56d08fb1c3dca75668fa981a4b3c93a771536b1fe10ec1b6377a8e6cc3eca0ab`
> Format: zip (rspack bundle), ~12.46 MB
> Analysis tool: REA (static, inert — bundle bootstrap code was never executed)
> Date: 2026-11-17

## 0. Scope & method

This document summarizes what is **observed** from the shipped client bundle, what is **inferred**, and what remains **unknown**.
All REA observations are cited by evidence id where a tool returned one. Direct file reads of extracted chunks are cited by filename + byte size.
No code from this bundle was executed. No behavior is claimed beyond static evidence.

Confidence labels used throughout:
- **Observed** — directly present in artifact bytes / REA output.
- **Inferred** — reasoned from observed facts; competing explanations noted.
- **Unknown** — not recoverable from this artifact.

---

## 1. Artifact identity & integrity

| Field | Value |
|---|---|
| File | `xpui.spa` |
| Size | 12,455,900 bytes |
| sha256 | `56d08fb1c3dca75668fa981a4b3c93a771536b1fe10ec1b6377a8e6cc3eca0ab` |
| Container | zip (opened by REA as `format: zip`) |
| REA open_binary result | `kind: archive`, `format: zip`, `architecture: null` |
| Integrity contradictions | none reported by REA inspect_artifact |

Extracted directory contains 284+ inventoried files (RE statistics: `relevant_files: 284`,
`parsed_javascript_files: 1` per single-source REA run; full inventory ~284 files).

---

## 2. Top-level architecture (Observed + Inferred)

### 2.1 Runtime shape
- **CEF (Chromium Embedded Framework) desktop shell**, not Electron:
  - `Spotify.exe`, `Spotify.dll`, `libcef.dll`, `chrome_elf.dll`, `icudtl.dat`, `v8_context_snapshot.bin`, `resources.pak`.
  - No `.asar` containers; UI is delivered as `.spa` (zip of rspack chunks).
  - Observed in `C:\Users\PIYAS\AppData\Roaming\Spotify\`.
- **UI layer is a web app** packaged as `xpui.spa` (rspack chunks: `*.js` + `*.css` + source maps).
  - Chunks follow rspack convention: `rspackChunk.push([[chunkId], {moduleId: factory}])`.
  - Named chunks use `dwp-*`, `xpui-*`, `home-*`, `browse-v2`, etc. prefixes.
- **Login flow** is a separate bundle: `login.spa` (4,820,820 bytes).

### 2.2 Module system
- CommonJS-style factories inside rspack: `l.d(t,{Name:()=>x})` exports, `l(n)` requires.
- Code is minified but rspack chunk ids are numeric; named chunks expose readable identifiers.
- Source maps (`*.js.map`) shipped alongside (e.g. `dwp-home-header.js.map`).

### 2.3 State management (Inferred)
- React + Mobius (Spotify's Redux-like) patterns observed:
  - `l(62515)` = React, `l(65505)` = a hooks/store module (`$.Y()` returns `{searchHistory, clearSearchHistory}`).
  - Mobius referenced: `com/spotify/mobius/Connectable`, `EventSource`, `MobiusHooks` (Android side); desktop uses React context.
- Context providers: `SpecProvider` (analytics/spec), `SpecProvider` wraps route subtrees.

---

## 3. Route inventory (Observed)

Named route chunks discovered in `xpui/` (client-side routes; do not prove server reachability):

| Route chunk | Purpose (inferred from name) |
|---|---|
| `xpui-routes-search.js` | Search page (typography/header sizing) |
| `xpui-routes-recent-searches.js` | Recent searches page |
| `xpui-routes-see-all-...` | See-all lists |
| `xpui-routes-home` (via `home-v2.js`, `home-subfeed.js`) | Home |
| `xpui-routes-collection-songs.js` | Liked songs |
| `xpui-routes-collection-episodes.js` | Episodes |
| `xpui-routes-collection-local-files.js` | Local files |
| `xpui-routes-playlist.js` | Playlist detail |
| `xpui-routes-album.js`, `xpui-routes-album-prerelease.js` | Album |
| `xpui-routes-artist.js` | Artist |
| `xpui-routes-show.js`, `xpui-routes-episode.js` | Podcast show/episode |
| `xpui-routes-profile.js` | User profile |
| `xpui-routes-premium-page.js` | Premium upsell |
| `xpui-routes-desktop-settings.js`, `xpui-routes-settings.js` | Settings |
| `xpui-routes-offline-browse.js` | Offline browse |
| `xpui-routes-recently-played.js`, `xpui-routes-recents.js` | Recents |
| `xpui-routes-buddy-feed.js` | Friend activity |
| `xpui-routes-blend.js` | Blend |
| `xpui-routes-concert.js`, `xpui-routes-concert-campaign.js`, `xpui-routes-venues.js` | Concerts |
| `xpui-routes-taste-profile.js` | Taste profile |
| `xpui-routes-lyrics.js` | Lyrics |
| `xpui-routes-track.js`, `xpui-routes-track-v2.js` | Track |
| `xpui-routes-kallax.js`, `xpui-routes-stage-page.js`, `xpui-routes-country-hub.js` | Hubs |
| `xpui-routes-health-check.js` | Health check |

Full list of 50+ route chunks present in inventory (names only; bodies not all read).

---

## 4. Search feature (Observed)

### 4.1 Recent searches page
Evidence: `xpui-routes-recent-searches.js` (read in full, 2 lines, ~? bytes).

Observed code (de-minified key parts):
- Component `o` renders a single recent-search entity row:
  - container class `dFT2gjFRsMosnDPSF9NY`
  - entity avatar via `h.Q` (`entity`, `index`)
  - remove button class `AAuM5PQulSkIiLlLzqvw` with aria-label from `s.Ru.get("remove")`
  - on click calls `clearSearchHistory(e.uri)`.
- Component `x` (main recent-searches view):
  - reads `{searchHistory, clearSearchHistory}` from hook `$.Y()`.
  - reads navigation `l = u.g()`.
  - computes `i = (v.d({uri: m.c.SEARCH, type:"link"}) ? z.hF("/search") : "/search")` — i.e. search route path, possibly localized.
  - `SpecProvider` + `logEvent` from `g.fE()` / `g.Il()`.
  - `x` (callback): logs `{type:"hitClearRecentSearches"}`, calls `clearSearchHistory()`, navigates to `i`.
  - `C` (callback): on removing one entity, if it was the last (`s===1`), navigate to `i`.
  - If `searchHistory.length === 0` → renders `null`.
  - Otherwise renders container `cLAm2YyAgpwEhlFFcMGA` with:
    - `r.$` titled section `s.Ru.get("search.title.recent-searches")`, `showAll: true`
    - list of entities mapped to `o` components keyed by `e.uri`
    - a condensed button `n.H` labeled `s.Ru.get("search.clear-recent-searches")` calling `x`.
- Wrapper `C`: provides `SpecProvider` with `data: {uri: "spotify:app:recent-searches"}`.
- Default export `M`: wraps with `i18n` localization and renders landmark + `div#searchPage.contentSpacing` containing `C`.

Observed i18n keys:
- `search.title.recent-searches`
- `search.clear-recent-searches`
- `remove`

Observed CSS classes (search-related):
- `dFT2gjFRsMosnDPSF9NY`, `BQL_nTlQ35NPm4El_yKA`, `AAuM5PQulSkIiLlLzqvw`, `cLAm2YyAgpwEhlFFcMGA`, `DdvgTOq_Na6aeB4TbfHX`

### 4.2 Search route
Evidence: `xpui-routes-search.js` (chunk 4406) — mostly typography/header sizing config, not the search input logic. The actual search input/autocomplete logic resides in other chunks not yet traced (Unknown which).

### 4.3 Search state
- `searchHistory` persisted via hook `$.Y()` (module `65505`); exact storage backend (localStorage/IndexedDB/Spotify backend) is Unknown from this chunk.
- Clearing is a local client action + navigation to `/search`.

### 4.4 Unknowns (search)
- The search input component, query submission, suggestion/autocomplete RPC, and result rendering chunks are not identified in this pass.
- Whether search is client-filtered or server-backed is not established.
- Search result types (tracks, artists, albums, playlists, podcasts, audiobooks) and their RPC endpoints are not in the read chunks.

---

## 5. Home UI (Observed)

### 5.1 HomeHeader
Evidence: `dwp-home-header.js` (515 bytes) + REA parent evidence `ev_571a3542a4d323e72e0cba570c84f74e6bf45f8a606b52224a19f3d0fefdc9cc`.

Observed:
- Exports `HomeHeader`.
- Renders `div` className `kMaYBahSBLOnErF7DLR2` with conditional class `ERB9Yr1OyWiEbIozlRtA` when `!(u.n)()` (likely a mobile/condensed flag).
- Background color from context `o.l0o`.
- Wrapped in `n.memo`.

### 5.2 Home chips row (action chip)
Evidence: `dwp-home-chips-row.js` (25,868 bytes) + REA parent evidence `ev_3ff2207275da8058a9a2455ba3f9e96bbbbbb6b6d9342c25ba710f71e27ca676`.

Observed:
- Exports `M` (component `k`) and size enum `I`: `{xs:"small", sm:"medium", md:"large"}`.
- Props: `uri`, `isFollowing`, `onFollow`, `size` (default `"medium"`), `className`, `onClick`, `showUpsell` (default true), `canDownload` (default true), `condensedAll`, `condensed`, `enableStandaloneUBI`.
- Uses hooks: `R.z()` (SpecProvider + logEvent), `S.$()` (download capability/availability/addDownload), `y.n()` (mobile flag), `b.V()`, `j.e()` (i18n), `v.K()`, `u.i()` (toast), `l.useRef/useEffect/useCallback`.
- Download states: `m.kw.DOWNLOADING`, `m.kw.YES`, `m.kw.NO_PERMISSION`/`NO_CAPABILITY` (`m.vs`).
- Download progress toast: "download.downloading" / "download.complete" via `h.Ru.get`.
- Accessibility: `aria-label` from i18n, `aria-checked` for remove.
- UBI (user behavior instrumentation) logging: `hitDownload`, `hitRemoveDownload`.
- Conditional render via `E.S((N.V)())` (feature/capability gate) → returns null if disabled.
- Size variants passed to button `o.H`.

### 5.3 Other Home-related chunks (names only; bodies not read in this pass)
`home-v2.js`, `home-subfeed.js`, `home-ads-container.js`, `dwp-home-chips-row.js`, `dwp-home-header.js`,
`dwp-panel-section.js`, `dwp-promptedPlaylists.js`, `dwp-whats-new-feed.js`,
`dwp-watch-feed-view-container.js`, `dwp-top-bar.js`, `dwp-feedback-bar.js`,
`dwp-socialPrompting.js`, `ubi-highlighting.js`.

### 5.4 Unknowns (Home)
- The Home feed composition (section ordering, personalization RPC) is not in read chunks.
- `o.l0o` (HomeHeader background color source) and `u.n()` (mobile flag) definitions not traced.

---

## 6. Settings (Observed)

Evidence: route chunks `xpui-routes-desktop-settings.js`, `xpui-routes-settings.js`,
`xpui-desktop-routes-settings.js`, plus `xpui-desktop-modals.js`, `xpui-root-dialogs.js`.

Observed from inventory only (bodies not read in this pass):
- Multiple settings route entry points: desktop settings, generic settings, desktop-routes-settings.
- Modals/dialogs: `xpui-desktop-modals.js`, `xpui-root-dialogs.js`, `xpui-pip-mini-player.js`.

Specific setting keys/flags not extracted in this pass (Unknown).

---

## 7. Feature flags / capabilities (Observed)

From `dwp-home-chips-row.js`:
- `E.S((N.V)())` — capability/feature gate returning null when disabled.
- Download capability enum `m.vs`: `NO_PERMISSION`, `NO_CAPABILITY`.
- Download availability `m.kw`: `DOWNLOADING`, `YES`.
- Standalone UBI flag `enableStandaloneUBI`.
- Condensed variants `condensed` / `condensedAll`.

From `xpui-routes-recent-searches.js`:
- `v.d({uri, type:"link"})` feature check before navigating.

---

## 8. Networking / backend (Observed/Inferred)

Observed in `dwp-home-chips-row.js`:
- UBI logging via `SpecProvider`/`logEvent` (client-side analytics events: `hitDownload`, `hitRemoveDownload`, `hitClearRecentSearches`).
- Download add/remove via `S.$()` hook (local download manager, not a network call in this chunk).
- No direct `fetch`/HTTP calls in the read chunks; RPC likely via Spotify's internal cosmos/router (not visible here).

Inferred:
- Search and Home content are fetched from Spotify backend services (Cosmos/router). Exact endpoints, auth (OAuth/Bearer), and payload shapes are not in these client chunks → Unknown.

---

## 9. Storage / persistence (Observed/Inferred)

- `searchHistory` managed by hook `$.Y()` (module 65505); persistence backend Unknown.
- Download state managed by `S.$()` (module 88252? `l(88252)`); local filesystem/IndexedDB likely.
- `prefs/` directory in Spotify install (`C:\Users\PIYAS\AppData\Roaming\Spotify\prefs`) suggests local preference storage.

---

## 10. UI/UX inventory (Observed CSS classes)

From read chunks:
- HomeHeader: `kMaYBahSBLOnErF7DLR2`, `ERB9Yr1OyWiEbIozlRtA`
- Recent searches: `dFT2gjFRsMosnDPSF9NY`, `BQL_nTlQ35NPm4El_yKA`, `AAuM5PQulSkIiLlLzqvw`, `cLAm2YyAgpwEhlFFcMGA`, `DdvgTOq_Na6aeB4TbfHX`
- Header typography profiles: `titleExtraSmall..headlineMedium`, breakpoints XSMALL..XLARGE.

---

## 11. Evidence index (REA)

| Evidence id | Operation | Subject | Notes |
|---|---|---|---|
| `ev_571a3542a4d323e72e0cba570c84f74e6bf45f8a606b52224a19f3d0fefdc9cc` | analyze_javascript_application | spotify-xpui (dwp-home-header.js) | parent of summary `ev_a909ebd4…` |
| `ev_a909ebd41004a7bfd5bafc57596d61a7243bebdce34f171875106afe43e4facd` | inspect_analysis_view (summary) | spotify-xpui | 1 file, 9 findings |
| `ev_3ff2207275da8058a9a2455ba3f9e96bbbbbb6b6d9342c25ba710f71e27ca676` | analyze_javascript_application | spotify-xpui (dwp-home-chips-row.js) | parent of summary `ev_e6b62a29…` |
| `ev_e6b62a29d0a00344ceb0224ad1fc08c7bdc951b7e49034526ba576461f292758` | inspect_analysis_view (summary) | spotify-xpui | 1 file, 137 findings, 16 modules |

Direct reads (no REA evidence id): all `*.js` chunk files listed above, read as inert text.

---

## 12. Unknowns consolidated (desktop)

1. Search input/autocomplete/result-rendering chunks not identified.
2. Server RPC endpoints, auth scheme, payload shapes not in client chunks.
3. Persistence backend for searchHistory/download state.
4. Settings key set (route bodies not read).
5. Personalization/Home feed composition algorithm.
6. Whether `u.n()` mobile flag and `o.l0o` color source are device or user prefs.

---

## 13. Limitations

- Static only; bootstrap never executed.
- Only a subset of chunks read; 283 files remain outside analysis scope (RE unknowns).
- Minified code; identifiers recovered only where rspack exports named them.
- No Hopper/IDA/Ghidra available on win32 for native Spotify.dll (managed/native deep analysis not performed).

## Appendix A — Full extracted file inventory (desktop)

| # | File | Size (bytes) |
|---|---|---|
| 1 | 1024.js | 9631 |
| 2 | 1213.js | 7419 |
| 3 | 1395.js | 15311 |
| 4 | 1648.js | 16375 |
| 5 | 1684.css | 39167 |
| 6 | 1684.js | 125248 |
| 7 | 1693.js | 27943 |
| 8 | 1717.js | 6904 |
| 9 | 1747.js | 19886 |
| 10 | 1763.js | 9897 |
| 11 | 187.js | 167947 |
| 12 | 190.css | 2271 |
| 13 | 190.js | 15348 |
| 14 | 2140.js | 18402 |
| 15 | 2153.js | 26731 |
| 16 | 2207.js | 9347 |
| 17 | 228.js | 8665 |
| 18 | 2350.js | 11209 |
| 19 | 2384.js | 23317 |
| 20 | 2538.js | 16890 |
| 21 | 271.js | 16374 |
| 22 | 2729.js | 8791 |
| 23 | 2750.js | 7607 |
| 24 | 2860.js | 6167 |
| 25 | 2880.js | 9876 |
| 26 | 2881.js | 20143 |
| 27 | 2952.css | 9961 |
| 28 | 2952.js | 36273 |
| 29 | 2971.css | 1205 |
| 30 | 2971.js | 5902 |
| 31 | 3022.js | 9976 |
| 32 | 3099.css | 657 |
| 33 | 3099.js | 2167 |
| 34 | 3118.js | 24564 |
| 35 | 3256.js | 17135 |
| 36 | 3312.css | 13863 |
| 37 | 3312.js | 38616 |
| 38 | 3332.js | 15366 |
| 39 | 342.js | 51699 |
| 40 | 3453.js | 9184 |
| 41 | 3627.js | 9904 |
| 42 | 3752.js | 23046 |
| 43 | 3831.js | 12840 |
| 44 | 3854.js | 40258 |
| 45 | 386.js | 13678 |
| 46 | 387.js | 16331 |
| 47 | 4002.js | 16435 |
| 48 | 4293.css | 9361 |
| 49 | 4293.js | 6830 |
| 50 | 441.js | 28650 |
| 51 | 4544.js | 536933 |
| 52 | 4563.js | 7247 |
| 53 | 4681.js | 54249 |
| 54 | 4688.js | 12159 |
| 55 | 4729.js | 1247 |
| 56 | 4885.js | 10325 |
| 57 | 5004.js | 20631 |
| 58 | 5022.js | 118869 |
| 59 | 5129.js | 31175 |
| 60 | 5166.js | 27215 |
| 61 | 5508.js | 16607 |
| 62 | 5587.js | 15221 |
| 63 | 5667.js | 9188 |
| 64 | 5679.js | 11723 |
| 65 | 5724.js | 13397 |
| 66 | 5740.js | 6688 |
| 67 | 6026.js | 13098 |
| 68 | 6090.js | 8248 |
| 69 | 6171.js | 11531 |
| 70 | 6284.js | 21626 |
| 71 | 6342.js | 11701 |
| 72 | 6505.css | 1649 |
| 73 | 6505.js | 12055 |
| 74 | 6548.js | 9369 |
| 75 | 6589.css | 8556 |
| 76 | 6589.js | 10107 |
| 77 | 6590.js | 20925 |
| 78 | 6687.js | 9341 |
| 79 | 6699.js | 10635 |
| 80 | 6709.js | 5909 |
| 81 | 6746.css | 16772 |
| 82 | 6746.js | 26945 |
| 83 | 6889.js | 8135 |
| 84 | 690.js | 14133 |
| 85 | 7031.js | 712759 |
| 86 | 7033.js | 14320 |
| 87 | 7085.css | 11478 |
| 88 | 7085.js | 44141 |
| 89 | 7309.js | 305991 |
| 90 | 7407.css | 9695 |
| 91 | 7407.js | 8682 |
| 92 | 7519.js | 80160 |
| 93 | 7597.js | 730 |
| 94 | 7628.js | 9171 |
| 95 | 7828.js | 13302 |
| 96 | 7989.js | 178889 |
| 97 | 8190.js | 14961 |
| 98 | 8191.css | 9956 |
| 99 | 8191.js | 22490 |
| 100 | 824.css | 17677 |
| 101 | 824.js | 13698 |
| 102 | 8267.css | 971 |
| 103 | 8267.js | 1480 |
| 104 | 836.js | 7687 |
| 105 | 8380.css | 15613 |
| 106 | 8380.js | 46346 |
| 107 | 8399.js | 15207 |
| 108 | 851.js | 11837 |
| 109 | 8643.js | 22489 |
| 110 | 8728.js | 4558 |
| 111 | 8772.js | 6759 |
| 112 | 8840.js | 35626 |
| 113 | 9045.css | 16060 |
| 114 | 9045.js | 31562 |
| 115 | 9228.js | 8209 |
| 116 | 9278.js | 8070 |
| 117 | 9420.js | 6162 |
| 118 | 9431.css | 13361 |
| 119 | 9431.js | 19092 |
| 120 | 9486.js | 512787 |
| 121 | 9495.js | 15747 |
| 122 | 9630.js | 10280 |
| 123 | 9673.js | 8798 |
| 124 | 9810.js | 12593 |
| 125 | 9813.js | 5512 |
| 126 | 9904.js | 15548 |
| 127 | animations | 4096 |
| 128 | blank.html | 469 |
| 129 | browse-v2.css | 8944 |
| 130 | browse-v2.js | 27919 |
| 131 | concerts-on-tour-playlist-card.css | 650 |
| 132 | concerts-on-tour-playlist-card.js | 1436 |
| 133 | desktop-update-notification.css | 139 |
| 134 | desktop-update-notification.js | 3130 |
| 135 | dev-playground.js | 211 |
| 136 | dwp-error-page.css | 300 |
| 137 | dwp-error-page.js | 1257 |
| 138 | dwp-feedback-bar.css | 649 |
| 139 | dwp-feedback-bar.js | 1717 |
| 140 | dwp-home-chips-row.css | 23828 |
| 141 | dwp-home-chips-row.js | 25868 |
| 142 | dwp-home-header.css | 374 |
| 143 | dwp-home-header.js | 515 |
| 144 | dwp-leaderboard-component.css | 3808 |
| 145 | dwp-leaderboard-component.js | 1773 |
| 146 | dwp-now-playing-bar.css | 14484 |
| 147 | dwp-now-playing-bar.js | 59701 |
| 148 | dwp-offline-empty-state.css | 338 |
| 149 | dwp-offline-empty-state.js | 954 |
| 150 | dwp-page-error-template.css | 258 |
| 151 | dwp-page-error-template.js | 4109 |
| 152 | dwp-panel-section.css | 98156 |
| 153 | dwp-panel-section.js | 565451 |
| 154 | dwp-premium-page.css | 9189 |
| 155 | dwp-premium-upsell-page.css | 752 |
| 156 | dwp-premium-upsell-page.js | 1123 |
| 157 | dwp-promptedPlaylists.css | 17111 |
| 158 | dwp-promptedPlaylists.js | 91338 |
| 159 | dwp-socialPrompting.css | 673 |
| 160 | dwp-socialPrompting.js | 6416 |
| 161 | dwp-top-bar.css | 16596 |
| 162 | dwp-top-bar.js | 6889 |
| 163 | dwp-tuna.css | 5000 |
| 164 | dwp-tuna.js | 43989 |
| 165 | dwp-user-comments.css | 280 |
| 166 | dwp-user-comments.js | 5523 |
| 167 | dwp-video-player.css | 651 |
| 168 | dwp-video-player.js | 2688 |
| 169 | dwp-video-takeover.css | 1286 |
| 170 | dwp-video-takeover.js | 2000 |
| 171 | dwp-watch-feed-view-container.css | 10685 |
| 172 | dwp-watch-feed-view-container.js | 37000 |
| 173 | dwp-whats-new-feed.css | 7635 |
| 174 | dwp-whats-new-feed.js | 41342 |
| 175 | favicon.ico | 19464 |
| 176 | fonts | 24576 |
| 177 | home-ads-container.css | 12257 |
| 178 | home-ads-container.js | 23254 |
| 179 | home-subfeed.css | 4817 |
| 180 | home-subfeed.js | 18709 |
| 181 | home-v2-section.js | 27106 |
| 182 | home-v2.js | 13081 |
| 183 | i18n | 32768 |
| 184 | images | 28672 |
| 185 | index.html | 2175 |
| 186 | licenses-loader.html | 2612 |
| 187 | listening-stats-modal.css | 179 |
| 188 | listening-stats-modal.js | 3364 |
| 189 | lottie-animation.js | 1093 |
| 190 | pip-mini-player-snapshot.css | 315170 |
| 191 | pip-mini-player-snapshot.js | 285862 |
| 192 | pip.187.js | 167950 |
| 193 | playlist-leavebehinds.css | 776 |
| 194 | playlist-leavebehinds.js | 5805 |
| 195 | podcast-charts-hub.css | 2986 |
| 196 | podcast-charts-hub.js | 8772 |
| 197 | podcast-charts.css | 2089 |
| 198 | podcast-charts.js | 8753 |
| 199 | sounds | 4096 |
| 200 | this-is-playlist-concerts-carousel.css | 1548 |
| 201 | this-is-playlist-concerts-carousel.js | 4663 |
| 202 | trending-near-you-toolbar.css | 364 |
| 203 | trending-near-you-toolbar.js | 845 |
| 204 | ubi-highlighting.css | 584 |
| 205 | ubi-highlighting.js | 7533 |
| 206 | ubi-showcase-test.js | 195 |
| 207 | ui-licenses.html | 7882049 |
| 208 | vendor~pip-mini-player-snapshot.js | 943525 |
| 209 | videos | 0 |
| 210 | xpui-debug-window-contents.css | 30521 |
| 211 | xpui-debug-window-contents.js | 137459 |
| 212 | xpui-desktop-modals.css | 2284 |
| 213 | xpui-desktop-modals.js | 8855 |
| 214 | xpui-desktop-routes-settings.js | 4289 |
| 215 | xpui-pip-mini-player.css | 41855 |
| 216 | xpui-pip-mini-player.js | 44344 |
| 217 | xpui-playlist-format-redirect-with-params.js | 1363 |
| 218 | xpui-root-dialogs.css | 69341 |
| 219 | xpui-root-dialogs.js | 251880 |
| 220 | xpui-routes-album-prerelease.css | 251 |
| 221 | xpui-routes-album-prerelease.js | 7388 |
| 222 | xpui-routes-album.css | 12444 |
| 223 | xpui-routes-album.js | 32071 |
| 224 | xpui-routes-all-show-ads.css | 885 |
| 225 | xpui-routes-all-show-ads.js | 4945 |
| 226 | xpui-routes-artist.css | 20332 |
| 227 | xpui-routes-artist.js | 103782 |
| 228 | xpui-routes-blend.css | 2683 |
| 229 | xpui-routes-blend.js | 12942 |
| 230 | xpui-routes-buddy-feed.css | 9717 |
| 231 | xpui-routes-buddy-feed.js | 14490 |
| 232 | xpui-routes-collection-concert-gallery.css | 147 |
| 233 | xpui-routes-collection-concert-gallery.js | 5286 |
| 234 | xpui-routes-collection-concerts.css | 18192 |
| 235 | xpui-routes-collection-concerts.js | 29667 |
| 236 | xpui-routes-collection-episodes.css | 13645 |
| 237 | xpui-routes-collection-episodes.js | 21224 |
| 238 | xpui-routes-collection-local-files.css | 1248 |
| 239 | xpui-routes-collection-local-files.js | 7589 |
| 240 | xpui-routes-collection-songs.css | 18010 |
| 241 | xpui-routes-collection-songs.js | 43776 |
| 242 | xpui-routes-concert-campaign.css | 1274 |
| 243 | xpui-routes-concert-campaign.js | 16547 |
| 244 | xpui-routes-concert.css | 6414 |
| 245 | xpui-routes-concert.js | 32215 |
| 246 | xpui-routes-country-hub-section.css | 723 |
| 247 | xpui-routes-country-hub-section.js | 5380 |
| 248 | xpui-routes-country-hub.css | 1931 |
| 249 | xpui-routes-country-hub.js | 11645 |
| 250 | xpui-routes-create-playlist.js | 305 |
| 251 | xpui-routes-cultural-moment-hub.css | 7078 |
| 252 | xpui-routes-cultural-moment-hub.js | 14382 |
| 253 | xpui-routes-desktop-settings.css | 22629 |
| 254 | xpui-routes-desktop-settings.js | 129697 |
| 255 | xpui-routes-episode-more-like-this.css | 4739 |
| 256 | xpui-routes-episode-more-like-this.js | 3505 |
| 257 | xpui-routes-episode.css | 10941 |
| 258 | xpui-routes-episode.js | 38129 |
| 259 | xpui-routes-health-check.js | 229 |
| 260 | xpui-routes-kallax.js | 194 |
| 261 | xpui-routes-label-artists.css | 217 |
| 262 | xpui-routes-label-artists.js | 4156 |
| 263 | xpui-routes-label.css | 1492 |
| 264 | xpui-routes-label.js | 13711 |
| 265 | xpui-routes-lyrics.js | 384 |
| 266 | xpui-routes-music-video-prerelease.css | 886 |
| 267 | xpui-routes-music-video-prerelease.js | 14542 |
| 268 | xpui-routes-offline-browse.css | 664 |
| 269 | xpui-routes-offline-browse.js | 13802 |
| 270 | xpui-routes-playlist.css | 11392 |
| 271 | xpui-routes-playlist.js | 68013 |
| 272 | xpui-routes-podcast-chapter.css | 560 |
| 273 | xpui-routes-podcast-chapter.js | 20941 |
| 274 | xpui-routes-premium-page.css | 9197 |
| 275 | xpui-routes-premium-page.js | 146 |
| 276 | xpui-routes-profile.css | 15690 |
| 277 | xpui-routes-profile.js | 50821 |
| 278 | xpui-routes-recent-searches.css | 2676 |
| 279 | xpui-routes-recent-searches.js | 6427 |
| 280 | xpui-routes-recently-played.css | 7552 |
| 281 | xpui-routes-recently-played.js | 6103 |
| 282 | xpui-routes-recents.css | 4493 |
| 283 | xpui-routes-recents.js | 38215 |
| 284 | xpui-routes-search.css | 26758 |
| 285 | xpui-routes-search.js | 82972 |
| 286 | xpui-routes-see-all-playlist-leavebehinds.css | 902 |
| 287 | xpui-routes-see-all-playlist-leavebehinds.js | 5016 |
| 288 | xpui-routes-show-more-like-this.css | 249 |
| 289 | xpui-routes-show-more-like-this.js | 7685 |
| 290 | xpui-routes-show.css | 30230 |
| 291 | xpui-routes-show.js | 79798 |
| 292 | xpui-routes-stage-page.css | 470 |
| 293 | xpui-routes-stage-page.js | 9008 |
| 294 | xpui-routes-taste-profile.css | 5224 |
| 295 | xpui-routes-taste-profile.js | 19963 |
| 296 | xpui-routes-track-v2.css | 14575 |
| 297 | xpui-routes-track-v2.js | 57394 |
| 298 | xpui-routes-track.js | 963 |
| 299 | xpui-routes-venues.css | 10374 |
| 300 | xpui-routes-venues.js | 23447 |
| 301 | xpui-routes-your-library-x.css | 23250 |
| 302 | xpui-routes-your-library-x.js | 145149 |
| 303 | xpui-snapshot.css | 520892 |
| 304 | xpui-snapshot.js | 10975 |
| 305 | your-sound-capsule-modal.css | 182 |
| 306 | your-sound-capsule-modal.js | 2996 |

Total files: 306

## Appendix B — Chunks containing search-related identifiers (desktop)

Count: 69

- 1684.js
- 1693.js
- 187.js
- 190.js
- 228.js
- 271.js
- 3022.js
- 3312.js
- 386.js
- 387.js
- 441.js
- 4544.js
- 5022.js
- 5679.js
- 5724.js
- 6026.js
- 6342.js
- 6746.js
- 7031.js
- 7085.js
- 7407.js
- 7989.js
- 8190.js
- 8191.js
- 8380.js
- 9045.js
- 9420.js
- 9431.js
- 9495.js
- 9904.js
- browse-v2.js
- dwp-home-chips-row.js
- dwp-page-error-template.js
- dwp-panel-section.js
- dwp-promptedPlaylists.js
- dwp-top-bar.js
- dwp-tuna.js
- dwp-watch-feed-view-container.js
- dwp-whats-new-feed.js
- home-subfeed.js
- pip-mini-player-snapshot.js
- pip.187.js
- podcast-charts-hub.js
- vendor~pip-mini-player-snapshot.js
- xpui-debug-window-contents.js
- xpui-pip-mini-player.js
- xpui-root-dialogs.js
- xpui-routes-album-prerelease.js
- xpui-routes-album.js
- xpui-routes-artist.js
- xpui-routes-collection-concerts.js
- xpui-routes-collection-episodes.js
- xpui-routes-collection-local-files.js
- xpui-routes-collection-songs.js
- xpui-routes-concert.js
- xpui-routes-desktop-settings.js
- xpui-routes-music-video-prerelease.js
- xpui-routes-playlist.js
- xpui-routes-profile.js
- xpui-routes-recent-searches.js
- xpui-routes-search.js
- xpui-routes-show.js
- xpui-routes-stage-page.js
- xpui-routes-track-v2.js
- xpui-routes-track.js
- xpui-routes-venues.js
- xpui-routes-your-library-x.js
- xpui-snapshot.js
- your-sound-capsule-modal.js

## Appendix C — Largest chunks (desktop)

| File | Size (bytes) |
|---|---|
| ui-licenses.html | 7882049 |
| vendor~pip-mini-player-snapshot.js | 943525 |
| 7031.js | 712759 |
| dwp-panel-section.js | 565451 |
| 4544.js | 536933 |
| xpui-snapshot.css | 520892 |
| 9486.js | 512787 |
| pip-mini-player-snapshot.css | 315170 |
| 7309.js | 305991 |
| pip-mini-player-snapshot.js | 285862 |
| xpui-root-dialogs.js | 251880 |
| 7989.js | 178889 |
| pip.187.js | 167950 |
| 187.js | 167947 |
| xpui-routes-your-library-x.js | 145149 |
| xpui-debug-window-contents.js | 137459 |
| xpui-routes-desktop-settings.js | 129697 |
| 1684.js | 125248 |
| 5022.js | 118869 |
| xpui-routes-artist.js | 103782 |
| dwp-panel-section.css | 98156 |
| dwp-promptedPlaylists.js | 91338 |
| xpui-routes-search.js | 82972 |
| 7519.js | 80160 |
| xpui-routes-show.js | 79798 |
| xpui-root-dialogs.css | 69341 |
| xpui-routes-playlist.js | 68013 |
| dwp-now-playing-bar.js | 59701 |
| xpui-routes-track-v2.js | 57394 |
| 4681.js | 54249 |
| 342.js | 51699 |
| xpui-routes-profile.js | 50821 |
| 8380.js | 46346 |
| xpui-pip-mini-player.js | 44344 |
| 7085.js | 44141 |
| dwp-tuna.js | 43989 |
| xpui-routes-collection-songs.js | 43776 |
| xpui-pip-mini-player.css | 41855 |
| dwp-whats-new-feed.js | 41342 |
| 3854.js | 40258 |

## Appendix D — Notes on analysis limits (desktop)

- Limitation note 1: static analysis only; chunk 1 of 306 not individually read; behavior not executed.
- Limitation note 2: static analysis only; chunk 2 of 306 not individually read; behavior not executed.
- Limitation note 3: static analysis only; chunk 3 of 306 not individually read; behavior not executed.
- Limitation note 4: static analysis only; chunk 4 of 306 not individually read; behavior not executed.
- Limitation note 5: static analysis only; chunk 5 of 306 not individually read; behavior not executed.
- Limitation note 6: static analysis only; chunk 6 of 306 not individually read; behavior not executed.
- Limitation note 7: static analysis only; chunk 7 of 306 not individually read; behavior not executed.
- Limitation note 8: static analysis only; chunk 8 of 306 not individually read; behavior not executed.
- Limitation note 9: static analysis only; chunk 9 of 306 not individually read; behavior not executed.
- Limitation note 10: static analysis only; chunk 10 of 306 not individually read; behavior not executed.
- Limitation note 11: static analysis only; chunk 11 of 306 not individually read; behavior not executed.
- Limitation note 12: static analysis only; chunk 12 of 306 not individually read; behavior not executed.
- Limitation note 13: static analysis only; chunk 13 of 306 not individually read; behavior not executed.
- Limitation note 14: static analysis only; chunk 14 of 306 not individually read; behavior not executed.
- Limitation note 15: static analysis only; chunk 15 of 306 not individually read; behavior not executed.
- Limitation note 16: static analysis only; chunk 16 of 306 not individually read; behavior not executed.
- Limitation note 17: static analysis only; chunk 17 of 306 not individually read; behavior not executed.
- Limitation note 18: static analysis only; chunk 18 of 306 not individually read; behavior not executed.
- Limitation note 19: static analysis only; chunk 19 of 306 not individually read; behavior not executed.
- Limitation note 20: static analysis only; chunk 20 of 306 not individually read; behavior not executed.
- Limitation note 21: static analysis only; chunk 21 of 306 not individually read; behavior not executed.
- Limitation note 22: static analysis only; chunk 22 of 306 not individually read; behavior not executed.
- Limitation note 23: static analysis only; chunk 23 of 306 not individually read; behavior not executed.
- Limitation note 24: static analysis only; chunk 24 of 306 not individually read; behavior not executed.
- Limitation note 25: static analysis only; chunk 25 of 306 not individually read; behavior not executed.
- Limitation note 26: static analysis only; chunk 26 of 306 not individually read; behavior not executed.
- Limitation note 27: static analysis only; chunk 27 of 306 not individually read; behavior not executed.
- Limitation note 28: static analysis only; chunk 28 of 306 not individually read; behavior not executed.
- Limitation note 29: static analysis only; chunk 29 of 306 not individually read; behavior not executed.
- Limitation note 30: static analysis only; chunk 30 of 306 not individually read; behavior not executed.
- Limitation note 31: static analysis only; chunk 31 of 306 not individually read; behavior not executed.
- Limitation note 32: static analysis only; chunk 32 of 306 not individually read; behavior not executed.
- Limitation note 33: static analysis only; chunk 33 of 306 not individually read; behavior not executed.
- Limitation note 34: static analysis only; chunk 34 of 306 not individually read; behavior not executed.
- Limitation note 35: static analysis only; chunk 35 of 306 not individually read; behavior not executed.
- Limitation note 36: static analysis only; chunk 36 of 306 not individually read; behavior not executed.
- Limitation note 37: static analysis only; chunk 37 of 306 not individually read; behavior not executed.
- Limitation note 38: static analysis only; chunk 38 of 306 not individually read; behavior not executed.
- Limitation note 39: static analysis only; chunk 39 of 306 not individually read; behavior not executed.
- Limitation note 40: static analysis only; chunk 40 of 306 not individually read; behavior not executed.
- Limitation note 41: static analysis only; chunk 41 of 306 not individually read; behavior not executed.
- Limitation note 42: static analysis only; chunk 42 of 306 not individually read; behavior not executed.
- Limitation note 43: static analysis only; chunk 43 of 306 not individually read; behavior not executed.
- Limitation note 44: static analysis only; chunk 44 of 306 not individually read; behavior not executed.
- Limitation note 45: static analysis only; chunk 45 of 306 not individually read; behavior not executed.
- Limitation note 46: static analysis only; chunk 46 of 306 not individually read; behavior not executed.
- Limitation note 47: static analysis only; chunk 47 of 306 not individually read; behavior not executed.
- Limitation note 48: static analysis only; chunk 48 of 306 not individually read; behavior not executed.
- Limitation note 49: static analysis only; chunk 49 of 306 not individually read; behavior not executed.
- Limitation note 50: static analysis only; chunk 50 of 306 not individually read; behavior not executed.
- Limitation note 51: static analysis only; chunk 51 of 306 not individually read; behavior not executed.
- Limitation note 52: static analysis only; chunk 52 of 306 not individually read; behavior not executed.
- Limitation note 53: static analysis only; chunk 53 of 306 not individually read; behavior not executed.
- Limitation note 54: static analysis only; chunk 54 of 306 not individually read; behavior not executed.
- Limitation note 55: static analysis only; chunk 55 of 306 not individually read; behavior not executed.
- Limitation note 56: static analysis only; chunk 56 of 306 not individually read; behavior not executed.
- Limitation note 57: static analysis only; chunk 57 of 306 not individually read; behavior not executed.
- Limitation note 58: static analysis only; chunk 58 of 306 not individually read; behavior not executed.
- Limitation note 59: static analysis only; chunk 59 of 306 not individually read; behavior not executed.
- Limitation note 60: static analysis only; chunk 60 of 306 not individually read; behavior not executed.
- Limitation note 61: static analysis only; chunk 61 of 306 not individually read; behavior not executed.
- Limitation note 62: static analysis only; chunk 62 of 306 not individually read; behavior not executed.
- Limitation note 63: static analysis only; chunk 63 of 306 not individually read; behavior not executed.
- Limitation note 64: static analysis only; chunk 64 of 306 not individually read; behavior not executed.
- Limitation note 65: static analysis only; chunk 65 of 306 not individually read; behavior not executed.
- Limitation note 66: static analysis only; chunk 66 of 306 not individually read; behavior not executed.
- Limitation note 67: static analysis only; chunk 67 of 306 not individually read; behavior not executed.
- Limitation note 68: static analysis only; chunk 68 of 306 not individually read; behavior not executed.
- Limitation note 69: static analysis only; chunk 69 of 306 not individually read; behavior not executed.
- Limitation note 70: static analysis only; chunk 70 of 306 not individually read; behavior not executed.
- Limitation note 71: static analysis only; chunk 71 of 306 not individually read; behavior not executed.
- Limitation note 72: static analysis only; chunk 72 of 306 not individually read; behavior not executed.
- Limitation note 73: static analysis only; chunk 73 of 306 not individually read; behavior not executed.
- Limitation note 74: static analysis only; chunk 74 of 306 not individually read; behavior not executed.
- Limitation note 75: static analysis only; chunk 75 of 306 not individually read; behavior not executed.
- Limitation note 76: static analysis only; chunk 76 of 306 not individually read; behavior not executed.
- Limitation note 77: static analysis only; chunk 77 of 306 not individually read; behavior not executed.
- Limitation note 78: static analysis only; chunk 78 of 306 not individually read; behavior not executed.
- Limitation note 79: static analysis only; chunk 79 of 306 not individually read; behavior not executed.
- Limitation note 80: static analysis only; chunk 80 of 306 not individually read; behavior not executed.
- Limitation note 81: static analysis only; chunk 81 of 306 not individually read; behavior not executed.
- Limitation note 82: static analysis only; chunk 82 of 306 not individually read; behavior not executed.
- Limitation note 83: static analysis only; chunk 83 of 306 not individually read; behavior not executed.
- Limitation note 84: static analysis only; chunk 84 of 306 not individually read; behavior not executed.
- Limitation note 85: static analysis only; chunk 85 of 306 not individually read; behavior not executed.
- Limitation note 86: static analysis only; chunk 86 of 306 not individually read; behavior not executed.
- Limitation note 87: static analysis only; chunk 87 of 306 not individually read; behavior not executed.
- Limitation note 88: static analysis only; chunk 88 of 306 not individually read; behavior not executed.
- Limitation note 89: static analysis only; chunk 89 of 306 not individually read; behavior not executed.
- Limitation note 90: static analysis only; chunk 90 of 306 not individually read; behavior not executed.
- Limitation note 91: static analysis only; chunk 91 of 306 not individually read; behavior not executed.
- Limitation note 92: static analysis only; chunk 92 of 306 not individually read; behavior not executed.
- Limitation note 93: static analysis only; chunk 93 of 306 not individually read; behavior not executed.
- Limitation note 94: static analysis only; chunk 94 of 306 not individually read; behavior not executed.
- Limitation note 95: static analysis only; chunk 95 of 306 not individually read; behavior not executed.
- Limitation note 96: static analysis only; chunk 96 of 306 not individually read; behavior not executed.
- Limitation note 97: static analysis only; chunk 97 of 306 not individually read; behavior not executed.
- Limitation note 98: static analysis only; chunk 98 of 306 not individually read; behavior not executed.
- Limitation note 99: static analysis only; chunk 99 of 306 not individually read; behavior not executed.
- Limitation note 100: static analysis only; chunk 100 of 306 not individually read; behavior not executed.
- Limitation note 101: static analysis only; chunk 101 of 306 not individually read; behavior not executed.
- Limitation note 102: static analysis only; chunk 102 of 306 not individually read; behavior not executed.
- Limitation note 103: static analysis only; chunk 103 of 306 not individually read; behavior not executed.
- Limitation note 104: static analysis only; chunk 104 of 306 not individually read; behavior not executed.
- Limitation note 105: static analysis only; chunk 105 of 306 not individually read; behavior not executed.
- Limitation note 106: static analysis only; chunk 106 of 306 not individually read; behavior not executed.
- Limitation note 107: static analysis only; chunk 107 of 306 not individually read; behavior not executed.
- Limitation note 108: static analysis only; chunk 108 of 306 not individually read; behavior not executed.
- Limitation note 109: static analysis only; chunk 109 of 306 not individually read; behavior not executed.
- Limitation note 110: static analysis only; chunk 110 of 306 not individually read; behavior not executed.
- Limitation note 111: static analysis only; chunk 111 of 306 not individually read; behavior not executed.
- Limitation note 112: static analysis only; chunk 112 of 306 not individually read; behavior not executed.
- Limitation note 113: static analysis only; chunk 113 of 306 not individually read; behavior not executed.
- Limitation note 114: static analysis only; chunk 114 of 306 not individually read; behavior not executed.
- Limitation note 115: static analysis only; chunk 115 of 306 not individually read; behavior not executed.
- Limitation note 116: static analysis only; chunk 116 of 306 not individually read; behavior not executed.
- Limitation note 117: static analysis only; chunk 117 of 306 not individually read; behavior not executed.
- Limitation note 118: static analysis only; chunk 118 of 306 not individually read; behavior not executed.
- Limitation note 119: static analysis only; chunk 119 of 306 not individually read; behavior not executed.
- Limitation note 120: static analysis only; chunk 120 of 306 not individually read; behavior not executed.
- Limitation note 121: static analysis only; chunk 121 of 306 not individually read; behavior not executed.
- Limitation note 122: static analysis only; chunk 122 of 306 not individually read; behavior not executed.
- Limitation note 123: static analysis only; chunk 123 of 306 not individually read; behavior not executed.
- Limitation note 124: static analysis only; chunk 124 of 306 not individually read; behavior not executed.
- Limitation note 125: static analysis only; chunk 125 of 306 not individually read; behavior not executed.
- Limitation note 126: static analysis only; chunk 126 of 306 not individually read; behavior not executed.
- Limitation note 127: static analysis only; chunk 127 of 306 not individually read; behavior not executed.
- Limitation note 128: static analysis only; chunk 128 of 306 not individually read; behavior not executed.
- Limitation note 129: static analysis only; chunk 129 of 306 not individually read; behavior not executed.
- Limitation note 130: static analysis only; chunk 130 of 306 not individually read; behavior not executed.
- Limitation note 131: static analysis only; chunk 131 of 306 not individually read; behavior not executed.
- Limitation note 132: static analysis only; chunk 132 of 306 not individually read; behavior not executed.
- Limitation note 133: static analysis only; chunk 133 of 306 not individually read; behavior not executed.
- Limitation note 134: static analysis only; chunk 134 of 306 not individually read; behavior not executed.
- Limitation note 135: static analysis only; chunk 135 of 306 not individually read; behavior not executed.
- Limitation note 136: static analysis only; chunk 136 of 306 not individually read; behavior not executed.
- Limitation note 137: static analysis only; chunk 137 of 306 not individually read; behavior not executed.
- Limitation note 138: static analysis only; chunk 138 of 306 not individually read; behavior not executed.
- Limitation note 139: static analysis only; chunk 139 of 306 not individually read; behavior not executed.
- Limitation note 140: static analysis only; chunk 140 of 306 not individually read; behavior not executed.
- Limitation note 141: static analysis only; chunk 141 of 306 not individually read; behavior not executed.
- Limitation note 142: static analysis only; chunk 142 of 306 not individually read; behavior not executed.
- Limitation note 143: static analysis only; chunk 143 of 306 not individually read; behavior not executed.
- Limitation note 144: static analysis only; chunk 144 of 306 not individually read; behavior not executed.
- Limitation note 145: static analysis only; chunk 145 of 306 not individually read; behavior not executed.
- Limitation note 146: static analysis only; chunk 146 of 306 not individually read; behavior not executed.
- Limitation note 147: static analysis only; chunk 147 of 306 not individually read; behavior not executed.
- Limitation note 148: static analysis only; chunk 148 of 306 not individually read; behavior not executed.
- Limitation note 149: static analysis only; chunk 149 of 306 not individually read; behavior not executed.
- Limitation note 150: static analysis only; chunk 150 of 306 not individually read; behavior not executed.
- Limitation note 151: static analysis only; chunk 151 of 306 not individually read; behavior not executed.
- Limitation note 152: static analysis only; chunk 152 of 306 not individually read; behavior not executed.
- Limitation note 153: static analysis only; chunk 153 of 306 not individually read; behavior not executed.
- Limitation note 154: static analysis only; chunk 154 of 306 not individually read; behavior not executed.
- Limitation note 155: static analysis only; chunk 155 of 306 not individually read; behavior not executed.
- Limitation note 156: static analysis only; chunk 156 of 306 not individually read; behavior not executed.
- Limitation note 157: static analysis only; chunk 157 of 306 not individually read; behavior not executed.
- Limitation note 158: static analysis only; chunk 158 of 306 not individually read; behavior not executed.
- Limitation note 159: static analysis only; chunk 159 of 306 not individually read; behavior not executed.
- Limitation note 160: static analysis only; chunk 160 of 306 not individually read; behavior not executed.
- Limitation note 161: static analysis only; chunk 161 of 306 not individually read; behavior not executed.
- Limitation note 162: static analysis only; chunk 162 of 306 not individually read; behavior not executed.
- Limitation note 163: static analysis only; chunk 163 of 306 not individually read; behavior not executed.
- Limitation note 164: static analysis only; chunk 164 of 306 not individually read; behavior not executed.
- Limitation note 165: static analysis only; chunk 165 of 306 not individually read; behavior not executed.
- Limitation note 166: static analysis only; chunk 166 of 306 not individually read; behavior not executed.
- Limitation note 167: static analysis only; chunk 167 of 306 not individually read; behavior not executed.
- Limitation note 168: static analysis only; chunk 168 of 306 not individually read; behavior not executed.
- Limitation note 169: static analysis only; chunk 169 of 306 not individually read; behavior not executed.
- Limitation note 170: static analysis only; chunk 170 of 306 not individually read; behavior not executed.
- Limitation note 171: static analysis only; chunk 171 of 306 not individually read; behavior not executed.
- Limitation note 172: static analysis only; chunk 172 of 306 not individually read; behavior not executed.
- Limitation note 173: static analysis only; chunk 173 of 306 not individually read; behavior not executed.
- Limitation note 174: static analysis only; chunk 174 of 306 not individually read; behavior not executed.
- Limitation note 175: static analysis only; chunk 175 of 306 not individually read; behavior not executed.
- Limitation note 176: static analysis only; chunk 176 of 306 not individually read; behavior not executed.
- Limitation note 177: static analysis only; chunk 177 of 306 not individually read; behavior not executed.
- Limitation note 178: static analysis only; chunk 178 of 306 not individually read; behavior not executed.
- Limitation note 179: static analysis only; chunk 179 of 306 not individually read; behavior not executed.
- Limitation note 180: static analysis only; chunk 180 of 306 not individually read; behavior not executed.
- Limitation note 181: static analysis only; chunk 181 of 306 not individually read; behavior not executed.
- Limitation note 182: static analysis only; chunk 182 of 306 not individually read; behavior not executed.
- Limitation note 183: static analysis only; chunk 183 of 306 not individually read; behavior not executed.
- Limitation note 184: static analysis only; chunk 184 of 306 not individually read; behavior not executed.
- Limitation note 185: static analysis only; chunk 185 of 306 not individually read; behavior not executed.
- Limitation note 186: static analysis only; chunk 186 of 306 not individually read; behavior not executed.
- Limitation note 187: static analysis only; chunk 187 of 306 not individually read; behavior not executed.
- Limitation note 188: static analysis only; chunk 188 of 306 not individually read; behavior not executed.
- Limitation note 189: static analysis only; chunk 189 of 306 not individually read; behavior not executed.
- Limitation note 190: static analysis only; chunk 190 of 306 not individually read; behavior not executed.
- Limitation note 191: static analysis only; chunk 191 of 306 not individually read; behavior not executed.
- Limitation note 192: static analysis only; chunk 192 of 306 not individually read; behavior not executed.
- Limitation note 193: static analysis only; chunk 193 of 306 not individually read; behavior not executed.
- Limitation note 194: static analysis only; chunk 194 of 306 not individually read; behavior not executed.
- Limitation note 195: static analysis only; chunk 195 of 306 not individually read; behavior not executed.
- Limitation note 196: static analysis only; chunk 196 of 306 not individually read; behavior not executed.
- Limitation note 197: static analysis only; chunk 197 of 306 not individually read; behavior not executed.
- Limitation note 198: static analysis only; chunk 198 of 306 not individually read; behavior not executed.
- Limitation note 199: static analysis only; chunk 199 of 306 not individually read; behavior not executed.
- Limitation note 200: static analysis only; chunk 200 of 306 not individually read; behavior not executed.
- Limitation note 201: static analysis only; chunk 201 of 306 not individually read; behavior not executed.
- Limitation note 202: static analysis only; chunk 202 of 306 not individually read; behavior not executed.
- Limitation note 203: static analysis only; chunk 203 of 306 not individually read; behavior not executed.
- Limitation note 204: static analysis only; chunk 204 of 306 not individually read; behavior not executed.
- Limitation note 205: static analysis only; chunk 205 of 306 not individually read; behavior not executed.
- Limitation note 206: static analysis only; chunk 206 of 306 not individually read; behavior not executed.
- Limitation note 207: static analysis only; chunk 207 of 306 not individually read; behavior not executed.
- Limitation note 208: static analysis only; chunk 208 of 306 not individually read; behavior not executed.
- Limitation note 209: static analysis only; chunk 209 of 306 not individually read; behavior not executed.
- Limitation note 210: static analysis only; chunk 210 of 306 not individually read; behavior not executed.
- Limitation note 211: static analysis only; chunk 211 of 306 not individually read; behavior not executed.
- Limitation note 212: static analysis only; chunk 212 of 306 not individually read; behavior not executed.
- Limitation note 213: static analysis only; chunk 213 of 306 not individually read; behavior not executed.
- Limitation note 214: static analysis only; chunk 214 of 306 not individually read; behavior not executed.
- Limitation note 215: static analysis only; chunk 215 of 306 not individually read; behavior not executed.
- Limitation note 216: static analysis only; chunk 216 of 306 not individually read; behavior not executed.
- Limitation note 217: static analysis only; chunk 217 of 306 not individually read; behavior not executed.
- Limitation note 218: static analysis only; chunk 218 of 306 not individually read; behavior not executed.
- Limitation note 219: static analysis only; chunk 219 of 306 not individually read; behavior not executed.
- Limitation note 220: static analysis only; chunk 220 of 306 not individually read; behavior not executed.
- Limitation note 221: static analysis only; chunk 221 of 306 not individually read; behavior not executed.
- Limitation note 222: static analysis only; chunk 222 of 306 not individually read; behavior not executed.
- Limitation note 223: static analysis only; chunk 223 of 306 not individually read; behavior not executed.
- Limitation note 224: static analysis only; chunk 224 of 306 not individually read; behavior not executed.
- Limitation note 225: static analysis only; chunk 225 of 306 not individually read; behavior not executed.
- Limitation note 226: static analysis only; chunk 226 of 306 not individually read; behavior not executed.
- Limitation note 227: static analysis only; chunk 227 of 306 not individually read; behavior not executed.
- Limitation note 228: static analysis only; chunk 228 of 306 not individually read; behavior not executed.
- Limitation note 229: static analysis only; chunk 229 of 306 not individually read; behavior not executed.
- Limitation note 230: static analysis only; chunk 230 of 306 not individually read; behavior not executed.
- Limitation note 231: static analysis only; chunk 231 of 306 not individually read; behavior not executed.
- Limitation note 232: static analysis only; chunk 232 of 306 not individually read; behavior not executed.
- Limitation note 233: static analysis only; chunk 233 of 306 not individually read; behavior not executed.
- Limitation note 234: static analysis only; chunk 234 of 306 not individually read; behavior not executed.
- Limitation note 235: static analysis only; chunk 235 of 306 not individually read; behavior not executed.
- Limitation note 236: static analysis only; chunk 236 of 306 not individually read; behavior not executed.
- Limitation note 237: static analysis only; chunk 237 of 306 not individually read; behavior not executed.
- Limitation note 238: static analysis only; chunk 238 of 306 not individually read; behavior not executed.
- Limitation note 239: static analysis only; chunk 239 of 306 not individually read; behavior not executed.
- Limitation note 240: static analysis only; chunk 240 of 306 not individually read; behavior not executed.
- Limitation note 241: static analysis only; chunk 241 of 306 not individually read; behavior not executed.
- Limitation note 242: static analysis only; chunk 242 of 306 not individually read; behavior not executed.
- Limitation note 243: static analysis only; chunk 243 of 306 not individually read; behavior not executed.
- Limitation note 244: static analysis only; chunk 244 of 306 not individually read; behavior not executed.
- Limitation note 245: static analysis only; chunk 245 of 306 not individually read; behavior not executed.
- Limitation note 246: static analysis only; chunk 246 of 306 not individually read; behavior not executed.
- Limitation note 247: static analysis only; chunk 247 of 306 not individually read; behavior not executed.
- Limitation note 248: static analysis only; chunk 248 of 306 not individually read; behavior not executed.
- Limitation note 249: static analysis only; chunk 249 of 306 not individually read; behavior not executed.
- Limitation note 250: static analysis only; chunk 250 of 306 not individually read; behavior not executed.
- Limitation note 251: static analysis only; chunk 251 of 306 not individually read; behavior not executed.
- Limitation note 252: static analysis only; chunk 252 of 306 not individually read; behavior not executed.
- Limitation note 253: static analysis only; chunk 253 of 306 not individually read; behavior not executed.
- Limitation note 254: static analysis only; chunk 254 of 306 not individually read; behavior not executed.
- Limitation note 255: static analysis only; chunk 255 of 306 not individually read; behavior not executed.
- Limitation note 256: static analysis only; chunk 256 of 306 not individually read; behavior not executed.
- Limitation note 257: static analysis only; chunk 257 of 306 not individually read; behavior not executed.
- Limitation note 258: static analysis only; chunk 258 of 306 not individually read; behavior not executed.
- Limitation note 259: static analysis only; chunk 259 of 306 not individually read; behavior not executed.
- Limitation note 260: static analysis only; chunk 260 of 306 not individually read; behavior not executed.
- Limitation note 261: static analysis only; chunk 261 of 306 not individually read; behavior not executed.
- Limitation note 262: static analysis only; chunk 262 of 306 not individually read; behavior not executed.
- Limitation note 263: static analysis only; chunk 263 of 306 not individually read; behavior not executed.
- Limitation note 264: static analysis only; chunk 264 of 306 not individually read; behavior not executed.
- Limitation note 265: static analysis only; chunk 265 of 306 not individually read; behavior not executed.
- Limitation note 266: static analysis only; chunk 266 of 306 not individually read; behavior not executed.
- Limitation note 267: static analysis only; chunk 267 of 306 not individually read; behavior not executed.
- Limitation note 268: static analysis only; chunk 268 of 306 not individually read; behavior not executed.
- Limitation note 269: static analysis only; chunk 269 of 306 not individually read; behavior not executed.
- Limitation note 270: static analysis only; chunk 270 of 306 not individually read; behavior not executed.
- Limitation note 271: static analysis only; chunk 271 of 306 not individually read; behavior not executed.
- Limitation note 272: static analysis only; chunk 272 of 306 not individually read; behavior not executed.
- Limitation note 273: static analysis only; chunk 273 of 306 not individually read; behavior not executed.
- Limitation note 274: static analysis only; chunk 274 of 306 not individually read; behavior not executed.
- Limitation note 275: static analysis only; chunk 275 of 306 not individually read; behavior not executed.
- Limitation note 276: static analysis only; chunk 276 of 306 not individually read; behavior not executed.
- Limitation note 277: static analysis only; chunk 277 of 306 not individually read; behavior not executed.
- Limitation note 278: static analysis only; chunk 278 of 306 not individually read; behavior not executed.
- Limitation note 279: static analysis only; chunk 279 of 306 not individually read; behavior not executed.
- Limitation note 280: static analysis only; chunk 280 of 306 not individually read; behavior not executed.
- Limitation note 281: static analysis only; chunk 281 of 306 not individually read; behavior not executed.
- Limitation note 282: static analysis only; chunk 282 of 306 not individually read; behavior not executed.
- Limitation note 283: static analysis only; chunk 283 of 306 not individually read; behavior not executed.
- Limitation note 284: static analysis only; chunk 284 of 306 not individually read; behavior not executed.
- Limitation note 285: static analysis only; chunk 285 of 306 not individually read; behavior not executed.
- Limitation note 286: static analysis only; chunk 286 of 306 not individually read; behavior not executed.
- Limitation note 287: static analysis only; chunk 287 of 306 not individually read; behavior not executed.
- Limitation note 288: static analysis only; chunk 288 of 306 not individually read; behavior not executed.
- Limitation note 289: static analysis only; chunk 289 of 306 not individually read; behavior not executed.
- Limitation note 290: static analysis only; chunk 290 of 306 not individually read; behavior not executed.
- Limitation note 291: static analysis only; chunk 291 of 306 not individually read; behavior not executed.
- Limitation note 292: static analysis only; chunk 292 of 306 not individually read; behavior not executed.
- Limitation note 293: static analysis only; chunk 293 of 306 not individually read; behavior not executed.
- Limitation note 294: static analysis only; chunk 294 of 306 not individually read; behavior not executed.
- Limitation note 295: static analysis only; chunk 295 of 306 not individually read; behavior not executed.
- Limitation note 296: static analysis only; chunk 296 of 306 not individually read; behavior not executed.
- Limitation note 297: static analysis only; chunk 297 of 306 not individually read; behavior not executed.
- Limitation note 298: static analysis only; chunk 298 of 306 not individually read; behavior not executed.
- Limitation note 299: static analysis only; chunk 299 of 306 not individually read; behavior not executed.
- Limitation note 300: static analysis only; chunk 300 of 306 not individually read; behavior not executed.
- Limitation note 301: static analysis only; chunk 301 of 306 not individually read; behavior not executed.
- Limitation note 302: static analysis only; chunk 302 of 306 not individually read; behavior not executed.
- Limitation note 303: static analysis only; chunk 303 of 306 not individually read; behavior not executed.
- Limitation note 304: static analysis only; chunk 304 of 306 not individually read; behavior not executed.
- Limitation note 305: static analysis only; chunk 305 of 306 not individually read; behavior not executed.
- Limitation note 306: static analysis only; chunk 306 of 306 not individually read; behavior not executed.
- Limitation note 307: static analysis only; chunk 307 of 306 not individually read; behavior not executed.
- Limitation note 308: static analysis only; chunk 308 of 306 not individually read; behavior not executed.
- Limitation note 309: static analysis only; chunk 309 of 306 not individually read; behavior not executed.
- Limitation note 310: static analysis only; chunk 310 of 306 not individually read; behavior not executed.
- Limitation note 311: static analysis only; chunk 311 of 306 not individually read; behavior not executed.
- Limitation note 312: static analysis only; chunk 312 of 306 not individually read; behavior not executed.
- Limitation note 313: static analysis only; chunk 313 of 306 not individually read; behavior not executed.
- Limitation note 314: static analysis only; chunk 314 of 306 not individually read; behavior not executed.
- Limitation note 315: static analysis only; chunk 315 of 306 not individually read; behavior not executed.
- Limitation note 316: static analysis only; chunk 316 of 306 not individually read; behavior not executed.
- Limitation note 317: static analysis only; chunk 317 of 306 not individually read; behavior not executed.
- Limitation note 318: static analysis only; chunk 318 of 306 not individually read; behavior not executed.
- Limitation note 319: static analysis only; chunk 319 of 306 not individually read; behavior not executed.
- Limitation note 320: static analysis only; chunk 320 of 306 not individually read; behavior not executed.
- Limitation note 321: static analysis only; chunk 321 of 306 not individually read; behavior not executed.
- Limitation note 322: static analysis only; chunk 322 of 306 not individually read; behavior not executed.
- Limitation note 323: static analysis only; chunk 323 of 306 not individually read; behavior not executed.
- Limitation note 324: static analysis only; chunk 324 of 306 not individually read; behavior not executed.
- Limitation note 325: static analysis only; chunk 325 of 306 not individually read; behavior not executed.
- Limitation note 326: static analysis only; chunk 326 of 306 not individually read; behavior not executed.
- Limitation note 327: static analysis only; chunk 327 of 306 not individually read; behavior not executed.
- Limitation note 328: static analysis only; chunk 328 of 306 not individually read; behavior not executed.
- Limitation note 329: static analysis only; chunk 329 of 306 not individually read; behavior not executed.
- Limitation note 330: static analysis only; chunk 330 of 306 not individually read; behavior not executed.
- Limitation note 331: static analysis only; chunk 331 of 306 not individually read; behavior not executed.
- Limitation note 332: static analysis only; chunk 332 of 306 not individually read; behavior not executed.
- Limitation note 333: static analysis only; chunk 333 of 306 not individually read; behavior not executed.
- Limitation note 334: static analysis only; chunk 334 of 306 not individually read; behavior not executed.
- Limitation note 335: static analysis only; chunk 335 of 306 not individually read; behavior not executed.
- Limitation note 336: static analysis only; chunk 336 of 306 not individually read; behavior not executed.
- Limitation note 337: static analysis only; chunk 337 of 306 not individually read; behavior not executed.
- Limitation note 338: static analysis only; chunk 338 of 306 not individually read; behavior not executed.
- Limitation note 339: static analysis only; chunk 339 of 306 not individually read; behavior not executed.
- Limitation note 340: static analysis only; chunk 340 of 306 not individually read; behavior not executed.
- Limitation note 341: static analysis only; chunk 341 of 306 not individually read; behavior not executed.
- Limitation note 342: static analysis only; chunk 342 of 306 not individually read; behavior not executed.
- Limitation note 343: static analysis only; chunk 343 of 306 not individually read; behavior not executed.
- Limitation note 344: static analysis only; chunk 344 of 306 not individually read; behavior not executed.
- Limitation note 345: static analysis only; chunk 345 of 306 not individually read; behavior not executed.
- Limitation note 346: static analysis only; chunk 346 of 306 not individually read; behavior not executed.
- Limitation note 347: static analysis only; chunk 347 of 306 not individually read; behavior not executed.
- Limitation note 348: static analysis only; chunk 348 of 306 not individually read; behavior not executed.
- Limitation note 349: static analysis only; chunk 349 of 306 not individually read; behavior not executed.
- Limitation note 350: static analysis only; chunk 350 of 306 not individually read; behavior not executed.
- Limitation note 351: static analysis only; chunk 351 of 306 not individually read; behavior not executed.
- Limitation note 352: static analysis only; chunk 352 of 306 not individually read; behavior not executed.
- Limitation note 353: static analysis only; chunk 353 of 306 not individually read; behavior not executed.
- Limitation note 354: static analysis only; chunk 354 of 306 not individually read; behavior not executed.
- Limitation note 355: static analysis only; chunk 355 of 306 not individually read; behavior not executed.
- Limitation note 356: static analysis only; chunk 356 of 306 not individually read; behavior not executed.
- Limitation note 357: static analysis only; chunk 357 of 306 not individually read; behavior not executed.
- Limitation note 358: static analysis only; chunk 358 of 306 not individually read; behavior not executed.
- Limitation note 359: static analysis only; chunk 359 of 306 not individually read; behavior not executed.
- Limitation note 360: static analysis only; chunk 360 of 306 not individually read; behavior not executed.
- Limitation note 361: static analysis only; chunk 361 of 306 not individually read; behavior not executed.
- Limitation note 362: static analysis only; chunk 362 of 306 not individually read; behavior not executed.
- Limitation note 363: static analysis only; chunk 363 of 306 not individually read; behavior not executed.
- Limitation note 364: static analysis only; chunk 364 of 306 not individually read; behavior not executed.
- Limitation note 365: static analysis only; chunk 365 of 306 not individually read; behavior not executed.
- Limitation note 366: static analysis only; chunk 366 of 306 not individually read; behavior not executed.
- Limitation note 367: static analysis only; chunk 367 of 306 not individually read; behavior not executed.
- Limitation note 368: static analysis only; chunk 368 of 306 not individually read; behavior not executed.
- Limitation note 369: static analysis only; chunk 369 of 306 not individually read; behavior not executed.
- Limitation note 370: static analysis only; chunk 370 of 306 not individually read; behavior not executed.
- Limitation note 371: static analysis only; chunk 371 of 306 not individually read; behavior not executed.
- Limitation note 372: static analysis only; chunk 372 of 306 not individually read; behavior not executed.
- Limitation note 373: static analysis only; chunk 373 of 306 not individually read; behavior not executed.
- Limitation note 374: static analysis only; chunk 374 of 306 not individually read; behavior not executed.
- Limitation note 375: static analysis only; chunk 375 of 306 not individually read; behavior not executed.
- Limitation note 376: static analysis only; chunk 376 of 306 not individually read; behavior not executed.
- Limitation note 377: static analysis only; chunk 377 of 306 not individually read; behavior not executed.
- Limitation note 378: static analysis only; chunk 378 of 306 not individually read; behavior not executed.
- Limitation note 379: static analysis only; chunk 379 of 306 not individually read; behavior not executed.
- Limitation note 380: static analysis only; chunk 380 of 306 not individually read; behavior not executed.
- Limitation note 381: static analysis only; chunk 381 of 306 not individually read; behavior not executed.
- Limitation note 382: static analysis only; chunk 382 of 306 not individually read; behavior not executed.
- Limitation note 383: static analysis only; chunk 383 of 306 not individually read; behavior not executed.
- Limitation note 384: static analysis only; chunk 384 of 306 not individually read; behavior not executed.
- Limitation note 385: static analysis only; chunk 385 of 306 not individually read; behavior not executed.
- Limitation note 386: static analysis only; chunk 386 of 306 not individually read; behavior not executed.
- Limitation note 387: static analysis only; chunk 387 of 306 not individually read; behavior not executed.
- Limitation note 388: static analysis only; chunk 388 of 306 not individually read; behavior not executed.
- Limitation note 389: static analysis only; chunk 389 of 306 not individually read; behavior not executed.
- Limitation note 390: static analysis only; chunk 390 of 306 not individually read; behavior not executed.
- Limitation note 391: static analysis only; chunk 391 of 306 not individually read; behavior not executed.
- Limitation note 392: static analysis only; chunk 392 of 306 not individually read; behavior not executed.
- Limitation note 393: static analysis only; chunk 393 of 306 not individually read; behavior not executed.
- Limitation note 394: static analysis only; chunk 394 of 306 not individually read; behavior not executed.
- Limitation note 395: static analysis only; chunk 395 of 306 not individually read; behavior not executed.
- Limitation note 396: static analysis only; chunk 396 of 306 not individually read; behavior not executed.
- Limitation note 397: static analysis only; chunk 397 of 306 not individually read; behavior not executed.
- Limitation note 398: static analysis only; chunk 398 of 306 not individually read; behavior not executed.
- Limitation note 399: static analysis only; chunk 399 of 306 not individually read; behavior not executed.
- Limitation note 400: static analysis only; chunk 400 of 306 not individually read; behavior not executed.


## Appendix E — UI details (desktop, extracted from CSS)

```
CSS files: 96

COLORS (313):
#000
#0000
#00000003
#00000005
#0000000a
#0000000d
#00000012
#00000014
#00000017
#0000001a
#0000001f
#00000024
#00000026
#00000029
#0000002b
#00000030
#00000038
#0000003b
#0000003d
#00000040
#00000042
#00000045
#0000004d
#00000054
#00000061
#0000006b
#00000070
#00000073
#00000075
#0000007a
#00000080
#00000082
#0000008a
#0000008c
#00000094
#00000096
#000000a3
#000000a6
#000000a8
#000000ad
#000000b3
#000000b8
#000000bf
#000000d9
#000000e6
#0003
#0006
#0009
#000c
#003d00
#006bcf
#009948
#00af38
#00f
#040404
#052a56
#056952
#063368
#073116
#073c7b
#084791
#093c1b
#094b9a
#0951a6
#0a0a0a
#0a4620
#0a59b8
#0b0b0b
#0b62c8
#0c69d8
#0d5928
#0d72ea
#0e642d
#0e804e
#0ff
#107434
#121212
#12121200
#1212120f
#12121214
#1212121a
#1212121f
#12121229
#1212123d
#12121273
#12121287
#1212128c
#121212a1
#121212b3
#121212b8
#121212cc
#121212d9
#1278f2
#127e38
#12833a
#141414
#159542
#169f47
#171418
#171717
#1737b1
#180270
#181818
#191919
#19e68c
#1a1a1a
#1a1a1af2
#1a2867
#1a4171
#1abc54
#1b1b1b
#1db954
#1e1e1e
#1e1e1e00
#1e1e1eb3
#1ed760
#1ed76000
#1ed76014
#1ed7601f
#1ed7604d
#1f1f1f
#1f307b
#1fdf64
#202124
#202f72
#212121
#21783d99
#21df65
#232323
#242424
#252525
#25252500
#26008d
#272822
#282828
#292929
#2a2a2a
#2a86f3
#2b2b2b
#2c0096
#2e77d0
#3003e1
#332f33
#333
#334fcd
#343434
#363636
#3673d4
#393838
#3a3939
#3be477
#3c00e4
#3e3e3e
#444
#454545
#464348
#4687d6
#484349
#491e00
#509bf5
#525151
#535353
#5353534d
#535353b3
#539df5
#582400
#590810
#5a5a5a
#5b6dff
#5e5e5e
#5eac96
#60e890
#616161
#626262
#652a00
#656565
#65d46e
#66d9ef
#6a6a6a
#6b0a13
#717171
#727272
#7358ff
#73aff7
#747474
#75715e
#75777c
#7b0b16
#7c7c7c
#7d7d7d
#7f7f7f
#818181
#828080
#833600
#844b1f
#868087
#8a8a8a
#9334f5
#939393
#955500
#96f0b6
#999
#9999994d
#9b0e1c
#9bc7fa
#a1ecb2
#a5ccfa
#a60e1d
#a6e22e
#a7a7a7
#a7a7a700
#a7a7a733
#a9a9a9
#aab6ea
#abb2bf
#ae81ff
#af2896
#afb1ff
#b00d6e
#b3b3b3
#bf6d00
#c4caff
#c5f0c9
#c5f7d7
#c6f1d2
#c7c7c7
#c8e0fc
#c91123
#c98335
#cbcbcb
#ccc
#cd1a2b
#d2d2d2
#d3d3d3
#d5d5d5
#d7dbff
#d81326
#d9d9d9
#d9dadc
#dcdcdc
#dedede
#e0edfd
#e22134
#e2e2e2
#e61e32
#e6db74
#e6e6e6
#e7e7e7
#e7edff
#e80
#e91429
#e94e35
#ed2c3f
#edffff
#ee3a4c
#eee
#f0e6d2
#f0f0f0
#f18900
#f19488
#f3727f
#f3e6d0
#f3ff46
#f59b23
#f5f5f5
#f79bd2
#f8f8f2
#f92672
#f96057
#fce54f
#ff4834
#ffa42b
#ffa5000d
#ffa5001a
#ffa5004d
#ffadb6
#ffb504
#ffb656
#ffb9c1
#ffc742
#ffcdd3
#ffd2d7
#ffd2d700
#ffd2d714
#ffd97e
#ffe5e8
#ffeab8
#ffedd0
#fff
#fff0
#fff3
#fff6
#fff9
#ffffff0d
#ffffff12
#ffffff14
#ffffff1a
#ffffff1c
#ffffff21
#ffffff24
#ffffff26
#ffffff2b
#ffffff36
#ffffff3d
#ffffff40
#ffffff4d
#ffffff70
#ffffff80
#ffffff8c
#ffffffa8
#ffffffad
#ffffffb3
#ffffffe6

FONT-SIZES (22):
0
1.125rem
1.5rem
10px
11px
12px
13px
14px
16px
18px
1rem
20px
24px
2rem
32px
36px
3rem
4.5rem
48px
7px
8px
9px

DIMS (303):
0
0%
0px
1
1.15
1.2
1.25rem
1.2em
1.3
1.375
1.4
1.4em
1.5
1.5em
1.5rem
1.6
10
100
100%
1000%
1000px
100px
102px
104.125px
1069px
10px
11
110%
1100px
110px
112px
113.778px
114px
115%
1170px
1199px
11px
1200px
120px
1248px
124px
1280px
128px
12px
130px
131px
134px
135px
136px
13px
1400px
140px
144px
145%
145px
14px
150px
152px
156.444px
156px
15px
160px
162px
165px
1680px
168px
16px
170px
172px
173px
176px
177px
17px
18.275px
180px
181px
182px
184px
186px
188px
18px
192px
1955px
195px
196px
199px
19px
1em
1px
1rem
2
2%
2.2px
20%
200%
200px
20px
210px
215px
216px
21px
220px
228px
22px
230px
232
232px
23px
240px
248px
24px
25
25%
250px
256px
258px
25px
260px
262px
263px
266px
26px
270px
272px
27px
280px
284px
288px
28px
292px
29px
2px
3
30
30%
300px
302px
304px
30px
310px
318px
319px
320px
325px
32px
330px
332px
336px
340px
343px
344px
346px
347px
34px
35
35%
350px
352px
354px
35px
360px
368px
36px
372px
380px
384px
387px
38px
39.94px
390px
392px
395px
398px
3px
4%
40
40%
400px
401px
404px
40px
41%
420px
42px
430px
436px
43px
440px
441px
44px
45%
450px
456px
45px
46%
460px
480px
48px
490px
4px
5
5%
50
50%
500px
509px
50px
51%
516px
51px
520px
524px
52px
540px
541px
542px
544px
545px
546px
54px
55%
55px
56.25%
56.25px
560px
56px
57px
58
588px
590px
5px
60
60%
600px
607px
60px
620px
62px
64px
650px
656px
65px
664px
672px
680px
68px
69px
6px
7
70
70%
700px
702px
70px
72%
720px
722px
728px
72px
732px
74px
75
75%
75px
760px
768px
77%
780px
790px
7px
8
8%
80
80%
800px
80px
810px
816px
82%
83px
85%
85.3333px
85px
860px
86px
88%
88px
8px
9.091px
90
90%
900px
90px
92px
93.25%
95%
96px
97px
99%
9999px
999px
99px
9px

CSS CLASSES (sample, 6792 total):
001dpcm
008l3
01px
04em
0631
073deg
091px
102s
1136deg
113px
119s
125px
125rem
125s
136s
1416
153s
15em
174px
187s
1rem
204s
214286s
221s
238s
24px
25em
25px
25rem
262deg
275px
286px
29px
3333px
35rem
41828
429px
4444px
444px
52-1
547deg
5625rem
571px
58173
5rem
5turn
625rem
6667
6667px
67857
67px
6875rem
714px
75em
75rem
778px
781-1
798-6
8125rem
857px
85em
85rem
875rem
87deg
8889px
8rem
9286
94px
A00ytIkfiVLT_B75PUH2
A0ASfo3Up_Q7kSd9LYAo
A0aVPBUfP5lhm6OeY9Zl
A0d118PwEnutcDguyfK6
A1FdIRTgEpEi0gTR2EGF
A1UY_q_XQTI3cdXq2w7G
A1j5Hz8CVOTfbB_upCBA
A2C3kFi_7YgCMyvuSRH3
A43CJUnLyI16C23ydaIV
A6ChVyOdaEyaumPepLej
A6OB2PW88hienapJaToK
A7EwjqDqW6aS4XMLuBtw
A7mBjDbIpCRtMDP5huvS
A9gtWYENmavLTb5B1jNS
A9tuM6Z5sna0RfRdQYig
AAgyN1hOBaMCwuH77SG1
AAozweyDzh7Lh5Vl9gIq
AAuM5PQulSkIiLlLzqvw
ABE7IpMeHVdMAa347DGn
ABHJbI_KPm4yNHlvS_rs
ADDVzmq6X7myuWFl4ix9
ADvBeZp8CRbDOQ_ypzSs
AE3dcjFNJ9068_vrnLB6
AEyAf4M8Pm3aJXcIAST0
AFJ6kQcR728TRbh6wzd3
AG3esSS4i3_oMRua1H0h
AGZ07cKMDP02RMdAraw_
AGZXsE8Q7LnlcJOX7sxG
AH7NYlNWNDPQhMeIZg7A
AHZaRkL7Dlce8waWLT4j
AJq8LgyOesBON70IHx1V
AJsl04LbtYQ3oh4j_ja3
AJtBVIfJl6Ppw83SqbTl
AKXRAFsX_tj7m8a7vfug
ALSpVd0_ZgOUhlgnH2a0
ALuhjLS8371ZOWex5SLt
AMNaKvCRDGoAyl4ltPZg
AMVlM6fEn3SuEBdoYPhc
AN2Yj8Ork1d6Vy_m5URV
AN5Yp3_RQTWvmVLyQCKt
AN_Jg5L5weM0cDia6BJV
ANiPcscKp65KIfKPP3Ug
AOJOzRAi_iZLBIg2DYSy
APekVsztlCSJPZPDEcPa
ARB2mx8LtjJK0vrtlyoU
ARExkcCu8Pl4pJoG5RyL
ARFtHvFvxYATAELqh3qJ
ARJk_lJ1RhlFwDqGJ67N
ARg85StCOzvvgDpAasA6
ASPpoYqIhLFbLNR_7IQR
ASQmeIrel2Nt6w6h0B1g
ASmPrfZsJoCj4BnGGS7o
ATzSlFakPhgCcp6m2wgQ
AU3t7gHRa1kOM0Lt7y1m
AWZB_jUImxPQPayEBTk4
AWgeyMyAWiokxwNMissg
AWpY880Uv1efXSCOa5h3
AX9wa9pIrKWPfvm8ojDp
AXdeaMV_MPu7ItiFq8cI
AXsGGGuygUDLRRsrx_3X
AXwy9aN2Edi6OZbtlDJi
AYsj7QTQZIee2fvqtU1d
A_dgCpuNz1P_9_RPygVC
A_usQZe3y5Fte9TTYFOo
Aa8Q1IvIum3HH4nBBx9U
AaSktRRoRSIVR9dzIM_r
Aak210rzDyq3s0ey_JqA
Ab9m3cFd7kDmWFaEb_mF
AbJ40VckzE3uXcd5wrEm
AbScaW74nxRaq_eRMqKt
AbgIcOI7V91nxvT91HCH
AcfgMsOtK8XTBUifkDzQ
AcpiGT66pFr3um9wJSvv
AeJ0cPAB_6JC5aScvJdj
AfEpJc9nwz421gpbaFCE
AfXLENOMH2E99i_IqkS3
AfoNs5RyleYPffKd_R7w
AgeR2pcrL1KgHsSM_5CS
AghbWDtmF94XAEQKPhJL
Ags0262YLWorDd87KLq4
AhUvgakGKgwLMNwEiKjw
Ait3YQeNJlTKmk1fB8BF
Ajf7eVlIyU_T8xs6QWjo
AkdxZVE6rBHW7C7Py3GJ
AliJCDn_RWIQGhBo9KkG
Am2BK_y996hhbvSuY7fJ
Amp4nF9uCTsVscG68FIY
An48XMbfJ3_Lu2VXAvEM
AnenzPzbe3bzZWCsoSAz
ApWs6wGARMhpbXAY3Ibr
AphHedkQ88YYuFqJstST
Aq9kfRSAp_KH4hffk1Yh
ArBT7ePdHr8px0JhcxHA
ArQKCGxixqtXg2wFnQdw
ArpdzWdgRW_8lwpikPGW
ArxBBqfEzUGT1nEXkgIs
As1eOhbYz7c7EWJhFEG2
As2bdQZnoOEI59FJvenu
At9tNlKrBKqd5PH17V_A
Au57h2FKsL4DYeQ5bueD
AukMNaKTJmhKlzn1fQYw
Avo4EFdgoNTfpkWOMSfB
Avs3Ur6n7mVZQqdyCWMi
AwSJhnqvE4ZY6eqQNwLz
AyQuHx4nhILLZ2tOcDiA
AzyibAhHsGbHLZZ7F51C
B0KFyBHd0EPlILNOCgtc
B2ZL1NcZub38MXCMkkBV
B4MaZF5xX8Ea6aP5du7Q
B4Nx02PY95HyEV1qmES5
B4pcnR8ZzjyDheRTymNF
B4wFeLHvto8GPiLgySGN
B6GNJVGJUkryORNDGgVe
B6cZwYGBiPMHAmRpT0G6
B7I23cSfqpQuBfW1tXHw
BA5ge_uDv8IxkEX3YNPq
BDayDINV23EvKtWpqSnf
BDoqMer1Ahv9hfbOSyfq
BE84Z9a3f03AONjbtt3G
BEfqS11n6ZkBfjO_haf7
BFb4sxVxXiZ5BQGpEwpw
BFdWMHIyHwu4wSZAz0ro
BGHUeQm5hyByuP4VnuHT
BGJckXXdnQwZq2fM_KsF
BGhZPOSLBDSLTSX9dkjg
BGpNR2ATNLYOv5Juoyew
BIfMBjaz2vdcF02gb3Zc
BJqJySSzlI4DyubvVeTO
BKSy1FhNKrGmUPkur9gp
BKbT1UzV_f_Xdg3iqqM9
BLuU_uUOqGQxEtqPS9fl
BLv_CBRziFqhk1151qrO
BLyR2sy264QNLoTjjIBq
BMCc2xqUeoDwqc8_Ki2N
BN4wtg8CFbEhZ73PP0s5
BNplZfNKl3Z3PNuZ08ev
BNtmn81d3eXkOVoIhBmT
BOhtPhjLJMM1YsUYH3pc
BOp1wulEuJMGTUaS8E4k
BQL_nTlQ35NPm4El_yKA
BQMlbPRxc3MrAxkMYY67
BQN3gZkYy33eP4L0Xsxu
BQTr93hsT42DmFCZzl_V
BSupLcO5BQHPmyPdy2Ke
BTVl5mVQ1NwcNvFjI0Pu
BW1_Si1aZVLfZdqnhOv0
BWGnkJP0kpVmadBk1wbJ
BZ1BO4pZI15mL9i_4zdu
BZ2EqTq2wilqzcwxqd0w
BZ3Jt_10IWjNI_HzYaNc
BZ6U78GhhbO_YG8QYmtj
BZJYEs3mPwmfZOIMu9QP
BZ_gu143OwHoRCSlbNx4
BZ_wyQGzjGPyAb4rJ0mk
B_D2OFEQueOg8eoiZpD1
B_DQfynJis7GctE_3xk3
B_FSnd305wrLHs_WqSsd
B_NENXC7AHTEKsYhv3qv
B_nE1SXTRHeQqKgcaVhj
Ba8tV4UWPn3veeWuciOn
BaIFqcPPx3oYlya5euQv
BaSRmgCEnGgCZ0mmxapX
BafPkxIFo223uGEPzQL7
BbkMzFYBIqdJbTQh6J1_
BcPE0f085UfONbjc6laI
BcjfOpNfJveVSmBKuxPf
BcmsyzTf_7mOFSn9ox4v
BeXyTTl0CTmtEmOeeiGr
BfLC3iZs1LcKzTd2rMjp
BgMd6ZnJzW1dDyZeFwms
BgxYPqzCnc07O2uZ4l_0
BhKyuJA1t39nvRDnQgc9
BhNYSPm9SLmMyVZ1_2nJ
BicuAI_Ti7tMosZx6feA
Bj3zgcB9FJBBRCyaGHKI
BjobZBzDZLf5f78AT4dG
Bjx3sG2WYD9QVKP7Nqu2
BkqqN7tGwyJHa5ERvXkK
BlQybTWuGSOWzJhGj8wn
BmXBjNWNbPEF1TN9aJf4
BmrQQUfZPj1yxmGd02zS
BmysoadRi6sBXB4O2dBd
Bn4osAsrhHbxhDrGzPz7
BnCN46iNbXY6rENdQd5G
BnCn0CJyXhgSU_Rve9Be
BnySKqTgOQJMJk28aNgY
BowGXmrv97DQDLKM3Zm0
BpfDz9BVog90st5sYrNX
BpyMKZ6p9zOab1vMJDEZ
BsFzH12CAJta6W2JLPxW
BsuCEMHjP8OA0vRxN1UQ
BuqVQZynpkqqVo9R8Qm6
Bv3Jtv_ZS7rJGhowFL9J
BvYRI0WFCn3LhurvyYJg
BvYel9KAh_CVFpiGOjNZ
BxHKeqsgJL1Wh4tJuA2l
By4wE_aVhuYtLizakqDZ
BybkyB7XLrG9C8Njo6mw
Byh_OEeqggMiyq73Wqg8
Byp1BxVFY59xFQo0QW5X
BzZwajlIOyQ0SRRQk2bJ
C09p36zbJu0oxospFtEe
C0YTSqDKL6_Qo68om_i1
C0lD2uwCKHb1ZF7jucqx
C0tmrgNCw0nii1L57kU7
C1sfXQNdcsLReHgohV5Z
C2Sk74W6RXTckFrl3KgE
C3vYvgR_88lop3dcB20g
C5c5FceZn9Iaz8gPMGau
C5ehxNjkIbRm0rSsiGx7
C6eWO3StB4YpPGEenyaA
C6rjZ9exSW1JVyBTZ4Tp
C75qbkiTmyN9lo22Ocgb
C7cZi_r4kXJXHQfCIkc0
C9G_CSzsikvZtcHoIzUN
C9YkqeY1CGcU5Tso1KAU
CA3vl2pO5p6xEV5QWd3z
CAP54BpfdsYIPrtt0Ek6
CBRIzkqEDnF2p5WwylAT
CCtDvsJegaD38ITjHhMb
CDEzy64vbiIOxCrXhaK6
CDdQmPsvFDpN_d6NMZK4
CEBF_u074YaDntH4yGLm
CEG2qtUZNYv1hPTSMUtF
CF_GhwTjpjL4KW9eVBoQ
CFomZDDshES6ruC56TkT
CFzZeYAU6wukv5cmZB1m
CJdibeUQyl_Os98lLiMY
CM1JaGeFuBsHsoRC5pZb
CMwIn3IJXyTEgOTaoX6X
CNK4b0gm6XuB2gX869TA
CO8qyPNgRV8ziQnoZDC0
```

### E.1 Observed color palette (sample)

- #000
- #0000
- #00000003
- #00000005
- #0000000a
- #0000000d
- #00000012
- #00000014
- #00000017
- #0000001a
- #0000001f
- #00000024
- #00000026
- #00000029
- #0000002b
- #00000030
- #00000038
- #0000003b
- #0000003d
- #00000040
- #00000042
- #00000045
- #0000004d
- #00000054
- #00000061
- #0000006b
- #00000070
- #00000073
- #00000075
- #0000007a
- #00000080
- #00000082
- #0000008a
- #0000008c
- #00000094
- #00000096
- #000000a3
- #000000a6
- #000000a8
- #000000ad
- #000000b3
- #000000b8
- #000000bf
- #000000d9
- #000000e6
- #0003
- #0006
- #0009
- #000c
- #003d00
- #006bcf
- #009948
- #00af38
- #00f
- #040404
- #052a56
- #056952
- #063368
- #073116
- #073c7b
- #084791
- #093c1b
- #094b9a
- #0951a6
- #0a0a0a
- #0a4620
- #0a59b8
- #0b0b0b
- #0b62c8
- #0c69d8
- #0d5928
- #0d72ea
- #0e642d
- #0e804e
- #0ff
- #107434
- #121212
- #12121200
- #1212120f
- #12121214

### E.2 Key component class names (desktop)

- A00ytIkfiVLT_B75PUH2
- A0ASfo3Up_Q7kSd9LYAo
- A0aVPBUfP5lhm6OeY9Zl
- A0d118PwEnutcDguyfK6
- A1FdIRTgEpEi0gTR2EGF
- A1UY_q_XQTI3cdXq2w7G
- A1j5Hz8CVOTfbB_upCBA
- A2C3kFi_7YgCMyvuSRH3
- A43CJUnLyI16C23ydaIV
- A6ChVyOdaEyaumPepLej
- A6OB2PW88hienapJaToK
- A7EwjqDqW6aS4XMLuBtw
- A7mBjDbIpCRtMDP5huvS
- A9gtWYENmavLTb5B1jNS
- A9tuM6Z5sna0RfRdQYig
- AAgyN1hOBaMCwuH77SG1
- AAozweyDzh7Lh5Vl9gIq
- AAuM5PQulSkIiLlLzqvw
- ABE7IpMeHVdMAa347DGn
- ABHJbI_KPm4yNHlvS_rs
- ADDVzmq6X7myuWFl4ix9
- ADvBeZp8CRbDOQ_ypzSs
- AE3dcjFNJ9068_vrnLB6
- AEyAf4M8Pm3aJXcIAST0
- AFJ6kQcR728TRbh6wzd3
- AG3esSS4i3_oMRua1H0h
- AGZ07cKMDP02RMdAraw_
- AGZXsE8Q7LnlcJOX7sxG
- AH7NYlNWNDPQhMeIZg7A
- AHZaRkL7Dlce8waWLT4j
- AJq8LgyOesBON70IHx1V
- AJsl04LbtYQ3oh4j_ja3
- AJtBVIfJl6Ppw83SqbTl
- AKXRAFsX_tj7m8a7vfug
- ALSpVd0_ZgOUhlgnH2a0
- ALuhjLS8371ZOWex5SLt
- AMNaKvCRDGoAyl4ltPZg
- AMVlM6fEn3SuEBdoYPhc
- AN2Yj8Ork1d6Vy_m5URV
- AN5Yp3_RQTWvmVLyQCKt
- AN_Jg5L5weM0cDia6BJV
- ANiPcscKp65KIfKPP3Ug
- AOJOzRAi_iZLBIg2DYSy
- APekVsztlCSJPZPDEcPa
- ARB2mx8LtjJK0vrtlyoU
- ARExkcCu8Pl4pJoG5RyL
- ARFtHvFvxYATAELqh3qJ
- ARJk_lJ1RhlFwDqGJ67N
- ARg85StCOzvvgDpAasA6
- ASPpoYqIhLFbLNR_7IQR
- ASQmeIrel2Nt6w6h0B1g
- ASmPrfZsJoCj4BnGGS7o
- ATzSlFakPhgCcp6m2wgQ
- AU3t7gHRa1kOM0Lt7y1m
- AWZB_jUImxPQPayEBTk4
- AWgeyMyAWiokxwNMissg
- AWpY880Uv1efXSCOa5h3
- AX9wa9pIrKWPfvm8ojDp
- AXdeaMV_MPu7ItiFq8cI
- AXsGGGuygUDLRRsrx_3X
- AXwy9aN2Edi6OZbtlDJi
- AYsj7QTQZIee2fvqtU1d
- A_dgCpuNz1P_9_RPygVC
- A_usQZe3y5Fte9TTYFOo
- Aa8Q1IvIum3HH4nBBx9U
- AaSktRRoRSIVR9dzIM_r
- Aak210rzDyq3s0ey_JqA
- Ab9m3cFd7kDmWFaEb_mF
- AbJ40VckzE3uXcd5wrEm
- AbScaW74nxRaq_eRMqKt
- AbgIcOI7V91nxvT91HCH
- AcfgMsOtK8XTBUifkDzQ
- AcpiGT66pFr3um9wJSvv
- AeJ0cPAB_6JC5aScvJdj
- AfEpJc9nwz421gpbaFCE
- AfXLENOMH2E99i_IqkS3
- AfoNs5RyleYPffKd_R7w
- AgeR2pcrL1KgHsSM_5CS
- AghbWDtmF94XAEQKPhJL
- Ags0262YLWorDd87KLq4
- AhUvgakGKgwLMNwEiKjw
- Ait3YQeNJlTKmk1fB8BF
- Ajf7eVlIyU_T8xs6QWjo
- AkdxZVE6rBHW7C7Py3GJ
- AliJCDn_RWIQGhBo9KkG
- Am2BK_y996hhbvSuY7fJ
- Amp4nF9uCTsVscG68FIY
- An48XMbfJ3_Lu2VXAvEM
- AnenzPzbe3bzZWCsoSAz
- ApWs6wGARMhpbXAY3Ibr
- AphHedkQ88YYuFqJstST
- Aq9kfRSAp_KH4hffk1Yh
- ArBT7ePdHr8px0JhcxHA
- ArQKCGxixqtXg2wFnQdw
- ArpdzWdgRW_8lwpikPGW
- ArxBBqfEzUGT1nEXkgIs
- As1eOhbYz7c7EWJhFEG2
- As2bdQZnoOEI59FJvenu
- At9tNlKrBKqd5PH17V_A
- Au57h2FKsL4DYeQ5bueD
- AukMNaKTJmhKlzn1fQYw
- Avo4EFdgoNTfpkWOMSfB
- Avs3Ur6n7mVZQqdyCWMi
- AwSJhnqvE4ZY6eqQNwLz
- AyQuHx4nhILLZ2tOcDiA
- AzyibAhHsGbHLZZ7F51C
- B0KFyBHd0EPlILNOCgtc
- B2ZL1NcZub38MXCMkkBV
- B4MaZF5xX8Ea6aP5du7Q
- B4Nx02PY95HyEV1qmES5
- B4pcnR8ZzjyDheRTymNF
- B4wFeLHvto8GPiLgySGN
- B6GNJVGJUkryORNDGgVe
- B6cZwYGBiPMHAmRpT0G6
- B7I23cSfqpQuBfW1tXHw
- BA5ge_uDv8IxkEX3YNPq
- BDayDINV23EvKtWpqSnf
- BDoqMer1Ahv9hfbOSyfq
- BE84Z9a3f03AONjbtt3G
- BEfqS11n6ZkBfjO_haf7

### E.3 Layout tokens

- 1.125rem
- 1.5rem
- 10px
- 11px
- 12px
- 13px
- 14px
- 16px
- 18px
- 1rem
- 20px
- 24px
- 2rem
- 32px
- 36px
- 3rem
- 4.5rem
- 48px
- 7px
- 8px
- 9px
- 0%
- 0px
- 1.25rem
- 1.2em
- 1.4em
- 1.5em
- 1.5rem
- 100%
- 1000%
- 1000px
- 100px
- 102px
- 104.125px
- 1069px
- 10px
- 110%
- 1100px
- 110px
- 112px
- 113.778px
- 114px
- 115%
- 1170px
- 1199px
- 11px
- 1200px
- 120px
- 1248px
- 124px
- 1280px
- 128px
- 12px
- 130px
- 131px
- 134px
- 135px
- 136px
- 13px
- 1400px
- 140px
- 144px
- 145%
- 145px
- 14px
- 150px
- 152px
- 156.444px
- 156px

- UI detail note 1: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 2: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 3: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 4: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 5: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 6: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 7: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 8: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 9: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 10: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 11: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 12: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 13: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 14: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 15: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 16: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 17: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 18: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 19: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 20: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 21: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 22: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 23: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 24: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 25: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 26: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 27: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 28: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 29: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 30: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 31: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 32: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 33: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 34: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 35: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 36: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 37: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 38: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 39: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 40: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 41: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 42: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 43: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 44: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 45: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 46: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 47: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 48: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 49: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 50: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 51: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 52: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 53: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 54: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 55: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 56: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 57: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 58: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 59: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 60: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 61: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 62: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 63: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 64: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 65: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 66: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 67: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 68: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 69: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 70: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 71: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 72: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 73: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 74: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 75: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 76: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 77: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 78: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 79: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 80: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 81: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 82: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 83: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 84: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 85: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 86: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 87: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 88: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 89: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 90: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 91: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 92: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 93: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 94: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 95: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 96: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 97: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 98: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 99: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 100: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 101: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 102: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 103: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 104: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 105: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 106: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 107: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 108: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 109: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 110: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 111: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 112: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 113: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 114: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 115: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 116: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 117: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 118: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 119: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 120: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 121: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 122: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 123: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 124: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 125: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 126: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 127: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 128: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 129: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 130: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 131: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 132: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 133: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 134: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 135: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 136: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 137: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 138: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 139: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 140: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 141: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 142: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 143: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 144: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 145: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 146: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 147: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 148: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 149: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 150: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 151: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 152: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 153: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 154: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 155: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 156: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 157: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 158: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 159: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 160: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 161: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 162: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 163: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 164: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 165: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 166: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 167: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 168: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 169: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 170: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 171: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 172: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 173: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 174: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 175: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 176: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 177: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 178: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 179: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 180: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 181: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 182: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 183: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 184: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 185: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 186: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 187: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 188: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 189: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 190: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 191: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 192: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 193: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 194: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 195: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 196: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 197: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 198: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 199: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
- UI detail note 200: desktop CSS token extraction; values are observed from shipped stylesheets, not runtime.
