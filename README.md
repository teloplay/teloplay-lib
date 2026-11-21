# TeloPlay

Cross-platform (Android, Windows, Web) music streaming app built with Flutter.

"Spotify-র প্রিমিয়াম ফিল ও পারফরম্যান্স + OpenTune-র লোকাল কাস্টমাইজেশন + TeloPlay-র হাইব্রিড AI ও ৪-লেয়ার মেটাডাটা ইঞ্জিন।"

## Features

- Streaming playback across Android, Windows, and Web (PWA)
- 4-layer metadata & search orchestration (Deezer, Last.fm, MusicBrainz)
- Synced lyrics (LRCLib)
- Offline-first local cache with Drift SQLite
- Supabase auth, multi-device sync & presence
- Midnight Aurora true-dark theme with dynamic theming

## Tech Stack

- **Framework**: Flutter (Dart 3.5+)
- **State management**: Flutter Riverpod
- **Local DB**: Drift SQLite (web: `sqlite3.wasm` + drift worker)
- **Backend**: Supabase (Auth, sync, presence)
- **Audio**:
  - Android: `media_kit` + `audio_service`
  - Windows: `media_kit` + `smtc_windows` + `window_manager`
  - Web: WebAudio + Web MediaSession API
- **Stream extraction**: YouTube/Innertube engine (platform-native)
- **AI**: multi-LLM gateway router (OpenRouter / NVIDIA NIM / Kilo AI)

## Architecture

Repository pattern + clean layering:

```
lib/
  core/       # theme, playback engines, platform abstraction, audio
  data/       # drift DB, repositories, sync
  providers/  # Riverpod state
  screens/    # feature screens
  ui/shell/   # responsive shell (sidebar / bottom nav)
  widgets/    # shared widgets
  web_app/    # web-specific screens & services
worker/       # Cloudflare Worker (stream resolver)
```

## Getting Started

```bash
flutter pub get
flutter run            # pick a device (android / windows / chrome)
flutter analyze        # static analysis
```

Environment config lives in `lib/core/config/env_config.dart` (Supabase URL + anon key).

## Docs

- `PROJECT_CONTEXT.md` — full system overview
- `FEATURE_STATUS.md` — phase tracker
- `ARCHITECTURE.md`, `DATABASE_SCHEMA.md`, `CODING_STANDARDS.md`
- `TeloPlay_Web_Behavior_Spec.md`, `TeloPlay_Windows_Behavior_Spec.md`, `TeloPlay_Android_Behavior_Spec.md`
