# 🎵 TeloPlay Stream Service

> **High-Performance, Botless, Zero-Login Audio Streaming & YouTube Music Metadata Microservice**  
> Built for Cloudflare Workers & Node.js edge environments to power TeloPlay across Web, Android, iOS, Windows, and macOS.

---

## 📑 সূচিপত্র (Table of Contents)
1. [🌟 মূল উদ্দেশ্য ও আর্কিটেকচার (Overview)](#-মূল-উদ্দেশ্য-ও-আর্কিটেকচার)
2. [🛡️ কীভাবে Bot-Proof ও Login-Free সার্ভিস দেওয়া হয়](#️-কীভাবে-bot-proof-ও-login-free-সার্ভিস-দেওয়া-হয়)
3. [🔒 সিকিউরিটি ও আর্কিটেকচারাল প্রোটেকশন প্ল্যান](#-সিকিউরিটি-ও-আর্কিটেকচারাল-প্রোটেকশন-প্ল্যান)
4. [🚀 সমস্ত API Endpoints ও ব্যবহারের নিয়ম (API Reference)](#-সমস্ত-api-endpoints-ও-ব্যবহারের-নিয়ম)
   - [Health & Ping](#1-get-apiping)
   - [Stream Resolver & Audio Proxy](#2-get-apiresolve--get-apistreamvideoid)
   - [Search & Filter](#3-get-apisearch--get-apisearch-filter)
   - [Search Suggestions (Autocomplete + Cards)](#4-get-apisuggest)
   - [Song Details & Related Tracks](#5-get-apisong)
   - [Artist Details & Discography](#6-get-apiartist)
   - [Album Details & Tracklist](#7-get-apialbum)
   - [Playlist & Pagination](#8-get-apiplaylist--get-apiplaylist-continuation)
   - [Watch Next & Radio Queue (Autoplay)](#9-get-apinext)
   - [Synced & Plain Lyrics](#10-get-apilyrics)
   - [Explore, Home, Charts, Moods & New Releases](#11-explore-home-charts-moods--new-releases)
5. [📦 Standard Data Model (OpenTune Compatibility)](#-standard-data-model)
6. [🛠️ লোকাল ডেভেলপমেন্ট ও ডিপ্লয়মেন্ট](#️-লোকাল-ডেভেলপমেন্ট-ও-ডিপ্লয়মেন্ট)

---

## 🌟 মূল উদ্দেশ্য ও আর্কিটেকচার

TeloPlay Stream Service হলো একটি লাইটওয়েট এবং অত্যন্ত দ্রুতগতির (<30ms মেটাডেটা লেটেন্সি) এজ মাইক্রোসার্ভিস। এটি YouTube Music-এর বিশাল ক্যাটালগ ও LRCLib-এর লিরিক্স ডেটাবেসকে একত্রিত করে ক্লায়েন্ট অ্যাপ্লিকেশনের (Flutter Web/Android/Desktop) জন্য একটি ওপেন এবং স্ট্যান্ডার্ড REST API প্রদান করে।

- **সম্পূর্ণ অ্যানোনিমাস (Anonymous):** ব্যবহারকারীর কোনো ব্যক্তিগত ডেটা, অ্যাকাউন্ট কুকি বা লগইন ক্রেডেনশিয়াল লাগে না।
- **জিরো ডিপেন্ডেন্সি ব্লট (Zero Bloat):** মেটাডেটা পার্সিংয়ের জন্য ভারী ব্রাউজার এমুলেটর বা জটিল লাইব্রেরি ছাড়াই সরাসরি InnerTube প্রোটোকল ব্যবহার করা হয়।
- **সম্পূর্ণ OpenTune মডেল সামঞ্জস্য:** প্রতিটি অবজেক্টের ফিল্ড নেমিং এবং ডেটা স্ট্রাকচার ওপেন সোর্স OpenTune আর্কিটেকচারের সাথে ১০০% সামঞ্জস্যপূর্ণ।

---

## 🛡️ কীভাবে Bot-Proof ও Login-Free সার্ভিস দেওয়া হয়

YouTube Music সাধারণত স্ক্র্যাপার বা সাধারণ রিকোয়েস্টগুলোকে বিভিন্ন উপায়ে ব্লক করে (যেমন: HTTP 429, Sign-in bot verification, SABR cipher signature, PoToken)। এই সার্ভিসটি নিচের আধুনিক মেকানিজম ব্যবহার করে এগুলো সম্পূর্ণ বাইপাস করে:

1. **Dual InnerTube Client Architecture:**
   - **`WEB_REMIX` Client Context:** মেটাডেটা (Search, Album, Artist, Playlist, Next, Explore) সম্পূর্ণ কুকি ছাড়া অফিসিয়াল YouTube Music ওয়েব ক্লায়েন্ট (`clientName: 67`, `clientVersion: 1.20260114.01.00`) হেডারের মাধ্যমে ডিরেক্ট ফেচ করা হয়। এতে কোনো বট ডিটেকশন ট্রিগার হয় না।
   - **`VISIONOS` (Apple Vision) Client Context:** অডিও স্ট্রিম URL রেজলভ করার সময় এটি Apple Vision OS ক্লায়েন্ট হিসেবে কাজ করে। এই ক্লায়েন্টটি YouTube-এর সবচেয়ে নতুন এবং ট্রাস্টেড ক্লায়েন্ট হওয়ায় এতে কোনো PoToken বা Google অ্যাকাউন্ট লগইন রিকোয়ারমেন্ট ছাড়াই 128kbps/160kbps অডিও স্ট্রিমিং লিঙ্ক রেজলভ করা যায়।

2. **Decipher & Player Signature Pipeline:**
   - যখন কোনো মিউজিক ভিডিওতে সাইফার সিগনেচার থাকে, তখন সার্ভিসের মেমোরিতে ক্যাশ করা অফলাইন প্লেয়ার সিগনেচার অ্যালগরিদম দিয়ে রিয়েল-টাইমে URL ডিকোড করা হয়।

3. **Multi-Source Fallback System:**
   - কোনো সোর্স সাময়িকভাবে রেসপন্স করতে দেরি করলে স্বয়ংক্রিয়ভাবে সেকেন্ডারি সোর্সে চলে যায় (যেমন: LRCLib Synced -> YouTube Music Official Lyrics -> LRCLib Search)।

4. **User Auth & Data Isolation:**
   - প্লেয়ার সার্ভিসে কোনো ইউজার প্রোফাইল বা লাইব্রেরি ডেটা থাকে না। সব ইউজার অ্যাকশন (প্লেলিস্ট তৈরি, ফেভারিট, হিস্ট্রি) ক্লায়েন্ট সরাসরি **Supabase Database**-এ সেভ করে। ফলে স্ট্রিমিং সার্ভিস ১০০% স্টেটলেস ও ব্যান-মুক্ত থাকে।

---

## 🔒 সিকিউরিটি ও আর্কিটেকচারাল প্রোটেকশন প্ল্যান

```
[ User Request ]
       │
       ▼
┌────────────────────────────────────────────────────────┐
│ 1. Per-IP Sliding Window Rate Limiter (120 req/min)   │ ──(Exceeded)──► HTTP 429 + Retry-After
└────────────────────────────────────────────────────────┘
       │ (Allowed)
       ▼
┌────────────────────────────────────────────────────────┐
│ 2. In-Memory Request Coalescing (IN_FLIGHT Map)       │ ──(Duplicate)──► Awaits existing promise
└────────────────────────────────────────────────────────┘
       │ (New request)
       ▼
┌────────────────────────────────────────────────────────┐
│ 3. In-Memory Resolution Cache (2-Hour TTL)            │ ──(Hit)──────► Instant Cache Response
└────────────────────────────────────────────────────────┘
       │ (Miss)
       ▼
┌────────────────────────────────────────────────────────┐
│ 4. YouTube InnerTube & Upstream Fetch                 │
└────────────────────────────────────────────────────────┘
       │
       ▼
┌────────────────────────────────────────────────────────┐
│ 5. HTTP 206 Range Proxy + Strict Header Sanitization  │ ──► Client Playback
└────────────────────────────────────────────────────────┘
```

1. **Per-IP Rate Limiting (Sliding Window):**
   - প্রতি ক্লায়েন্ট আইপির জন্য সর্বোচ্চ **১২০ রিকোয়েস্ট/মিনিট** বরাদ্দ।
   - অতিরিক্ত রিকোয়েস্ট আসলে `HTTP 429 Too Many Requests` এর সাথে `Retry-After` হেডার পাঠানো হয়। এটি ডস/ডিডিওএস অ্যাটাক ও বট স্প্যাম প্রতিরোধ করে।

2. **In-Flight Request Deduplication (Promise Coalescing):**
   - যদি ১০০ জন ব্যবহারকারী একই সেকেন্ডে একই গান (`videoId`) প্লে করতে চান, তবে সার্ভার আপস্ট্রিমে মাত্র **১টি** রিকোয়েস্ট পাঠায় এবং প্রাপ্ত ফলাফল সবার কাছে বিতরণ করে। এতে আপস্ট্রিম ব্লক হওয়ার ঝুঁকি শূন্যে নেমে আসে।

3. **In-Memory 2-Hour Stream Cache:**
   - একবার কোনো গানের অডিও URL রেজলভ হলে তা ২ ঘণ্টার জন্য মেমরিতে ক্যাশ থাকে। ফলে ক্যাশড গানে রেসপন্স টাইম হয় **১–৩ মিলিসেকেন্ড**।

4. **CORS Safe & Range Header Proxying (`/api/stream/:id`):**
   - ব্রাউজার এবং iOS সাফারি অডিও সিকিংয়ের জন্য HTTP Range রিকোয়েস্ট পাঠায়। সার্ভারের প্রক্সি হ্যান্ডলার আপস্ট্রিম থেকে `206 Partial Content` ঠিকমতো ফরোয়ার্ড করে, যার ফলে অডিও সিকিংয়ে কোনো বাফারিং ল্যাগ থাকে না।

---

## 🚀 সমস্ত API Endpoints ও ব্যবহারের নিয়ম

ব্যাস URL: `https://teloplay-stream-service.teloplay-verify.workers.dev`  
(লোকাল টেস্টের জন্য: `http://localhost:4000`)

---

### 1. `GET /api/ping`
সার্ভার হেলথচেক ও রেসপন্স টাইম পরিমাপ।

```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/ping"
```
**রেসপন্স:**
```json
{
  "ok": true,
  "pong": true,
  "time": "2026-10-09T20:00:00.000Z"
}
```

---

### 2. `GET /api/resolve` & `GET /api/stream/:videoId`
গানের ডিরেক্ট অডিও লিঙ্ক, ভলিউম নরমালাইজেশন (`loudnessDb`), ফরম্যাট ও বিটরেট পাওয়ার জন্য।

#### `/api/resolve?id=<videoId>`
```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/resolve?id=i1o1p_DD6TU"
```
**রেসপন্স:**
```json
{
  "ok": true,
  "provider": "innertube_visionos",
  "videoId": "i1o1p_DD6TU",
  "url": "https://rr1---sn-qxa7snee.googlevideo.com/videoplayback?...",
  "directUrl": "https://rr1---sn-qxa7snee.googlevideo.com/videoplayback?...",
  "mimeType": "audio/mp4",
  "format": "m4a",
  "itag": 140,
  "bitrate": 131218,
  "duration": 362,
  "loudnessDb": -12.65,
  "title": "Gehra Hua (From \"Dhurandhar\")",
  "author": "Shashwat Sachdev"
}
```

#### `/api/stream/:videoId`
ব্রাউজার ও মোবাইল প্লেয়ারের জন্য ডিরেক্ট অডিও স্ট্রিমিং ও সিকিং এন্ডপয়েন্ট (`HTTP 206 Partial Content` সাপোর্ট সহ)।
```html
<audio src="https://teloplay-stream-service.teloplay-verify.workers.dev/api/stream/i1o1p_DD6TU" controls></audio>
```

---

### 3. `GET /api/search` & `GET /api/search-filter`

#### ফিল্টার ছাড়া সাধারণ সার্চ:
```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/search?q=Arijit%20Singh&limit=10"
```

#### ক্যাটাগরি অনুযায়ী ফিল্টার সার্চ (`/api/search-filter`):
সাপোর্টেড ফিল্টার: `song`, `video`, `album`, `artist`, `community-playlist`, `featured-playlist`

```bash
# ১. শুধু গান সার্চ
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/search-filter?query=love&filter=song&limit=5"

# ২. শুধু আর্টিস্ট সার্চ (সঠিক সাবস্ক্রাইবার কাউন্ট সহ)
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/search-filter?query=arijit&filter=artist&limit=2"
```

**আর্টিস্ট সার্চ রেসপন্স:**
```json
{
  "ok": true,
  "filter": "artist",
  "results": [
    {
      "type": "artist",
      "id": "UCDxKh1gFWeYsqePvgVzmPoQ",
      "browseId": "UCDxKh1gFWeYsqePvgVzmPoQ",
      "name": "Arijit Singh",
      "author": "Arijit Singh",
      "subscribers": "648M monthly audience",
      "thumbnail": "https://lh3.googleusercontent.com/W_yOqnKSDYyeVOY_AsXhuAtb6rW3vCL3GtJ9DA1GxWOrJfyeSOqzvTv_TkFHijdkVPXWutASBlRFPg=w544-h544-l90-rj"
    }
  ],
  "continuation": null
}
```

---

### 4. `GET /api/suggest`
সার্চ সাজেশন কিউরি এবং রিচ রেকমেন্ডেড আইটেম (আর্টিস্ট, অ্যালবাম, গান)।

```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/suggest?q=arijit"
```
**রেসপন্স:**
```json
{
  "ok": true,
  "queries": [
    "arijit singh",
    "arijit singh songs",
    "arijit singh bangla song"
  ],
  "recommendedItems": [
    {
      "type": "artist",
      "id": "UCDxKh1gFWeYsqePvgVzmPoQ",
      "name": "Arijit Singh",
      "subscribers": "648M monthly audience",
      "thumbnail": "https://lh3.googleusercontent.com/..."
    },
    {
      "type": "song",
      "id": "uT_HXrrmHX8",
      "title": "Sitaare (From \"Ikkis\")",
      "author": "Arijit Singh",
      "duration": 243,
      "thumbnail": "https://yt3.googleusercontent.com/..."
    }
  ]
}
```

---

### 5. `GET /api/song`
একটি নির্দিষ্ট গানের সম্পূর্ণ ডিটেইলস, আর্টিস্ট বায়োগ্রাফি এবং রিলেটেড গানের লিস্ট।

```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/song?id=i1o1p_DD6TU"
```
**রেসপন্স:**
```json
{
  "ok": true,
  "videoId": "i1o1p_DD6TU",
  "title": "Gehra Hua (From \"Dhurandhar\")",
  "author": "Shashwat Sachdev, Arijit Singh, Armaan Khan & Irshad Kamil",
  "artistId": "UCtIiZrzDsXk_rWeynT1ho4g",
  "artistBio": "Shashwat Sachdev (Sha) is a National Award, Filmfare RD Burman and IIFA Award winning composer...",
  "duration": 363,
  "relatedSongs": [
    {
      "type": "song",
      "id": "ge4M2dVBgTw",
      "videoId": "ge4M2dVBgTw",
      "title": "Saiyaara (Movie: Saiyaara)",
      "author": "Faheem Abdullah",
      "duration": 371,
      "thumbnail": "https://yt3.googleusercontent.com/..."
    }
  ],
  "similarArtists": [],
  "playlists": []
}
```

---

### 6. `GET /api/artist`
আর্টিস্টের প্রোফাইল, বায়োগ্রাফি, টপ গান (ডিউরেশন সহ), অ্যালবাম, সিঙ্গেলস, ভিডিও এবং রিলেটেড আর্টিস্ট।

```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/artist?id=UCDxKh1gFWeYsqePvgVzmPoQ"
```
**রেসপন্স:**
```json
{
  "ok": true,
  "artist": {
    "id": "UCDxKh1gFWeYsqePvgVzmPoQ",
    "name": "Arijit Singh",
    "subscribers": "6.5M",
    "description": "Arijit Singh is an Indian singer, composer, and music producer...",
    "thumbnail": "https://lh3.googleusercontent.com/..."
  },
  "sections": {
    "topSongs": [
      {
        "type": "song",
        "id": "i1o1p_DD6TU",
        "videoId": "i1o1p_DD6TU",
        "title": "Gehra Hua (From \"Dhurandhar\")",
        "author": "Shashwat Sachdev",
        "duration": 363
      }
    ],
    "albums": [],
    "singles": [],
    "videos": [
      {
        "type": "video",
        "id": "wuzTkiYJoNw",
        "title": "Dance Ka Bhoot",
        "views": "181K views"
      }
    ],
    "relatedArtists": [
      {
        "type": "artist",
        "id": "UCRQgqV5VW2GKp8u5-hlqJvw",
        "name": "Arko",
        "subscribers": "301M monthly audience"
      }
    ]
  }
}
```

---

### 7. `GET /api/album`
অ্যালবামের তথ্য এবং সম্পূর্ণ ট্র্যাকলিস্ট (প্রতিটি ট্র্যাকের সঠিক ডিউরেশন সহ)।

```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/album?id=MPREb_beMs50hcV8R"
```
**রেসপন্স:**
```json
{
  "ok": true,
  "albumId": "MPREb_beMs50hcV8R",
  "albumName": "Love Anthems",
  "artistName": "Sachet Tandon",
  "year": 2024,
  "trackCount": 10,
  "duration": 2340,
  "tracks": [
    {
      "type": "song",
      "id": "abc12345",
      "videoId": "abc12345",
      "trackNumber": 1,
      "title": "Song Title",
      "duration": 215
    }
  ]
}
```

---

### 8. `GET /api/playlist` & `GET /api/playlist-continuation`
প্লেলিস্ট মেটাডেটা, ট্র্যাকলিস্ট (প্রতিটি ট্র্যাকে `setVideoId` সহ) এবং পেজিনেশন সাপোর্ট।

```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/playlist?id=VLPLXVyeVgQgGOymi0MOddagfMuCOfMtjXYE"
```
**রেসপন্স:**
```json
{
  "ok": true,
  "playlistId": "PLXVyeVgQgGOymi0MOddagfMuCOfMtjXYE",
  "playlistName": "Energetic Bollywood Songs",
  "author": "YouTube Music",
  "trackCount": 27,
  "tracks": [
    {
      "type": "song",
      "id": "H9pv_BZ2PGA",
      "videoId": "H9pv_BZ2PGA",
      "setVideoId": "289F4A46DF0A30D2",
      "title": "Lat Lag Gayee",
      "duration": 281,
      "trackNumber": 1
    }
  ],
  "continuation": "4wINGAEyBk1VU0lDJW..."
}
```

---

### 9. `GET /api/next`
অটোপ্লে (Autoplay) এবং ইনফিনিট রেডিও কিউ (Radio Queue) জেনারেটর।

```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/next?videoId=i1o1p_DD6TU"
```
**রেসপন্স:**
```json
{
  "ok": true,
  "videoId": "i1o1p_DD6TU",
  "title": "Up next",
  "currentIndex": 0,
  "continuation": "CDISOBILWUN3UDdYNDJ3ZnciEV...",
  "songs": [
    {
      "type": "song",
      "id": "i1o1p_DD6TU",
      "videoId": "i1o1p_DD6TU",
      "title": "Gehra Hua (From \"Dhurandhar\")",
      "duration": 363,
      "setVideoId": "56B44F6D10557CC6"
    }
  ]
}
```

---

### 10. `GET /api/lyrics`
টাইমস্ট্যাম্প সিঙ্কড এলআরসি (Synced LRC) এবং প্লেইন লিরিক্স এন্ডপয়েন্ট।

```bash
curl -s "https://teloplay-stream-service.teloplay-verify.workers.dev/api/lyrics?id=4NRXx6U8ABQ&title=Blinding%20Lights&artist=The%20Weeknd"
```
**রেসপন্স:**
```json
{
  "ok": true,
  "videoId": "4NRXx6U8ABQ",
  "title": "Blinding Lights",
  "artist": "The Weeknd",
  "hasSynced": true,
  "source": "lrclib",
  "syncedLyrics": "[00:13.13] Yeah\n[00:16.56] ♪\n[00:27.16] I've been tryna call\n[00:30.90] I've been on my own for long enough...",
  "plainLyrics": "Yeah\n♪\nI've been tryna call..."
}
```

---

### 11. Explore, Home, Charts, Moods & New Releases

| Endpoint | কাজের বিবরণ |
|---|---|
| `GET /api/explore` | নতুন অ্যালবাম ও মুডস/জনরা ক্যাটাগরির একীভূত ফিড। |
| `GET /api/home` | ফিল্টার চিপস (`chips[]`) ও সেকশন ক্যারোজেল (`sections[]`) সহ হোম ফিড। |
| `GET /api/charts?country=US` | দেশের চার্ট লিস্ট (`chartPosition` ও `chartChange` সহ)। |
| `GET /api/moods-and-genres` | মুড ও জনরার গ্রিড লিস্ট (`stripeColor`, `params`, `browseId` সহ)। |
| `GET /api/new-releases?limit=20` | লেটেস্ট রিলিজ হওয়া অ্যালবামের লিস্ট। |

---

## 📦 Standard Data Model

সার্ভার থেকে রিটার্ন হওয়া প্রতিটি গানের ডেটা মডেল OpenTune-এর মডেলের অনুরূপ:

```typescript
interface SongItem {
  type: 'song';
  id: string;               // YouTube Video ID
  videoId: string;          // YouTube Video ID
  title: string;            // Full Title
  cleanTitle: string;       // Sanitized Title (removes 'Official Video', etc.)
  author: string;           // Primary Artist Name
  artistId: string | null;  // Channel Browse ID (UC...)
  allArtistNames: string;   // Comma separated artist names
  artists: Array<{
    name: string;
    id: string | null;
  }>;
  thumbnail: string;        // 544x544 High-Resolution Cover
  highResThumbnail: string; // 544x544 High-Resolution Cover
  duration: number;         // Total duration in Seconds
  albumId: string | null;   // Album Browse ID (MPREb_...)
  albumName: string | null; // Album Title
  explicit: boolean;        // Parental Advisory Badge
  setVideoId?: string;      // Unique Playlist Track Pointer
  chartPosition?: number;   // Chart ranking if from /api/charts
  chartChange?: 'UP' | 'DOWN' | 'NEUTRAL';
}
```

---

## 🛠️ লোকাল ডেভেলপমেন্ট ও ডিপ্লয়মেন্ট

### ১. লোকাল সার্ভার রান করা
```bash
cd H:/TeloPlay/teloplay-stream-service
npm install
npm start
```
সার্ভারটি `http://localhost:4000` এ রান হবে।

### ২. Cloudflare Workers-এ ডিপ্লয় করা
```bash
npm run deploy
# অথবা: npx wrangler deploy
```

---

**Developed with ❤️ for TeloPlay**
