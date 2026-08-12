import 'song_model.dart';

/// Multi-song session snapshot for Continue Session feature.
class ContinueSession {
  final String sessionId;
  final SongModel currentSong;
  final Duration currentPosition;
  final List<SongModel> queueSnapshot;
  final int currentIndex;
  final DateTime lastPlayedAt;
  final String sourceRail;

  ContinueSession({
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
    SongModel? currentSong,
    Duration? currentPosition,
    List<SongModel>? queueSnapshot,
    int? currentIndex,
    DateTime? lastPlayedAt,
    String? sourceRail,
  }) => ContinueSession(
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
    'currentSongId': currentSong.id,
    'currentPositionMs': currentPosition.inMilliseconds,
    'queueCount': queueSnapshot.length,
    'currentIndex': currentIndex,
    'lastPlayedAt': lastPlayedAt.toIso8601String(),
    'sourceRail': sourceRail,
  };
}