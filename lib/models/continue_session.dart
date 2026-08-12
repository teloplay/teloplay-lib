import '../core/playback/playback_engine.dart';

/// Multi-song session snapshot for Continue Session feature.
///
/// ⚠️ Fix (Phase 0 v11 stabilization): originally written against a
/// `SongModel` that does not exist anywhere in this codebase. The app's
/// actual song shape is [SearchResult] (playback_engine.dart) — same type
/// [ContinueSessionManager] already receives from the player. No new model
/// introduced.
class ContinueSession {
  final String sessionId;
  final SearchResult currentSong;
  final Duration currentPosition;
  final List<SearchResult> queueSnapshot;
  final int currentIndex;
  final DateTime lastPlayedAt;
  final String sourceRail;

  const ContinueSession({
    required this.sessionId,
    required this.currentSong,
    required this.currentPosition,
    required this.queueSnapshot,
    required this.currentIndex,
    required this.lastPlayedAt,
    required this.sourceRail,
  });

  ContinueSession copyWith({
    String? sessionId,
    SearchResult? currentSong,
    Duration? currentPosition,
    List<SearchResult>? queueSnapshot,
    int? currentIndex,
    DateTime? lastPlayedAt,
    String? sourceRail,
  }) =>
      ContinueSession(
        sessionId: sessionId ?? this.sessionId,
        currentSong: currentSong ?? this.currentSong,
        currentPosition: currentPosition ?? this.currentPosition,
        queueSnapshot: queueSnapshot ?? this.queueSnapshot,
        currentIndex: currentIndex ?? this.currentIndex,
        lastPlayedAt: lastPlayedAt ?? this.lastPlayedAt,
        sourceRail: sourceRail ?? this.sourceRail,
      );

  Map<String, dynamic> toJson() => {
        'sessionId': sessionId,
        'currentSongId': currentSong.videoId,
        'currentPositionMs': currentPosition.inMilliseconds,
        'queueCount': queueSnapshot.length,
        'currentIndex': currentIndex,
        'lastPlayedAt': lastPlayedAt.toIso8601String(),
        'sourceRail': sourceRail,
      };
}

/// Minimal JSON (de)serialization for [SearchResult] queue snapshots.
///
/// [SearchResult] itself has no toJson/fromJson (it's a playback-layer
/// value type, not a persistence model) — these free functions live here
/// instead of adding persistence concerns to playback_engine.dart.
Map<String, dynamic> searchResultToJson(SearchResult r) => {
      'videoId': r.videoId,
      'title': r.title,
      'author': r.author,
      'thumbnail': r.thumbnail,
      'durationSeconds': r.duration?.inSeconds,
      'artistId': r.artistId,
      'albumId': r.albumId,
      'albumName': r.albumName,
      'allArtistNames': r.allArtistNames,
      'allArtistIds': r.allArtistIds,
      'explicit': r.explicit,
      'chartPosition': r.chartPosition,
      'chartChange': r.chartChange,
      'setVideoId': r.setVideoId,
    };

SearchResult searchResultFromJson(Map<String, dynamic> j) => SearchResult(
      videoId: j['videoId'] as String,
      title: j['title'] as String,
      author: j['author'] as String,
      thumbnail: j['thumbnail'] as String,
      duration: j['durationSeconds'] != null
          ? Duration(seconds: j['durationSeconds'] as int)
          : null,
      artistId: j['artistId'] as String?,
      albumId: j['albumId'] as String?,
      albumName: j['albumName'] as String?,
      allArtistNames: (j['allArtistNames'] as List?)?.cast<String>() ?? const [],
      allArtistIds: (j['allArtistIds'] as List?)?.cast<String?>() ?? const [],
      explicit: j['explicit'] as bool? ?? false,
      chartPosition: j['chartPosition'] as int?,
      chartChange: j['chartChange'] as String?,
      setVideoId: j['setVideoId'] as String?,
    );
