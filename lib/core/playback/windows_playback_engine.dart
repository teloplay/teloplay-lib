import 'dart:convert';
import 'dart:io';
import 'dart:math';

import '../logging/app_logger.dart';
import 'playback_engine.dart';

/// Windows-এর জন্য PlaybackEngine implementation (yt-dlp)।
/// yt-dlp কে subprocess হিসেবে কল করে audio stream URL বের করে।
///
/// ⚠️ v6-এর পর থেকে এটা আর Windows-এর primary engine না —
/// [InnertubeWindowsPlaybackEngine] permanent primary। এই ফাইল emergency
/// fallback হিসেবে সম্পূর্ণ অক্ষত রাখা হয়েছে, কখনো delete করা হবে না।
/// Provider-এ এক লাইন বদলেই আবার সক্রিয় করা সম্ভব।
class WindowsPlaybackEngine implements PlaybackEngine {
  @override
  String get engineLabel => 'yt-dlp/windows';

  @override
  Future<void> initialize() async {
    AppLogger.playback('WindowsPlaybackEngine ready (yt-dlp resolved lazily per-call)');
  }

  @override
  Future<List<SearchResult>> search(String query, {int limit = 10}) async {
    AppLogger.playback('[$engineLabel] search: $query (limit=$limit)');

    final results = await _runYtDlpMulti([
      'ytsearch$limit:$query',
      '--dump-json',
      '--flat-playlist',
      '-f',
      'bestaudio/best',
    ]);

    if (results.isEmpty) {
      throw PlaybackEngineException('কোনো ফলাফল পাওয়া যায়নি query="$query"');
    }

    return results.map((result) {
      final videoId = result['id'] as String?;
      return SearchResult(
        videoId: videoId ?? '',
        title: (result['title'] as String?) ?? 'Unknown',
        author: (result['channel'] as String?) ??
            (result['uploader'] as String?) ??
            'Unknown',
        thumbnail: (result['thumbnail'] as String?) ??
            'https://img.youtube.com/vi/$videoId/mqdefault.jpg',
        duration: result['duration'] != null
            ? Duration(seconds: result['duration'] as int)
            : null,
      );
    }).where((r) => r.videoId.isNotEmpty).toList();
  }

  @override
  Future<ResolvedStream> resolveStream(String videoId) async {
    AppLogger.playback('[$engineLabel] resolveStream: $videoId');

    final url = 'https://www.youtube.com/watch?v=$videoId';
    final result = await Process.run(
      _findYtDlp(),
      [
        '-f', 'bestaudio/best',
        '--get-url',
        '--no-playlist',
        '--no-warnings',
        '--http-chunk-size', '10M',
        url,
      ],
      runInShell: true,
      stdoutEncoding: const SystemEncoding(),
      stderrEncoding: const SystemEncoding(),
    );

    if (result.exitCode != 0) {
      final stderrStr = result.stderr.toString();
      throw PlaybackEngineException(
        'yt-dlp failed: '
        '${stderrStr.substring(0, min(150, stderrStr.length))}',
      );
    }

    final out = result.stdout.toString().trim().split('\n').first.trim();
    if (!out.startsWith('http')) {
      throw PlaybackEngineException('Invalid URL from yt-dlp for videoId=$videoId');
    }

    AppLogger.playback('[$engineLabel] resolved OK: $videoId');

    return ResolvedStream(
      streamUrl: out,
      expiresIn: const Duration(hours: 5),
      sourceLabel: engineLabel,
    );
  }

  /// yt-dlp helper (json dump, multi-result search-এ ব্যবহৃত)।
  Future<List<Map<String, dynamic>>> _runYtDlpMulti(List<String> args) async {
    final fullArgs = [
      ...args,
      '--no-warnings',
      '--http-chunk-size', '10M',
    ];

    final result = await Process.run(
      _findYtDlp(),
      fullArgs,
      runInShell: true,
      stdoutEncoding: const SystemEncoding(),
      stderrEncoding: const SystemEncoding(),
    );

    if (result.exitCode != 0) {
      throw PlaybackEngineException('yt-dlp error: ${result.stderr}');
    }

    final output = result.stdout.toString().trim();
    final parsed = <Map<String, dynamic>>[];
    for (final line in output.split('\n')) {
      final trimmed = line.trim();
      if (trimmed.isEmpty) continue;
      try {
        parsed.add(jsonDecode(trimmed) as Map<String, dynamic>);
      } catch (_) {
        // malformed/অসম্পূর্ণ লাইন স্কিপ
      }
    }
    return parsed;
  }

  String _findYtDlp() {
    final possiblePaths = [
      'yt-dlp',
      'yt-dlp.exe',
      'C:\\Program Files\\yt-dlp\\yt-dlp.exe',
    ];
    for (final p in possiblePaths) {
      try {
        final r = Process.runSync(p, ['--version'], runInShell: true);
        if (r.exitCode == 0) return p;
      } catch (_) {}
    }
    throw PlaybackEngineException('yt-dlp পাওয়া যায়নি। "winget install yt-dlp" দিন');
  }

  // ⚠️ Phase 0.9 — Audio Focus placeholder hooks-এর explicit override।
  // পুরনো design (deprecated, দেখুন playback_engine.dart-এর নোট) —
  // আর ব্যবহার হচ্ছে না, কিন্তু backward-compat interface member হিসেবে
  // থাকতে হবে।
  @override
  Future<void> onAudioFocusLost() async {
    // no-op — দেখুন audioFocusStream (নিচে)
  }

  @override
  Future<void> onAudioFocusGained() async {
    // no-op — দেখুন audioFocusStream (নিচে)
  }

  @override
  Stream<double>? get bufferHealthStream => null; // TODO

  // ⚠️ Audio Focus Ducking (Phase 1) — yt-dlp fallback engine-এ কোনো OS
  // audio-focus integration নেই (কখনো active হলে ducking ছাড়াই চলবে,
  // non-critical, safe fallback)। `implements PlaybackEngine` ব্যবহারের
  // কারণে explicit override বাধ্যতামূলক (নিচের searchSuggestions-এর
  // মন্তব্য দেখুন — একই কারণে build error হচ্ছিল)।
  @override
  Stream<AudioFocusSignal>? get audioFocusStream => null;

  // ⚠️ Bluetooth Optimization (Phase 1) — এই engine-এ কোনো Bluetooth/
  // device-change integration নেই (Windows fallback engine, non-
  // critical)। explicit no-op override — `implements PlaybackEngine`
  // ব্যবহারের কারণে বাধ্যতামূলক।
  @override
  Stream<String?>? get connectedAudioDeviceStream => null; // TODO(Phase 7+)

  // ⚠️ Live Search Suggestions — yt-dlp-এ কোনো suggestion endpoint নেই,
  // তাই এই fallback engine সবসময় খালি list দেয় (interface-এর default
  // no-op-এর মতোই আচরণ, কিন্তু explicit override হিসেবে রাখা হলো —
  // `implements PlaybackEngine` ব্যবহার করায় Dart-এর abstract member
  // resolution default body inherit করছিল না, তাই প্রতিটা engine-এ
  // explicit override বাধ্যতামূলক হয়ে যাচ্ছিল build error হিসেবে)।
  @override
  Future<List<String>> searchSuggestions(String query) async => [];

  @override
  Future<void> dispose() async {
    // কোনো persistent resource/process নেই — প্রতিটা resolve নিজের
    // subprocess শুরু-শেষ করে।
  }
}