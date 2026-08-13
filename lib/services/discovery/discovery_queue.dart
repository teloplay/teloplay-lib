import 'dart:async';
import 'dart:collection';

import '../../core/logging/app_logger.dart';
import '../metadata/lastfm_client.dart';
import '../metadata/musicbrainz_client.dart';
import '../metadata/deezer_client.dart';
import '../cache/metadata_cache_service.dart';

/// Rate-limited background batch processor for discovery enrichment.
/// NEVER blocks UI thread. Uses queue + timer-based processing.
class DiscoveryQueue {
  final LastFmClient? _lastFm;
  final MusicBrainzClient? _musicBrainz;
  final DeezerClient _deezer;
  final MetadataCacheService _cache;

  final Queue<_DiscoveryTask> _queue = Queue();
  Timer? _processorTimer;
  bool _isProcessing = false;

  // Rate limits (requests per second)
  static const _lastFmRate = 0.5; // 1 req per 2 seconds
  static const _musicBrainzRate = 1.0; // 1 req per second
  static const _deezerRate = 10.0; // 10 req per second (well within 50/5s)

  DateTime? _lastLastFmCall;
  DateTime? _lastMusicBrainzCall;
  DateTime? _lastDeezerCall;

  DiscoveryQueue({
    required LastFmClient? lastFm,
    required MusicBrainzClient? musicBrainz,
    required DeezerClient deezer,
    required MetadataCacheService cache,
  })  : _lastFm = lastFm,
        _musicBrainz = musicBrainz,
        _deezer = deezer,
        _cache = cache;

  /// Start background processor.
  void start() {
    if (_processorTimer != null) return;
    _processorTimer = Timer.periodic(const Duration(seconds: 1), (_) => _process());
    AppLogger.discovery('DiscoveryQueue started');
  }

  /// Stop background processor.
  void stop() {
    _processorTimer?.cancel();
    _processorTimer = null;
    AppLogger.discovery('DiscoveryQueue stopped');
  }

  /// Enqueue a discovery task. Non-blocking.
  void enqueueSimilarArtists(String artistName, {String? artistId}) {
    _queue.add(_DiscoveryTask(
      type: _TaskType.similarArtists,
      artistName: artistName,
      artistId: artistId,
      priority: _TaskPriority.high,
    ));
  }

  void enqueueArtistTags(String artistName) {
    _queue.add(_DiscoveryTask(
      type: _TaskType.artistTags,
      artistName: artistName,
      priority: _TaskPriority.normal,
    ));
  }

  void enqueueTrending() {
    _queue.add(_DiscoveryTask(
      type: _TaskType.trending,
      priority: _TaskPriority.low,
    ));
  }

  void enqueueMusicBrainzRelations(String mbid) {
    _queue.add(_DiscoveryTask(
      type: _TaskType.mbRelations,
      mbid: mbid,
      priority: _TaskPriority.normal,
    ));
  }

  /// Process one item from queue respecting rate limits.
  Future<void> _process() async {
    if (_isProcessing || _queue.isEmpty) return;
    _isProcessing = true;

    try {
      final task = _queue.removeFirst();

      switch (task.type) {
        case _TaskType.similarArtists:
          await _processSimilarArtists(task);
          break;
        case _TaskType.artistTags:
          await _processArtistTags(task);
          break;
        case _TaskType.trending:
          await _processTrending();
          break;
        case _TaskType.mbRelations:
          await _processMbRelations(task);
          break;
      }
    } catch (e) {
      AppLogger.error('DiscoveryQueue process error: $e');
    } finally {
      _isProcessing = false;
    }
  }

  Future<void> _processSimilarArtists(_DiscoveryTask task) async {
    if (!await _canCall(_lastDeezerCall, _deezerRate)) return;

    // Try Deezer first (instant path)
    if (task.artistId != null) {
      _lastDeezerCall = DateTime.now();
      final similar = await _deezer.getSimilarArtists(task.artistId!);
      AppLogger.discovery('Deezer similar artists: ${similar.length} for ${task.artistName}');
    }

    // Last.fm enrichment (background) — only if client available AND artistName not null
    if (_lastFm != null && task.artistName != null && await _canCall(_lastLastFmCall, _lastFmRate)) {
      _lastLastFmCall = DateTime.now();
      final similar = await _lastFm.getSimilarArtists(task.artistName!);
      AppLogger.discovery('Last.fm similar artists: ${similar.length} for ${task.artistName}');
    }
  }

  Future<void> _processArtistTags(_DiscoveryTask task) async {
    // FIX: Null check before calling _lastFm methods
    if (_lastFm == null || task.artistName == null) return;
    if (!await _canCall(_lastLastFmCall, _lastFmRate)) {
      _queue.addFirst(task); // Retry later
      return;
    }
    _lastLastFmCall = DateTime.now();
    final tags = await _lastFm.getArtistTags(task.artistName!);
    AppLogger.discovery('Last.fm tags: $tags for ${task.artistName}');
  }

  Future<void> _processTrending() async {
    // FIX: Null check before calling _lastFm methods
    if (_lastFm == null) return;
    if (!await _canCall(_lastLastFmCall, _lastFmRate)) return;
    _lastLastFmCall = DateTime.now();
    final trending = await _lastFm.getTrendingTracks();
    AppLogger.discovery('Last.fm trending: ${trending.length} tracks');
  }

  Future<void> _processMbRelations(_DiscoveryTask task) async {
    // FIX: Null check before calling _musicBrainz methods
    if (_musicBrainz == null || task.mbid == null) return;
    if (!await _canCall(_lastMusicBrainzCall, _musicBrainzRate)) {
      _queue.addFirst(task);
      return;
    }
    _lastMusicBrainzCall = DateTime.now();
    final relations = await _musicBrainz.getArtistRelations(task.mbid!);
    AppLogger.discovery('MusicBrainz relations: ${relations.length} for ${task.mbid}');
  }

  /// Check if enough time has passed since last call.
  Future<bool> _canCall(DateTime? lastCall, double ratePerSecond) async {
    if (lastCall == null) return true;
    final requiredGap = Duration(milliseconds: (1000 / ratePerSecond).round());
    return DateTime.now().difference(lastCall) >= requiredGap;
  }

  /// Get pending queue size.
  int get pendingCount => _queue.length;

  /// Clear all pending tasks.
  void clear() {
    _queue.clear();
    AppLogger.discovery('DiscoveryQueue cleared');
  }
}

enum _TaskType {
  similarArtists,
  artistTags,
  trending,
  mbRelations,
}

enum _TaskPriority {
  high,
  normal,
  low,
}

class _DiscoveryTask {
  final _TaskType type;
  final String? artistName;
  final String? artistId;
  final String? mbid;
  final _TaskPriority priority;

  _DiscoveryTask({
    required this.type,
    this.artistName,
    this.artistId,
    this.mbid,
    this.priority = _TaskPriority.normal,
  });
}