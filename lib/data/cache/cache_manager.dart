import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data'; // ← BytesBuilder এখানে আছে

import 'package:http/http.dart' as http;

import '../../core/logging/app_logger.dart';
import 'media_asset_manager.dart';

/// একটা audio cache lookup/store attempt-এর ফলাফল।
class AudioCacheResult {
  /// Cache hit হলে local file path (media_kit-এ সরাসরি `Media(path)`
  /// হিসেবে দেওয়া যাবে, `file://` prefix caller প্রয়োজনে যোগ করবে)।
  final String? localFilePath;
  final bool isHit;

  const AudioCacheResult({this.localFilePath, required this.isHit});

  static const miss = AudioCacheResult(isHit: false);
}

/// ⚠️ Phase 3 Item C (Thumbnail Cache Wiring) — audio-র
/// `AudioCacheResult`-এর সমান্তরাল কিন্তু ইচ্ছাকৃতভাবে আলাদা টাইপ।
/// Thumbnail আর audio result shape এখন identical (path + isHit), কিন্তু
/// আলাদা নাম রাখা হয়েছে যাতে ভবিষ্যতে কোনো একটাতে নতুন field (যেমন
/// thumbnail-এ image dimensions, audio-তে duration) যোগ করলে অন্যটা
/// অপ্রয়োজনীয়ভাবে প্রভাবিত না হয়, এবং caller-side টাইপ confusion
/// (audio result thumbnail slot-এ ভুল করে বসানো ইত্যাদি) কম্পাইল-টাইমেই
/// ধরা পড়ে।
class ThumbnailCacheResult {
  final String? localFilePath;
  final bool isHit;

  const ThumbnailCacheResult({this.localFilePath, required this.isHit});

  static const miss = ThumbnailCacheResult(isHit: false);
}

/// ⚠️ Phase 3 (Smart Cache Engine) — Audio-specific cache orchestration।
///
/// `MediaAssetManager` (generic, filesystem-level, asset-agnostic) আর
/// playback layer-এর মধ্যে সেতু। এই ক্লাস জানে *কীভাবে* audio bytes
/// আনতে হয় (HTTP download resolved stream URL থেকে) এবং *কখন* cache
/// করা উচিত (background download-throttling সিদ্ধান্ত এখানে না,
/// `CacheService`-এ — দেখো নিচের নোট)।
///
/// এই ক্লাস ইচ্ছাকৃতভাবে `PlaybackEngine`/`ResolvedStream` টাইপ
/// সরাসরি import করে না (`lib/core/playback/` থেকে) — download শুরু
/// করার জন্য শুধু একটা প্লেইন `streamUrl` string নেয়। এতে
/// `lib/data/cache/` layer playback abstraction থেকে independent থাকে।
///
/// ✅ Phase 3 Item C: এই ধারণাই thumbnail-এর জন্যও কাজে লাগলো —
/// `cacheThumbnail()` একইভাবে শুধু plain `imageUrl` string নেয়, কোনো
/// playback/UI টাইপের উপর নির্ভরশীল না।
class CacheManager {
  final MediaAssetManager _assetManager;
  final http.Client _httpClient;

  CacheManager(this._assetManager, {http.Client? httpClient})
      : _httpClient = httpClient ?? http.Client();

  // ⚠️ ইতিমধ্যে-চলমান download-গুলো ট্র্যাক রাখা হচ্ছে, যাতে একই videoId-এর
  // জন্য একাধিক concurrent download শুরু না হয়ে যায়।
  final Map<String, Future<AudioCacheResult>> _inFlightDownloads = {};

  // ⚠️ Thumbnail-এর জন্য আলাদা in-flight map — audio-র videoId key-space
  // এর সাথে কখনো accidental collision না হয় সেটা নিশ্চিত করতে (আলাদা
  // asset type, আলাদা tracking, যদিও বাস্তবে key একই videoId হতে পারে)।
  final Map<String, Future<ThumbnailCacheResult>> _inFlightThumbnails = {};

  /// এই videoId-এর জন্য audio ইতিমধ্যে cache-এ আছে কিনা চেক করা (দ্রুত,
  /// filesystem stat-only, download না)।
  Future<AudioCacheResult> checkCache(String videoId) async {
    final result = await _assetManager.get(
      MediaAssetType.audio,
      videoId,
    );

    if (!result.isHit || result.file == null) {
      return AudioCacheResult.miss;
    }

    return AudioCacheResult(
      localFilePath: result.file!.path,
      isHit: true,
    );
  }

  /// ✅ Phase 3 Item C — thumbnail cache lookup (filesystem stat-only,
  /// download না)। `.jpg` extension দিয়ে lookup করা হয় (দেখো
  /// `cacheThumbnail()`-এর নোট — সব thumbnail write-time-এ `.jpg`
  /// extension দিয়ে save হয়, ফলে lookup-এও একই extension দরকার, নাহলে
  /// hit থাকা সত্ত্বেও miss রিটার্ন হবে filename mismatch-এর কারণে)।
  Future<ThumbnailCacheResult> checkThumbnailCache(String videoId) async {
    final result = await _assetManager.get(
      MediaAssetType.thumbnail,
      videoId,
      extension: '.jpg',
    );

    if (!result.isHit || result.file == null) {
      return ThumbnailCacheResult.miss;
    }

    return ThumbnailCacheResult(
      localFilePath: result.file!.path,
      isHit: true,
    );
  }

  /// [streamUrl] থেকে audio bytes download করে cache-এ রাখা।
  Future<({AudioCacheResult result, List<String> evictionCandidates})>
      cacheAudio({
    required String videoId,
    required String streamUrl,
  }) async {
    final existing = _inFlightDownloads[videoId];
    if (existing != null) {
      AppLogger.performance(
        '[audio-cache] joining in-flight download: $videoId',
      );
      final result = await existing;
      return (result: result, evictionCandidates: <String>[]);
    }

    final cached = await checkCache(videoId);
    if (cached.isHit) {
      return (result: cached, evictionCandidates: <String>[]);
    }

    final completer = Completer<AudioCacheResult>();
    _inFlightDownloads[videoId] = completer.future;

    List<String> evictionCandidates = [];

    try {
      final downloadedBytes = await _downloadWithRetry(streamUrl, videoId);

      final putResult = await _assetManager.put(
        MediaAssetType.audio,
        videoId,
        downloadedBytes,
      );

      if (putResult == null) {
        completer.complete(AudioCacheResult.miss);
        return (result: AudioCacheResult.miss, evictionCandidates: <String>[]);
      }

      evictionCandidates = putResult.evictionCandidates;
      final result = AudioCacheResult(
        localFilePath: putResult.file.path,
        isHit: true,
      );
      completer.complete(result);
      return (result: result, evictionCandidates: evictionCandidates);
    } catch (e) {
      AppLogger.error('CacheManager.cacheAudio failed (videoId=$videoId)', e);
      completer.complete(AudioCacheResult.miss);
      return (result: AudioCacheResult.miss, evictionCandidates: <String>[]);
    } finally {
      _inFlightDownloads.remove(videoId);
    }
  }

  /// ✅ Phase 3 Item C — [imageUrl] থেকে thumbnail bytes download করে
  /// cache-এ রাখা।
  ///
  /// Audio-র `cacheAudio()`-এর তুলনায় ইচ্ছাকৃতভাবে সরল রাখা হয়েছে:
  ///   - কোনো Range-probe/parallel-chunk logic নেই — thumbnail সাধারণত
  ///     কয়েক KB থেকে সর্বোচ্চ কয়েকশ KB, ৪-connection parallel download-এর
  ///     setup overhead-ই এখানে মূল খরচ হয়ে দাঁড়াতো, লাভের চেয়ে ক্ষতি
  ///     বেশি।
  ///   - single streamed GET (`_downloadSequential`-এর মতোই pattern,
  ///     কিন্তু duplicate না করে ছোট আলাদা inline implementation — audio
  ///     path পুরোপুরি ভিন্ন retry/chunking নীতি বহন করে, শেয়ার করলে দুটো
  ///     ভিন্ন concern জড়িয়ে যেত)।
  ///   - Retry হালকা: max ১ retry, ৫০০ms delay (audio-র max ২, ৫০০/১০০০ms
  ///     এর তুলনায়) — thumbnail miss হলে UI graceful placeholder-এ পড়ে
  ///     থাকে (`CachedArtwork`-এর error/fallback state), এটা audio miss-এর
  ///     মতো playback-blocking সমস্যা না, তাই আক্রমণাত্মক retry নীতির
  ///     দরকার নেই।
  ///   - সব thumbnail `.jpg` extension দিয়ে save হয় (YouTube thumbnail
  ///     URL সবসময় JPEG সার্ভ করে; ভিন্ন format হলেও `Image.file` decode
  ///     করার সময় actual bytes দিয়েই format detect করে, extension নিছক
  ///     filename-এর জন্য)।
  ///
  /// non-throwing — ব্যর্থ হলে miss রিটার্ন করে।
  Future<({ThumbnailCacheResult result, List<String> evictionCandidates})>
      cacheThumbnail({
    required String videoId,
    required String imageUrl,
  }) async {
    final existing = _inFlightThumbnails[videoId];
    if (existing != null) {
      final result = await existing;
      return (result: result, evictionCandidates: <String>[]);
    }

    final cached = await checkThumbnailCache(videoId);
    if (cached.isHit) {
      return (result: cached, evictionCandidates: <String>[]);
    }

    final completer = Completer<ThumbnailCacheResult>();
    _inFlightThumbnails[videoId] = completer.future;

    List<String> evictionCandidates = [];

    try {
      final bytes = await _downloadThumbnailWithRetry(imageUrl, videoId);

      final putResult = await _assetManager.put(
        MediaAssetType.thumbnail,
        videoId,
        bytes,
        extension: '.jpg',
      );

      if (putResult == null) {
        completer.complete(ThumbnailCacheResult.miss);
        return (
          result: ThumbnailCacheResult.miss,
          evictionCandidates: <String>[],
        );
      }

      evictionCandidates = putResult.evictionCandidates;
      final result = ThumbnailCacheResult(
        localFilePath: putResult.file.path,
        isHit: true,
      );
      completer.complete(result);
      return (result: result, evictionCandidates: evictionCandidates);
    } catch (e) {
      AppLogger.performance(
        '[thumbnail-cache] download failed (videoId=$videoId): $e',
      );
      completer.complete(ThumbnailCacheResult.miss);
      return (
        result: ThumbnailCacheResult.miss,
        evictionCandidates: <String>[],
      );
    } finally {
      _inFlightThumbnails.remove(videoId);
    }
  }

  static const _thumbnailMaxRetries = 1;
  static const _thumbnailRetryDelay = Duration(milliseconds: 500);

  Future<List<int>> _downloadThumbnailWithRetry(
    String imageUrl,
    String videoId,
  ) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _thumbnailMaxRetries; attempt++) {
      try {
        final request = http.Request('GET', Uri.parse(imageUrl));
        final streamedResponse = await _httpClient.send(request);

        if (streamedResponse.statusCode != 200) {
          throw Exception('HTTP ${streamedResponse.statusCode}');
        }

        final builder = BytesBuilder(copy: false);
        await for (final chunk in streamedResponse.stream) {
          builder.add(chunk);
        }
        return builder.takeBytes();
      } catch (e) {
        lastError = e;
        final isLastAttempt = attempt == _thumbnailMaxRetries;
        if (isLastAttempt) break;
        await Future.delayed(_thumbnailRetryDelay);
      }
    }
    throw lastError ?? Exception('Unknown thumbnail download failure');
  }

  // ⚠️ Bug fix — `http.get()` (single-shot, পুরো response body একসাথে
  // buffer করে) YouTube-এর googlevideo.com CDN-এ বড়/দীর্ঘ audio stream-এর
  // জন্য প্রায়ই `ClientException: Connection closed while receiving
  // data` দিয়ে ব্যর্থ হচ্ছিল — এটা CDN-এর পরিচিত আচরণ। Fix: streamed
  // request।
  static const _downloadMaxRetries = 2;
  static const _downloadRetryDelays = [
    Duration(milliseconds: 500),
    Duration(milliseconds: 1000),
  ];

  static const _parallelChunkCount = 4;
  static const _minSizeForParallelDownload = 2 * 1024 * 1024; // 2MB

  Future<List<int>> _downloadWithRetry(String streamUrl, String videoId) async {
    Object? lastError;
    for (var attempt = 0; attempt <= _downloadMaxRetries; attempt++) {
      try {
        AppLogger.performance(
          '[audio-cache] downloading (attempt ${attempt + 1}/'
          '${_downloadMaxRetries + 1}): $videoId',
        );

        final bytes = await _downloadParallelOrFallback(streamUrl, videoId);

        AppLogger.performance(
          '[audio-cache] downloaded ${(bytes.length / 1024).toStringAsFixed(0)}KB: $videoId',
        );
        return bytes;
      } catch (e) {
        lastError = e;
        final isLastAttempt = attempt == _downloadMaxRetries;
        AppLogger.performance(
          '[audio-cache] download attempt ${attempt + 1} failed for '
          '$videoId: $e${isLastAttempt ? ' (giving up)' : ', retrying...'}',
        );
        if (isLastAttempt) break;
        await Future.delayed(_downloadRetryDelays[attempt]);
      }
    }
    throw lastError ?? Exception('Unknown download failure');
  }

  Future<List<int>> _downloadParallelOrFallback(
    String streamUrl,
    String videoId,
  ) async {
    int? contentLength;
    try {
      final probeRequest = http.Request('GET', Uri.parse(streamUrl))
        ..headers['Range'] = 'bytes=0-0';
      final probeResponse = await _httpClient.send(probeRequest);
      await probeResponse.stream.drain();

      if (probeResponse.statusCode == 206) {
        final contentRange = probeResponse.headers['content-range'];
        if (contentRange != null) {
          final match = RegExp(r'/(\d+)$').firstMatch(contentRange);
          if (match != null) {
            contentLength = int.tryParse(match.group(1)!);
          }
        }
      }
    } catch (e) {
      AppLogger.performance(
        '[audio-cache] range-probe failed, falling back to sequential '
        '($videoId): $e',
      );
    }

    if (contentLength == null || contentLength < _minSizeForParallelDownload) {
      return _downloadSequential(streamUrl, videoId);
    }

    try {
      return await _downloadInParallelChunks(
        streamUrl,
        videoId,
        contentLength,
      );
    } catch (e) {
      AppLogger.performance(
        '[audio-cache] parallel chunk download failed, falling back to '
        'sequential ($videoId): $e',
      );
      return _downloadSequential(streamUrl, videoId);
    }
  }

  Future<List<int>> _downloadSequential(
    String streamUrl,
    String videoId,
  ) async {
    final request = http.Request('GET', Uri.parse(streamUrl));
    final streamedResponse = await _httpClient.send(request);

    if (streamedResponse.statusCode != 200) {
      throw Exception('HTTP ${streamedResponse.statusCode}');
    }

    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamedResponse.stream) {
      builder.add(chunk);
    }
    return builder.takeBytes();
  }

  Future<List<int>> _downloadInParallelChunks(
    String streamUrl,
    String videoId,
    int totalBytes,
  ) async {
    final chunkSize = (totalBytes / _parallelChunkCount).ceil();
    final ranges = <({int start, int end})>[];

    for (var i = 0; i < _parallelChunkCount; i++) {
      final start = i * chunkSize;
      if (start >= totalBytes) break;
      final end = math.min(start + chunkSize - 1, totalBytes - 1);
      ranges.add((start: start, end: end));
    }

    AppLogger.performance(
      '[audio-cache] parallel download: ${ranges.length} chunks, '
      '${(totalBytes / 1024).toStringAsFixed(0)}KB total ($videoId)',
    );

    final chunkFutures = ranges.map((range) async {
      final request = http.Request('GET', Uri.parse(streamUrl))
        ..headers['Range'] = 'bytes=${range.start}-${range.end}';
      final response = await _httpClient.send(request);

      if (response.statusCode != 206 && response.statusCode != 200) {
        throw Exception(
          'Range request failed: HTTP ${response.statusCode}',
        );
      }

      final builder = BytesBuilder(copy: false);
      await for (final chunk in response.stream) {
        builder.add(chunk);
      }
      return builder.takeBytes();
    }).toList();

    final chunks = await Future.wait(chunkFutures);

    final result = BytesBuilder(copy: false);
    for (final chunk in chunks) {
      result.add(chunk);
    }
    return result.takeBytes();
  }

  /// একটা নির্দিষ্ট videoId-এর cached audio evict করা।
  Future<void> evictAudio(String videoId) =>
      _assetManager.evict(MediaAssetType.audio, videoId);

  /// ✅ Phase 3 Item C — cached thumbnail evict করা।
  Future<void> evictThumbnail(String videoId) =>
      _assetManager.evict(MediaAssetType.thumbnail, videoId);

  void dispose() {
    _httpClient.close();
  }
}