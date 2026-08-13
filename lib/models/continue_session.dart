import '../core/playback/playback_engine.dart';

/// Multi-song session snapshot for the Continue Session feature
/// (roadmap Section H).
///
/// ⚠️ Fix (Phase 0 v11 stabilization, revised): this used to back a
/// dedicated `ContinueSessions` Drift table, duplicating data
/// [QueueRepository] (data/repositories/queue_repository.dart) already
/// persists in `queue_items` (full queue + isCurrent + lastPositionMs).
/// [ContinueSessionManager] now builds this directly from
/// QueueRepository's existing loadQueue()/getCurrentPlaybackPosition() —
/// no new table, no duplicated state to keep in sync.
class ContinueSession {
  final SearchResult currentSong;
  final Duration currentPosition;
  final List<SearchResult> queueSnapshot;
  final int currentIndex;
  final String sourceRail;

  const ContinueSession({
    required this.currentSong,
    required this.currentPosition,
    required this.queueSnapshot,
    required this.currentIndex,
    required this.sourceRail,
  });

  int get remainingSongs => queueSnapshot.length - currentIndex - 1;
}
