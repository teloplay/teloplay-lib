import 'dart:async';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/services.dart';
import '../audio/audio_handler_registry.dart';
import '../logging/app_logger.dart';
import 'playback_engine.dart';

/// Android-এর জন্য PlaybackEngine implementation।
/// OpenTune-এর `:innertube` module থেকে বানানো native Kotlin bridge
/// ব্যবহার করে স্ট্রিম resolve করে — real device-এ (Samsung S7 Edge,
/// Android 13) verified।
///
/// এই ফাইলের logic হুবহু MusicPlayerService (আগের singleton service)
/// থেকে migrate করা — channel name, method name, argument shape সব
/// অক্ষত রাখা হয়েছে।
///
/// Channel: `com.piyas.teloplay/youtube_stream`
/// File: android/app/src/main/kotlin/com/piyas/teloplay/MainActivity.kt
class AndroidPlaybackEngine implements PlaybackEngine {
  static const MethodChannel _channel =
      MethodChannel('com.piyas.teloplay/youtube_stream');

  @override
  String get engineLabel => 'innertube/android';

  // ═══════════════════════════════════════════════════════════════
  // ⚠️ Audio Focus Ducking (Phase 1)
  // ═══════════════════════════════════════════════════════════════
  //
  // `audio_session` প্যাকেজ ব্যবহার করা হয়েছে — এটা Dart layer থেকেই
  // Android AudioManager-এর audio focus request/listener wrap করে
  // দেয়, তাই আলাদা native Kotlin listener/EventChannel লেখার দরকার
  // হয়নি (MainActivity.kt অপরিবর্তিত থাকছে)। এটা `just_audio`/
  // `audio_service` ecosystem-এর সাথে battle-tested এবং media_kit-এর
  // পাশে independent ভাবে চলে (media_kit নিজে audio focus manage করে
  // না)।
  //
  // এই engine নিজে duck/pause *করে না* — engine শুধু OS থেকে আসা
  // focus-change signal শোনে এবং repository-কে stream-এর মাধ্যমে
  // জানায় (repository-ই player.setVolume()/pause() এর মালিক, engine-এর
  // player object access নেই — এটা architectural boundary বজায়
  // রাখে)।
  StreamSubscription<AudioInterruptionEvent>? _interruptionSub;
  StreamSubscription<void>? _becomingNoisySub;

  final _audioFocusController =
      StreamController<AudioFocusSignal>.broadcast();

  @override
  Stream<AudioFocusSignal> get audioFocusStream =>
      _audioFocusController.stream;

  @override
  Future<void> initialize() async {
    // visitorData native side-এ lazy-init হয় (ensureVisitorData()),
    // তাই এখানে আলাদা warm-up call দরকার নেই।
    AppLogger.playback(
      'AndroidPlaybackEngine ready (visitorData lazy-inits on first call)',
    );

    // ⚠️ Bug fix — AudioService.init() সম্পূর্ণ হওয়ার আগে audio_session
    // configure করলে race condition হতো (দেখো audio_handler_registry.dart-
    // এর audioServiceReady নোট)। এখানে অপেক্ষা করা হচ্ছে, যাতে আমাদের
    // configure()/setActive() সবসময় audio_service লোড হওয়ার *পরে়*
    // চলে — এটাই audio_service-এর নিজস্ব সুপারিশকৃত order।
    // Timeout দিয়ে রাখা হচ্ছে (৫ সেকেন্ড) যাতে কোনো কারণে
    // AudioService.init() কখনো শেষ না হলেও (বা এই engine কোনো কারণে
    // Android entry point ছাড়া অন্য কোনো flow থেকে ব্যবহার হলে,
    // যেখানে audioServiceReady কখনো complete হবে না) পুরো app
    // অনির্দিষ্টকালের জন্য আটকে না থাকে।
    try {
      await audioServiceReady.future.timeout(const Duration(seconds: 5));
    } catch (_) {
      AppLogger.playback(
        '[$engineLabel] audioServiceReady wait timed out — proceeding '
        'with audio session setup anyway',
      );
    }

    await _setupAudioSession();
  }

  Future<void> _setupAudioSession() async {
    try {
      final session = await AudioSession.instance;

      // ⚠️ Bug fix — এখন এই কল আবার ফিরিয়ে আনা হয়েছে, কিন্তু এবার
      // initialize()-এ audioServiceReady-এর জন্য অপেক্ষা করার পরেই
      // এই মেথড চলে, তাই আমাদের configure()/setActive() সবসময়
      // audio_service-এর নিজস্ব session setup-এর *পরে়* চলবে —
      // audio_service-এর ডকুমেন্টেশনের সুপারিশ অনুযায়ী ("apply your
      // own preferred configuration using audio_session after all
      // other audio plugins have loaded")। আগে এই কল সম্পূর্ণ সরিয়ে
      // দেওয়া হয়েছিল, কিন্তু সেটা ভুল ফিক্স ছিল — configure()/
      // setActive() ছাড়া session কখনো ঠিকভাবে activate-ই হতো না,
      // regression হয়েছিল। আসল সমস্যা ছিল শুধু timing/order, ownership
      // না।
      await session.configure(const AudioSessionConfiguration.music());
      await session.setActive(true);

      _interruptionSub = session.interruptionEventStream.listen((event) {
        if (event.begin) {
          switch (event.type) {
            case AudioInterruptionType.duck:
              AppLogger.playback('[$engineLabel] audio focus: duck begin');
              _audioFocusController.add(AudioFocusSignal.duck);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              AppLogger.playback(
                '[$engineLabel] audio focus: call/interruption begin (pause)',
              );
              _audioFocusController.add(AudioFocusSignal.callInterruption);
              break;
          }
        } else {
          switch (event.type) {
            case AudioInterruptionType.duck:
              AppLogger.playback('[$engineLabel] audio focus: duck end');
              _audioFocusController.add(AudioFocusSignal.gained);
              break;
            case AudioInterruptionType.pause:
            case AudioInterruptionType.unknown:
              AppLogger.playback(
                '[$engineLabel] audio focus: call/interruption end',
              );
              _audioFocusController.add(AudioFocusSignal.callEnded);
              break;
          }
        }
      });

      _becomingNoisySub = session.becomingNoisyEventStream.listen((_) {
        AppLogger.playback(
          '[$engineLabel] audio becoming noisy (headphone/Bluetooth '
          'disconnected) — pause',
        );
        _audioFocusController.add(AudioFocusSignal.deviceDisconnected);
      });

      session.devicesChangedEventStream.listen((event) {
        if (event.devicesAdded.isEmpty) return;
        AppLogger.playback(
          '[$engineLabel] audio device added (${event.devicesAdded.length}) '
          '— possible reconnect',
        );
        _audioFocusController.add(AudioFocusSignal.deviceReconnected);
      });

      AppLogger.playback(
        '[$engineLabel] audio session configured & active (after '
        'audio_service ready)',
      );
    } catch (e) {
      AppLogger.error('[$engineLabel] audio session setup failed', e);
    }
  }

  @override
  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    AppLogger.playback('[$engineLabel] search: $query (limit=$limit)');

    try {
      final List<dynamic>? results = await _channel.invokeListMethod(
        'searchTracks',
        {'query': query, 'limit': limit},
      );

      if (results == null || results.isEmpty) {
        throw PlaybackEngineException('কোনো ফলাফল পাওয়া যায়নি query="$query"');
      }

      final parsed = results
          .cast<Map<dynamic, dynamic>>()
          .map((item) {
            final videoId = item['videoId'] as String?;
            return SearchResult(
              videoId: videoId ?? '',
              title: (item['title'] as String?) ?? 'Unknown',
              author: (item['author'] as String?) ?? 'Unknown',
              thumbnail: (item['thumbnail'] as String?) ??
                  'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
              duration: item['duration'] != null
                  ? Duration(seconds: item['duration'] as int)
                  : null,
            );
          })
          .where((r) => r.videoId.isNotEmpty)
          .take(limit)
          .toList();

      if (parsed.isEmpty) {
        throw PlaybackEngineException('কোনো ফলাফল পাওয়া যায়নি query="$query"');
      }

      return parsed;
    } on PlatformException catch (e) {
      throw PlaybackEngineException('Innertube search ব্যর্থ', cause: e);
    }
  }

  @override
  Future<ResolvedStream> resolveStream(String videoId) async {
    AppLogger.playback('[$engineLabel] resolveStream: $videoId');

    try {
      final streamUrl = await _channel.invokeMethod<String>(
        'getStreamUrl',
        {'videoId': videoId},
      );

      if (streamUrl == null || streamUrl.isEmpty) {
        throw PlaybackEngineException('স্ট্রিম URL খালি এসেছে videoId=$videoId');
      }

      AppLogger.playback('[$engineLabel] resolved OK: $videoId');

      return ResolvedStream(
        streamUrl: streamUrl,
        // Native side expiry ফেরত দেয় না — conservative estimate।
        expiresIn: const Duration(hours: 6),
        sourceLabel: engineLabel,
      );
    } on PlatformException catch (e) {
      throw PlaybackEngineException('Innertube ব্যর্থ', cause: e);
    }
  }

  // ⚠️ Phase 0.9 hooks — repository → engine দিকের placeholder call।
  // Audio focus এখন engine-driven (উপরের audioFocusStream দেখো), তাই
  // এই দুটো method আর সরাসরি ব্যবহার হচ্ছে না, কিন্তু interface
  // backward-compatibility-এর জন্য no-op override রাখা হলো।
  @override
  Future<void> onAudioFocusLost() async {}

  @override
  Future<void> onAudioFocusGained() async {}

  @override
  Stream<double>? get bufferHealthStream => null; // TODO(Phase 1)

  // ⚠️ Bluetooth Optimization (Phase 1) — codec/device-profiling Phase
  // 7+-এ পাঠানো হয়েছে (roadmap সিদ্ধান্ত), তাই এখানে placeholder null।
  @override
  Stream<String?>? get connectedAudioDeviceStream => null; // TODO(Phase 7+)

  // ⚠️ Live Search Suggestions — MethodChannel-এর নতুন
  // getSearchSuggestions handler কল করে। ব্যর্থ হলে (PlatformException)
  // exception propagate না করে খালি list — suggestion non-critical UX,
  // caller-কে try-catch করতে বাধ্য করা ঠিক না (interface contract
  // অনুযায়ী)।
  @override
  Future<List<String>> searchSuggestions(String query) async {
    try {
      final List<dynamic>? result = await _channel.invokeListMethod(
        'getSearchSuggestions',
        {'query': query},
      );
      return result?.cast<String>() ?? [];
    } on PlatformException catch (e) {
      AppLogger.playback('[$engineLabel] searchSuggestions failed: ${e.message}');
      return [];
    }
  }

  // ═══════════════════════════════════════════════════════════════
  // ⚠️ RICH DATA COMMANDS — MainActivity.kt-এর generic "command"
  // MethodChannel case ব্যবহার করে (handleCommand() dispatch)।
  //
  // প্রতিটা method native response shape অনুযায়ী ok/error চেক করে,
  // ব্যর্থ হলে PlaybackEngineException throw করে — search()/
  // resolveStream()-এর সাথে consistent error-handling pattern।
  // ═══════════════════════════════════════════════════════════════

  /// [cmd]-এ দেওয়া native command-টা execute করে পুরো response map
  /// (String-keyed) ফেরত দেয় — Windows engine (innertube-windows) এর
  /// same behavior: `ok` != true হলে বা response খালি হলে
  /// [PlaybackEngineException] throw হয়, সফল হলে সম্পূর্ণ map ফেরত আসে।
  Future<Map<String, dynamic>> _invokeCommand(
    String cmd,
    Map<String, dynamic> params,
  ) async {
    try {
      final response = await _channel.invokeMapMethod<dynamic, dynamic>(
        'command',
        {'cmd': cmd, ...params},
      );
      if (response == null || response['ok'] != true) {
        throw PlaybackEngineException(
          '$cmd failed: ${response?['error'] ?? 'empty response'}',
        );
      }
      return response.cast<String, dynamic>();
    } on PlatformException catch (e) {
      throw PlaybackEngineException('Innertube $cmd ব্যর্থ', cause: e);
    }
  }

  /// Video details (title, author, thumbnail, duration, explicit)
  Future<Map<String, dynamic>> getVideoDetails(String videoId) async {
    AppLogger.playback('[$engineLabel] getVideoDetails: $videoId');
    return _invokeCommand('details', {'videoId': videoId});
  }

  /// Album tracks (albumName, artistName, year, trackCount, tracks[])
  Future<Map<String, dynamic>> getAlbumTracks(String albumId) async {
    AppLogger.playback('[$engineLabel] getAlbumTracks: $albumId');
    return _invokeCommand('album', {'albumId': albumId});
  }

  /// Artist songs (artistName, thumbnail, songCount, songs[])
  /// limit <= 0 means no cap
  Future<Map<String, dynamic>> getArtistSongs(String artistId, {int limit = 0}) async {
    AppLogger.playback('[$engineLabel] getArtistSongs: $artistId (limit=$limit)');
    return _invokeCommand('artist', {'artistId': artistId, 'limit': limit});
  }

  /// Related songs / Watch Next (videoId, relatedCount, songs[])
  /// limit <= 0 means no cap
  Future<Map<String, dynamic>> getRelatedSongs(String videoId, {int limit = 0}) async {
    AppLogger.playback('[$engineLabel] getRelatedSongs: $videoId (limit=$limit)');
    return _invokeCommand('related', {'videoId': videoId, 'limit': limit});
  }

  /// Playlist tracks (playlistName, author, thumbnail, trackCount, tracks[])
  /// limit <= 0 means no cap
  Future<Map<String, dynamic>> getPlaylistTracks(String playlistId, {int limit = 0}) async {
    AppLogger.playback('[$engineLabel] getPlaylistTracks: $playlistId (limit=$limit)');
    return _invokeCommand('playlist', {'playlistId': playlistId, 'limit': limit});
  }

  /// Lyrics (lyrics text, source, isSynced)
  Future<Map<String, dynamic>> getLyrics(String videoId) async {
    AppLogger.playback('[$engineLabel] getLyrics: $videoId');
    return _invokeCommand('lyrics', {'videoId': videoId});
  }

  /// Media info (title, author, authorId, authorThumbnail, description,
  /// uploadDate, subscribers, viewCount, like, dislike)
  Future<Map<String, dynamic>> getMediaInfo(String videoId) async {
    AppLogger.playback('[$engineLabel] getMediaInfo: $videoId');
    return _invokeCommand('media-info', {'videoId': videoId});
  }

  /// Charts (sections[] — title, chartType, songs[])
  Future<Map<String, dynamic>> getCharts() async {
    AppLogger.playback('[$engineLabel] getCharts');
    return _invokeCommand('charts', {});
  }

  /// Home feed (sections[] — title, songs[])
  Future<Map<String, dynamic>> getHome() async {
    AppLogger.playback('[$engineLabel] getHome');
    return _invokeCommand('home', {});
  }

  @override
  Future<void> dispose() async {
    await _interruptionSub?.cancel();
    await _becomingNoisySub?.cancel();
    await _audioFocusController.close();

    try {
      final session = await AudioSession.instance;
      await session.setActive(false);
    } catch (e) {
      AppLogger.error('[$engineLabel] audio session deactivate failed', e);
    }

    // Native side নিজের visitorDataReady state MainActivity lifecycle
    // অনুযায়ী রাখে — Dart side থেকে cleanup করার কিছু নেই।
  }
}