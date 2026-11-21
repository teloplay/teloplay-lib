# 🎵 TeloPlay Triple-Engine Integration Guide (For Flutter Implementation)

> **Document Version:** 1.0.0 (Production Verified)  
> **Target Audience:** Flutter Front-End Developers, State Management & Audio Engineers  
> **Status:** 100% Contract Parity Verified Across Windows, Android & Cloudflare Worker

---

## 📑 সূচিপত্র (Table of Contents)
1. [🌟 তিন ইঞ্জিনের আর্কিটেকচার ও কমিউনিকেশন মেথড](#1-তিন-ইঞ্জিনের-আর্কিটেকচার-ও-কমিউনিকেশন-মেথড)
2. [📦 Unified SongItem মডেল (20-Key Invariant Contract)](#2-unified-songitem-মডেল-20-key-invariant-contract)
3. [🚀 সমস্ত এন্ডপয়েন্ট ও কমান্ডের ব্যবহার বিধি](#3-সমস্ত-এন্ডপয়েন্ট-ও-কমান্ডের-ব্যবহার-বিধি)
   - [১. Smart Search (Spotify-Style Discovery)](#১-smart-search-spotify-style-discovery)
   - [২. Stream Resolve (Audio URL & Playback)](#২-stream-resolve-audio-url--playback)
   - [৩. Smart Lyrics (6-Source Synced Karaoke)](#৩-smart-lyrics-6-source-synced-karaoke)
   - [৪. Artist Details & Discography](#৪-artist-details--discography)
   - [৫. Album Details & Tracklist](#৫-album-details--tracklist)
   - [৬. Playlist & Continuous Queue](#৬-playlist--continuous-queue)
   - [৭. Dynamic Locale Switching](#৭-dynamic-locale-switching)
   - [৮. Home, Explore & Charts Feed](#৮-home-explore--charts-feed)
4. [🎯 Flutter-এ কোন স্ক্রিনে কোনটি ব্যবহার হবে (Screen Mapping)](#4-flutter-এ-কোন-স্ক্রিনে-কোনটি-ব্যবহার-হবে-screen-mapping)
5. [🛡️ Best Practices & Defensive Deserialization](#5-best-practices--defensive-deserialization)

---

## 1. তিন ইঞ্জিনের আর্কিটেকচার ও কমিউনিকেশন মেথড

TeloPlay প্ল্যাটফর্ম অনুযায়ী উপযুক্ত ইঞ্জিনটি স্বয়ংক্রিয়ভাবে বেছে নেয়:

```
                  ┌─────────────────────────────────────┐
                  │      FLUTTER CORE AUDIO ENGINE      │
                  └──────────────────┬──────────────────┘
                                     │
      ┌──────────────────────────────┼──────────────────────────────┐
      │ (Desktop: Windows)           │ (Mobile: Android)            │ (Web / Fallback)
      ▼                              ▼                              ▼
┌──────────────────┐          ┌──────────────────┐          ┌──────────────────┐
│  WINDOWS DAEMON  │          │  ANDROID HOST    │          │  CLOUDFLARE EDGE │
│ innertube-cli.jar│          │ MethodChannel    │          │ Worker REST API  │
│ IPC: Line JSON   │          │ com.piyas...     │          │ HTTP + 206 Proxy │
└──────────────────┘          └──────────────────┘          └──────────────────┘
```

| প্ল্যাটফর্ম | ইঞ্জিন টেকনোলজি | কমিউনিকেশন মাধ্যম | রুটিন কল ফরম্যাট |
|---|---|---|---|
| **Windows Desktop** | `innertube-cli.jar` (Kotlin Native Daemon) | Standard I/O (`stdin` / `stdout`) | `proc.stdin.writeln(jsonEncode({"id": reqId, "cmd": command, ...}))` |
| **Android Mobile** | `MainActivity.kt` (Android Host) | Flutter `MethodChannel` (`com.piyas.teloplay/youtube_stream`) | `channel.invokeMethod('command', {'cmd': command, ...})` |
| **Web / Cross-Plat** | Cloudflare Edge Worker | REST API / HTTPS JSON | `http.get('https://teloplay-stream-service.teloplay-verify.workers.dev/api/...')` |

---

## 2. Unified SongItem মডেল (21-Key Invariant Contract)

তিনটি ব্যাকএন্ডের প্রতিটি গান **হুবহু এই ২১টি ফিল্ড** রিটার্ন করে। Dart মডেলে এটি কোনো ফিল্ড ড্রপ না করে ম্যাপ করা আছে:

```dart
class SongItem {
  final String type;             // Always "song"
  final String id;               // "zfWlGsiFDzk"
  final String videoId;          // "zfWlGsiFDzk"
  final String title;            // "Safar (From \"Jab Harry Met Sejal\")"
  final String cleanTitle;       // "Safar" (Uncluttered, perfect for UI)
  final String author;           // Primary artist name: "Pritam"
  final String? artistId;        // "UCuFDzYEZaWlCzxz1B6mKduQ" or null
  final List<String> allArtistNames; // ["Pritam", "Arijit Singh"]
  final List<String?> allArtistIds;  // ["UC...", null] (Index-aligned!)
  final List<ArtistSummary> artists; // [{"name": "Pritam", "id": "UC..."}]
  final String thumbnail;        // Standard thumbnail
  final String highResThumbnail; // 544x544 HD Artwork
  final int duration;            // Duration in seconds (e.g. 217)
  final String? albumId;         // "MPREb_..." or null
  final String? albumName;       // "Safar" or null
  final bool explicit;           // true / false
  final int? chartPosition;      // 1, 2, 3 or null
  final String? chartChange;     // "+2", "NEW" or null
  final String? watchVideoId;    // "zfWlGsiFDzk"
  final String? watchPlaylistId; // "RDAMVMzfWlGsiFDzk"
  final String? setVideoId;      // Playlist specific setVideoId or null

}
```



---

## 3. সমস্ত এন্ডপয়েন্ট ও কমান্ডের ব্যবহার বিধি

### ১. Smart Search (Spotify-Style Discovery)
> **কখন ব্যবহার হবে:** Search Bar-এ ইউজার কোনো কিছু লিখে এন্টার দিলে বা সার্চ করার সাথে সাথে। এটি নয়েজ গান (Cover, Slowed+Reverb) ফিল্টার করে আসল ট্র্যাকটিকে `topResult` (Hero Card) বানায় এবং ১৫টি রেডিও গান প্রস্তুত রাখে।

- **Windows CLI:**
  ```json
  { "id": "1", "cmd": "smart-search", "query": "Safar", "limit": 10 }
  ```
- **Android Host:**
  ```dart
  channel.invokeMethod('command', {'cmd': 'smart-search', 'query': 'Safar', 'limit': 10});
  ```
- **Worker (REST API):**
  ```http
  GET /api/search?q=Safar&mode=smart&limit=10
  ```
- **রেসপন্স স্ট্রাকচার:**
  ```json
  {
    "ok": true,
    "query": "Safar",
    "topResult": { /* Hero Item: SongItem or AlbumItem or ArtistItem */ },
    "songs": [ /* List of 5-10 Scored SongItems */ ],
    "relatedTracks": [ /* 15 Auto-play Radio SongItems */ ],
    "albums": [ /* 5 AlbumItems */ ],
    "artists": [ /* 5 ArtistItems */ ]
  }
  ```

---

### ২. Stream Resolve (Audio URL & Playback)
> **কখন ব্যবহার হবে:** ইউজার যখন কোনো গানে ট্যাপ করবে এবং অডিও প্লেয়ারে গান বাজানো শুরু হবে।

- **Windows CLI:**
  ```json
  { "id": "2", "cmd": "resolve", "videoId": "zfWlGsiFDzk" }
  ```
- **Android Host:**
  ```dart
  channel.invokeMethod('command', {'cmd': 'resolve', 'videoId': 'zfWlGsiFDzk'});
  ```
- **Worker (REST API):**
  ```http
  GET /api/resolve?id=zfWlGsiFDzk
  ```
- **Web / iOS Audio Stream Proxy:**
  ```http
  GET /api/stream/zfWlGsiFDzk  (Supports 'Range: bytes=0-' for instant seek)
  ```
- **রেসপন্স স্ট্রাকচার:**
  ```json
  {
    "ok": true,
    "videoId": "zfWlGsiFDzk",
    "url": "https://rr...googlevideo.com/videoplayback?...",
    "directUrl": "https://rr...googlevideo.com/videoplayback?...",
    "mimeType": "audio/webm; codecs=\"opus\"",
    "format": "webm",
    "bitrate": 152891,
    "duration": 217,
    "title": "Safar",
    "cleanTitle": "Safar",
    "author": "Bayaan",
    "thumbnail": "https://...",
    "highResThumbnail": "https://..."
  }
  ```

---

### ৩. Smart Lyrics (6-Source Synced Karaoke)
> **কখন ব্যবহার হবে:** Now Playing স্ক্রিনে লিরিক্স শিট খুললে বা কারাওকে মুডে থাকলে।

- **Windows CLI:**
  ```json
  { "id": "3", "cmd": "smart-lyrics", "videoId": "zfWlGsiFDzk", "title": "Safar", "artist": "Bayaan", "duration": 217 }
  ```
- **Android Host:**
  ```dart
  channel.invokeMethod('command', {'cmd': 'smart-lyrics', 'videoId': 'zfWlGsiFDzk', 'title': 'Safar', 'artist': 'Bayaan', 'duration': 217});
  ```
- **Worker (REST API):**
  ```http
  GET /api/lyrics?id=zfWlGsiFDzk&title=Safar&artist=Bayaan&duration=217
  ```
- **রেসপন্স স্ট্রাকচার:**
  ```json
  {
    "ok": true,
    "source": "Better Lyrics",
    "syncType": "word_by_word",
    "hasSynced": true,
    "lines": [
      {
        "startTimeMs": 18800,
        "text": "ও সানাম ও জিগার",
        "words": [
          { "text": "ও", "startMs": 18800, "endMs": 19200 },
          { "text": "সানাম", "startMs": 19200, "endMs": 19800 }
        ]
      }
    ]
  }


---

### ৪. Artist Details & Discography
> **কখন ব্যবহার হবে:** Artist Profile স্ক্রিনে (আর্টিস্টের ছবি, বায়ো, টপ সংস, অ্যালবাম ও ফ্যানদের পছন্দ দেখাতে)।

- **Windows CLI:**
  ```json
  { "id": "4", "cmd": "artist", "artistId": "UCuFDzYEZaWlCzxz1B6mKduQ", "limit": 10 }
  ```
- **Android Host:**
  ```dart
  channel.invokeMethod('command', {'cmd': 'artist', 'artistId': 'UCuFDzYEZaWlCzxz1B6mKduQ', 'limit': 10});
  ```
- **Worker (REST API):**
  ```http
  GET /api/artist?id=UCuFDzYEZaWlCzxz1B6mKduQ&limit=10
  ```
- **মূল রেসপন্স ফিল্ডস:** `artistId`, `artistName`, `subscriberCountText`, `monthlyListenerCountText`, `artistBio`, `songs`, `sections`.

---

### ৫. Album Details & Tracklist
> **কখন ব্যবহার হবে:** Album Page-এ (অ্যালবামের কাভার আর্ট, রিলিজ বছর, গানের সংখ্যা ও ট্র্যাকলিস্ট দেখাতে)।

- **Windows CLI:**
  ```json
  { "id": "5", "cmd": "album", "albumId": "MPREb_4OZv6GvrB4E" }
  ```
- **Android Host:**
  ```dart
  channel.invokeMethod('command', {'cmd': 'album', 'albumId': 'MPREb_4OZv6GvrB4E'});
  ```
- **Worker (REST API):**
  ```http
  GET /api/album?id=MPREb_4OZv6GvrB4E
  ```
- **মূল রেসপন্স ফিল্ডস:** `albumId`, `title`, `author`, `year`, `trackCount`, `duration`, `songs` (প্রতিটি গানে `trackNumber: 1, 2, 3...` সাজানো থাকে)।

---

### ৬. Playlist & Continuous Queue
> **কখন ব্যবহার হবে:** কিউরেটেড প্লেলিস্ট পেজ ও অটোমিক্স কিউ (Queue) লোড করতে।

- **Windows CLI:**
  ```json
  { "id": "6", "cmd": "playlist", "playlistId": "PL...", "limit": 50 }
  ```
- **Android Host:**
  ```dart
  channel.invokeMethod('command', {'cmd': 'playlist', 'playlistId': 'PL...', 'limit': 50});
  ```
- **Worker (REST API):**
  ```http
  GET /api/playlist?id=PL...&limit=50
  ```

---

### ৭. Dynamic Locale Switching
> **কখন ব্যবহার হবে:** ইউজার যখন সেটিংসে গিয়ে দেশ (`gl`) বা ভাষা (`hl`) পরিবর্তন করবে।

- **Windows CLI:**
  ```json
  { "id": "7", "cmd": "set-locale", "gl": "BD", "hl": "bn" }
  ```
- **Android Host:**
  ```dart
  channel.invokeMethod('command', {'cmd': 'set-locale', 'gl': 'BD', 'hl': 'bn'});
  ```
- **Worker (REST API):**
  ```http
  যেকোনো রিকোয়েস্টের সাথে কুয়েরি প্যারামিটার পাস করুন: ?gl=BD&hl=bn
  ```

---

### ৮. Home, Explore & Charts Feed
> **কখন ব্যবহার হবে:** Home Screen এবং Explore ট্যাবে ট্রেন্ডিং চার্ট ও নতুন রিলিজ গান দেখাতে।

- **Home Feed:** `cmd: "home"` | `/api/home`
- **Charts (Top 100):** `cmd: "charts"` | `/api/charts`
- **Moods & Genres:** `cmd: "moods-and-genres"` | `/api/moods-and-genres`
- **New Releases:** `cmd: "explore"` | `/api/explore`

---

## 4. Flutter-এ কোন স্ক্রিনে কোনটি ব্যবহার হবে (Screen Mapping)

```
┌─────────────────────────┬────────────────────────────────────────┬────────────────────────────────────────┐
│ FLUTTER SCREEN          │ PRIMARY BACKEND CALL                   │ FALLBACK / SECONDARY CALL              │
├─────────────────────────┼────────────────────────────────────────┼────────────────────────────────────────┤
│ 🏠 Home Screen          │ cmd: "home" (Personalized Sections)    │ Supabase (Recently Played / Favs)      │
│ 🔍 Search Screen        │ cmd: "suggest" (Autocomplete Chips)    │ Local Recent Searches (Hive)           │
│ 🔎 Search Results       │ cmd: "smart-search" (Top Match + Radio)│ Filtered Search (cmd: "search-filter") │
│ 🎵 Now Playing Screen   │ cmd: "resolve" (Instant Playback URL)  │ Worker /api/stream (Range Proxy)       │
│ 📜 Lyrics Sheet         │ cmd: "smart-lyrics" (Karaoke Syllable) │ YouTube Music Plain Captions           │
│ 👤 Artist Profile       │ cmd: "artist" (Bio, Top Songs, Albums) │ Related Artists                        │
│ 💿 Album Details        │ cmd: "album" (Numbered Tracklist)      │ Album Radio Queue                      │
│ 🌐 Explore / Charts     │ cmd: "charts" & cmd: "explore"         │ cmd: "moods-and-genres"                │
│ 💾 Offline Library      │ Local Hive Cache (Downloads & Favs)    │ Supabase (Batch sync on reconnect)     │
└─────────────────────────┴────────────────────────────────────────┴────────────────────────────────────────┘
```

---

## 5. Best Practices & Defensive Deserialization

Flutter ক্লায়েন্টে ডেটা পার্স করার সময় নিচের ডিফেন্সিভ প্যাটার্নটি অনুসরণ করুন:

```dart
// 安全 Deserialization Helper for SongItem
factory SongItem.fromJson(Map<String, dynamic> json) {
  return SongItem(
    type: json['type'] as String? ?? 'song',
    id: (json['id'] ?? json['videoId'] ?? '') as String,
    videoId: (json['videoId'] ?? json['id'] ?? '') as String,
    title: (json['title'] ?? 'Unknown Track') as String,
    cleanTitle: (json['cleanTitle'] ?? json['title'] ?? 'Unknown Track') as String,
    author: (json['author'] ?? 'Unknown Artist') as String,
    artistId: json['artistId'] as String?,
    allArtistNames: (json['allArtistNames'] is List)
        ? (json['allArtistNames'] as List).map((e) => e.toString()).toList()
        : [(json['author'] ?? 'Unknown Artist') as String],
    allArtistIds: (json['allArtistIds'] is List)
        ? (json['allArtistIds'] as List).map((e) => e?.toString()).toList()
        : [],
    thumbnail: (json['highResThumbnail'] ?? json['thumbnail'] ?? '') as String,
    highResThumbnail: (json['highResThumbnail'] ?? json['thumbnail'] ?? '') as String,
    duration: (json['duration'] is int)
        ? json['duration'] as int
        : int.tryParse(json['duration']?.toString() ?? '0') ?? 0,
    albumId: json['albumId'] as String?,
    albumName: json['albumName'] as String?,
    explicit: json['explicit'] as bool? ?? false,
    chartPosition: json['chartPosition'] as int?,
    chartChange: json['chartChange'] as String?,
    watchVideoId: json['watchVideoId'] as String?,
    watchPlaylistId: json['watchPlaylistId'] as String?,
  );
}
```

