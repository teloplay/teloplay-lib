import 'dart:async';
import 'dart:convert';
import 'dart:io';

import '../logging/app_logger.dart';
import 'playback_engine.dart';

/// Windows-এর জন্য Innertube-ভিত্তিক PlaybackEngine — persistent daemon
/// mode ব্যবহার করে (v2, JVM cold-start overhead fix)। এটাই Windows-এর
/// permanent primary engine (v6 চূড়ান্ত সিদ্ধান্ত)।
///
/// [WindowsPlaybackEngine] (yt-dlp) emergency fallback হিসেবে অক্ষত আছে।
class InnertubeWindowsPlaybackEngine implements PlaybackEngine {
  @override
  String get engineLabel => 'innertube/windows';

  Process? _daemon;
  StreamSubscription<String>? _stdoutSub;
  StreamSubscription<String>? _stderrSub;

  final _pendingRequests = <String, Completer<Map<String, dynamic>>>{};
  int _requestCounter = 0;

  // ⚠️ Bug fix — concurrent stdin write race। দুইটা search() call
  // (যেমন suggestion preview আর full search) প্রায় একই সময়ে
  // _sendRequest() কল করলে দুটোই daemon.stdin-এ writeln()/flush()
  // করার চেষ্টা করত একসাথে — Dart-এর IOSink একই সময়ে দুইটা concurrent
  // write/flush handle করতে পারে না, ফলে দ্বিতীয় write
  // "Bad state: StreamSink is bound to a stream" exception ছুঁড়ত এবং
  // caller-এর কাছে silently empty result হিসেবে ধরা পড়ত (catchError-এ)।
  //
  // Fix: stdin-এ লেখার অংশটুকু একটা simple async queue দিয়ে serialize
  // করা হচ্ছে — প্রতিটা _sendRequest() নিজের write শুরু করার আগে আগের
  // pending write শেষ হওয়া পর্যন্ত অপেক্ষা করে। Request/response
  // matching (id-ভিত্তিক) এতে প্রভাবিত হয় না — শুধু stdin-এ লেখার
  // মুহূর্তটাই serialize হচ্ছে, একাধিক request এখনো concurrently
  // pending থাকতে পারে (daemon একসাথে একাধিক request process করতে
  // পারে, শুধু stdin write নিজে atomic হতে হবে)।
  Future<void> _stdinWriteQueue = Future.value();

  String? _cachedJavaPath;
  String? _cachedJarPath;

  Future<void>? _initFuture;

  @override
  Future<void> initialize() {
    return _initFuture ??= _doInitialize();
  }

  Future<void> _doInitialize() async {
    if (_daemon != null) return;

    final java = _findJava();
    final jar = _findJar();

    AppLogger.playback('[$engineLabel] spawning daemon: $java -jar $jar --daemon');

    _daemon = await Process.start(
      java,
      ['-jar', jar, '--daemon'],
      runInShell: false,
    );

    _daemon!.stdin.encoding = utf8;

    _stdoutSub = _daemon!.stdout
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen(_onDaemonLine, onError: _onDaemonError);

    _stderrSub = _daemon!.stderr
        .transform(const Utf8Decoder())
        .transform(const LineSplitter())
        .listen((line) => AppLogger.playback('[$engineLabel][stderr] $line'));

    unawaited(_daemon!.exitCode.then((code) {
      AppLogger.playback('[$engineLabel] daemon exited with code $code');
      _failAllPending('daemon process exited (code $code)');
      _daemon = null;
      _initFuture = null;
    }));

    await _sendRequest('ping', {}).timeout(
      const Duration(seconds: 30),
      onTimeout: () => throw PlaybackEngineException(
        'innertube-cli daemon প্রস্তুত হতে সময় বেশি লাগছে (30s timeout)',
      ),
    );

    AppLogger.playback('[$engineLabel] daemon ready');
  }

  void _onDaemonLine(String line) {
    if (line.isBlank) return;

    Map<String, dynamic> parsed;
    try {
      parsed = jsonDecode(line) as Map<String, dynamic>;
    } catch (e) {
      AppLogger.playback('[$engineLabel] malformed daemon output ignored: $line');
      return;
    }

    final id = parsed['id'] as String?;
    if (id == null) return;

    final completer = _pendingRequests.remove(id);
    completer?.complete(parsed);
  }

  void _onDaemonError(Object error) {
    AppLogger.error('[$engineLabel] daemon stdout stream error', error);
    _failAllPending('daemon stdout stream error: $error');
  }

  void _failAllPending(String reason) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(PlaybackEngineException(reason));
      }
    }
    _pendingRequests.clear();
  }

  Future<Map<String, dynamic>> _sendRequest(
    String cmd,
    Map<String, dynamic> params,
  ) async {
    final daemon = _daemon;
    if (daemon == null) {
      throw PlaybackEngineException(
        '[$engineLabel] daemon চালু নেই — initialize() call হয়েছে কিনা যাচাই করুন',
      );
    }

    final id = (_requestCounter++).toString();
    final completer = Completer<Map<String, dynamic>>();
    _pendingRequests[id] = completer;

    final request = {'id': id, 'cmd': cmd, ...params};

    // ⚠️ Serialize stdin writes — দেখো উপরের _stdinWriteQueue নোট।
    final myWrite = _stdinWriteQueue.then((_) async {
      daemon.stdin.writeln(jsonEncode(request));
      await daemon.stdin.flush();
    });
    _stdinWriteQueue = myWrite.catchError((_) {
      // পরের queue entry যেন আগের write ব্যর্থ হলেও আটকে না যায়
    });
    await myWrite;

    return completer.future.timeout(
      const Duration(seconds: 20),
      onTimeout: () {
        _pendingRequests.remove(id);
        throw PlaybackEngineException(
          '[$engineLabel] "$cmd" command timeout (20s) — videoId/query: $params',
        );
      },
    );
  }

  @override
  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    await initialize();

    AppLogger.playback('[$engineLabel] search: $query (limit=$limit)');

    final response = await _sendRequest('search', {'query': query, 'limit': limit});

    if (response['ok'] != true) {
      throw PlaybackEngineException(
        'innertube-cli search ব্যর্থ: ${response['error']}',
      );
    }

    final rawResults = response['results'] as List<dynamic>? ?? [];
    final results = rawResults
        .cast<Map<String, dynamic>>()
        .map((item) {
          final videoId = item['videoId'] as String?;
          return SearchResult(
            videoId: videoId ?? '',
            title: (item['title'] as String?) ?? 'Unknown',
            author: (item['author'] as String?) ?? 'Unknown',
            thumbnail: (item['thumbnail'] as String?) ??
                'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
            artistId: item['artistId'] as String?,
            albumId: item['albumId'] as String?,
            albumName: item['albumName'] as String?,
            allArtistNames: (item['allArtistNames'] as List<dynamic>?)
                    ?.cast<String>() ??
                const [],
            allArtistIds: (item['allArtistIds'] as List<dynamic>?)
                    ?.map((e) => e as String?)
                    .toList() ??
                const [],
            explicit: item['explicit'] as bool? ?? false,
            chartPosition: item['chartPosition'] as int?,
            chartChange: item['chartChange'] as String?,
            setVideoId: item['setVideoId'] as String?,
          );
        })
        .where((r) => r.videoId.isNotEmpty)
        .take(limit)
        .toList();

   // ⚠️ Bug fix — আগে খালি results-কে PlaybackEngineException ধরা হতো,
    // যেটা caller-এর কাছে "কিছু পাওয়া যায়নি" আর "search ব্যর্থ হয়েছে"
    // দুটোকে আলাদা করতে দিত না। ছোট limit (যেমন suggestion preview-তে
    // limit=5) দিয়ে সার্চ করলে backend/daemon মাঝেমধ্যে সত্যিই ০টা
    // ফলাফল দেয় (কোনো crash/error ছাড়াই) — এটা একটা বৈধ অবস্থা, error
    // না। খালি list সরাসরি রিটার্ন করা হচ্ছে; caller নিজে সিদ্ধান্ত
    // নেবে খালি ফলাফল নিয়ে কী করবে।
    return results;
  }

  @override
  Future<ResolvedStream> resolveStream(String videoId) async {
    await initialize();

    AppLogger.playback('[$engineLabel] resolveStream: $videoId');

    final response = await _sendRequest('resolve', {'videoId': videoId});

    if (response['ok'] != true) {
      throw PlaybackEngineException(
        'innertube-cli resolve ব্যর্থ videoId=$videoId: ${response['error']}',
      );
    }

    final url = response['url'] as String?;
    if (url == null || !url.startsWith('http')) {
      throw PlaybackEngineException(
        'innertube-cli থেকে invalid/empty URL এসেছে videoId=$videoId',
      );
    }

    AppLogger.playback('[$engineLabel] resolved OK: $videoId');

    return ResolvedStream(
      streamUrl: url,
      expiresIn: const Duration(hours: 5),
      sourceLabel: engineLabel,
    );
  }

  // ⚠️ FIX (build error): এই দুটো method আগে ভুলভাবে সরিয়ে ফেলা
  // হয়েছিল এই ধারণায় যে interface default (no-op) যথেষ্ট — কিন্তু
  // `implements PlaybackEngine` ব্যবহারের কারণে (extends না), Dart-এ
  // প্রতিটা abstract member-এর explicit override বাধ্যতামূলক, default
  // body থাকা সত্ত্বেও। এই দুটো method এখন deprecated (ব্যবহৃত হচ্ছে
  // না, দেখুন playback_engine.dart-এর audioFocusStream নোট), কিন্তু
  // interface-এ থাকা মানে explicit override করতেই হবে।
  @override
  Future<void> onAudioFocusLost() async {
    // no-op — deprecated, দেখুন audioFocusStream (নিচে)
  }

  @override
  Future<void> onAudioFocusGained() async {
    // no-op — deprecated, দেখুন audioFocusStream (নিচে)
  }

  // ⚠️ Audio Focus Ducking (Phase 1) — Windows-এ এখনো implement করা
  // হয়নি। SMTC/Windows Core Audio-তে Android AudioManager-এর মতো
  // সরাসরি "audio focus" concept নেই (transient/duck/permanent loss
  // categorization) — Windows Core Audio session events
  // (IAudioSessionEvents) দিয়ে কাছাকাছি কিছু করা সম্ভব হলেও সেটা
  // windows_media_service.dart (SMTC wrapper)-এর সাথে সমন্বিত আলাদা
  // কাজ, এখানে scope-এর বাইরে।
  @override
  Stream<AudioFocusSignal>? get audioFocusStream => null;

  // ⚠️ Bluetooth Optimization (Phase 1) — Windows-এ Bluetooth/device-
  // change detection এখনো implement করা হয়নি (SMTC layer-এ এই ধরনের
  // device-connect/disconnect event সরাসরি expose করা নেই এই engine
  // থেকে, future scope হলে windows_media_service.dart-এর সাথে
  // সমন্বিত আলাদা কাজ হবে)। explicit no-op override —
  // `implements PlaybackEngine` ব্যবহারের কারণে বাধ্যতামূলক।
  @override
  Stream<String?>? get connectedAudioDeviceStream => null; // TODO(Phase 7+)

  @override
  Stream<double>? get bufferHealthStream => null; // TODO(Phase 1: Adaptive Buffering)

  @override
  Future<List<String>> searchSuggestions(String query) async {
    try {
      await initialize();
      final response = await _sendRequest('suggest', {'query': query});
      if (response['ok'] != true) return [];
      final raw = response['suggestions'] as List<dynamic>? ?? [];
      return raw.cast<String>();
    } catch (e) {
      AppLogger.playback('[$engineLabel] searchSuggestions failed: $e');
      return [];
    }
  }

  // ========== NEW COMMANDS (Extended Version) ==========

  /// Video details (title, author, thumbnail, duration, explicit)
  Future<Map<String, dynamic>> getVideoDetails(String videoId) async {
    await initialize();
    final response = await _sendRequest('details', {'videoId': videoId});
    if (response['ok'] != true) {
      throw PlaybackEngineException('details failed: ${response['error']}');
    }
    return response;
  }

  /// Album tracks (albumName, artistName, year, trackCount, tracks[])
  Future<Map<String, dynamic>> getAlbumTracks(String albumId) async {
    await initialize();
    final response = await _sendRequest('album', {'albumId': albumId});
    if (response['ok'] != true) {
      throw PlaybackEngineException('album failed: ${response['error']}');
    }
    return response;
  }

  /// Artist songs (artistName, thumbnail, songCount, songs[])
  /// limit <= 0 means no cap
  Future<Map<String, dynamic>> getArtistSongs(String artistId, {int limit = 0}) async {
    await initialize();
    final response = await _sendRequest('artist', {'artistId': artistId, 'limit': limit});
    if (response['ok'] != true) {
      throw PlaybackEngineException('artist failed: ${response['error']}');
    }
    return response;
  }

  /// Related songs / Watch Next (videoId, relatedCount, songs[])
  /// limit <= 0 means no cap
  Future<Map<String, dynamic>> getRelatedSongs(String videoId, {int limit = 0}) async {
    await initialize();
    final response = await _sendRequest('related', {'videoId': videoId, 'limit': limit});
    if (response['ok'] != true) {
      throw PlaybackEngineException('related failed: ${response['error']}');
    }
    return response;
  }

  /// Playlist tracks (playlistName, author, thumbnail, trackCount, tracks[])
  /// limit <= 0 means no cap
  Future<Map<String, dynamic>> getPlaylistTracks(String playlistId, {int limit = 0}) async {
    await initialize();
    final response = await _sendRequest('playlist', {'playlistId': playlistId, 'limit': limit});
    if (response['ok'] != true) {
      throw PlaybackEngineException('playlist failed: ${response['error']}');
    }
    return response;
  }

  /// Lyrics (lyrics text, source, isSynced)
  Future<Map<String, dynamic>> getLyrics(String videoId) async {
    await initialize();
    final response = await _sendRequest('lyrics', {'videoId': videoId});
    if (response['ok'] != true) {
      throw PlaybackEngineException('lyrics failed: ${response['error']}');
    }
    return response;
  }

  String _findJava() {
    if (_cachedJavaPath != null) return _cachedJavaPath!;

    final candidates = [
      r'C:\Program Files\Android\Android Studio\jbr\bin\java.exe',
      r'C:\Program Files\Java\jdk-21\bin\java.exe',
      r'C:\Program Files\Java\jdk-22\bin\java.exe',
      r'C:\Program Files\Java\jdk-23\bin\java.exe',
      'java',
    ];

    for (final path in candidates) {
      try {
        final needsShell = !path.contains(r'\');
        final r = Process.runSync(path, ['-version'], runInShell: needsShell);
        if (r.exitCode == 0) {
          _cachedJavaPath = path;
          AppLogger.playback('[$engineLabel] java resolved: $path');
          return path;
        }
      } catch (_) {}
    }

    throw PlaybackEngineException(
      'Java runtime পাওয়া যায়নি। innertube-cli.jar চালাতে JDK 21+ লাগবে।',
    );
  }

  String _findJar() {
    if (_cachedJarPath != null) return _cachedJarPath!;

    final candidates = [
      '${Directory.current.path}\\assets\\innertube-cli.jar',
      '${Directory.current.path}\\data\\flutter_assets\\assets\\innertube-cli.jar',
    ];

    for (final path in candidates) {
      if (File(path).existsSync()) {
        _cachedJarPath = path;
        return path;
      }
    }

    throw PlaybackEngineException(
      'innertube-cli.jar পাওয়া যায়নি। assets/innertube-cli.jar আছে কিনা '
      'যাচাই করুন। Checked paths: ${candidates.join(", ")}',
    );
  }

  @override
  Future<void> dispose() async {
    AppLogger.playback('[$engineLabel] disposing daemon...');

    _failAllPending('engine disposed');

    final daemon = _daemon;
    if (daemon != null) {
      try {
        daemon.stdin.writeln(jsonEncode({'id': '', 'cmd': 'shutdown'}));
        await daemon.stdin.flush();
        await daemon.stdin.close();

        final exited = await daemon.exitCode.timeout(
          const Duration(seconds: 3),
          onTimeout: () {
            daemon.kill();
            return -1;
          },
        );
        AppLogger.playback('[$engineLabel] daemon disposed (exit=$exited)');
      } catch (e) {
        AppLogger.error('[$engineLabel] dispose error, force killing', e);
        daemon.kill();
      }
    }

    await _stdoutSub?.cancel();
    await _stderrSub?.cancel();
    _daemon = null;
    _initFuture = null;
  }
}

extension on String {
  bool get isBlank => trim().isEmpty;
}