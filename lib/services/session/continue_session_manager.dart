import '../../core/logging/app_logger.dart';
import '../../core/playback/playback_engine.dart';
import '../../data/repositories/music_player_repository.dart';
import '../../data/repositories/queue_repository.dart';
import '../../data/repositories/settings_repository.dart';
import '../../models/continue_session.dart';

/// Reads/restores the Continue Session (multi-song resume, roadmap
/// Section H) on top of the app's existing queue persistence.
///
/// ⚠️ Fix (Phase 0 v11 stabilization, revised): originally designed
/// around a dedicated `ContinueSessions` Drift table + a full duplicate
/// save path — but [QueueRepository] already persists the entire queue,
/// current index and per-song `lastPositionMs` on every track change
/// (see saveQueue/updateCurrentIndex/updatePlaybackPosition in
/// queue_repository.dart, wired from MusicPlayerRepository already).
/// There is nothing left for this class to "save" — it only needs to
/// *read* that existing state back into a [ContinueSession] view and
/// hand off to MusicPlayerRepository to restore playback. The only new
/// piece of state genuinely missing from queue_items is `sourceRail`
/// ("Daily Mix", a playlist name, etc.) — that alone is kept in Settings.
class ContinueSessionManager {
  final QueueRepository _queueRepo;
  final SettingsRepository _settings;

  static const _kSourceRail = 'resume_sourceRail';
  static const _kDismissed = 'resume_dismissed';

  ContinueSessionManager({
    required QueueRepository queueRepository,
    required SettingsRepository settings,
  })  : _queueRepo = queueRepository,
        _settings = settings;

  /// Record which rail/context the currently-playing queue came from
  /// ("Daily Mix", a playlist name, etc). Call this whenever
  /// MusicPlayerRepository.playFromContext() is invoked with a named
  /// source, so the Continue Session card can say "From: Daily Mix".
  Future<void> setSourceRail(String sourceRail) async {
    await _settings.setValue(_kSourceRail, sourceRail);
    // A fresh play session means any previous dismissal no longer applies.
    await _settings.setValue(_kDismissed, '');
  }

  /// Check for a resumable session on app launch. Returns null if there's
  /// nothing to resume, the position is negligible, or the user dismissed
  /// this exact session already.
  Future<ContinueSession?> checkForResume() async {
    final loaded = await _queueRepo.loadQueue();
    if (loaded.queue.isEmpty || loaded.currentIndex < 0) return null;

    final positionInfo = await _queueRepo.getCurrentPlaybackPosition();
    if (positionInfo == null || positionInfo.positionMs <= 0) return null;

    final dismissedId = await _settings.getValue(_kDismissed);
    if (dismissedId == positionInfo.songId) return null;

    final sourceRail = await _settings.getValue(_kSourceRail);

    return ContinueSession(
      currentSong: loaded.queue[loaded.currentIndex],
      currentPosition: Duration(milliseconds: positionInfo.positionMs),
      queueSnapshot: loaded.queue,
      currentIndex: loaded.currentIndex,
      sourceRail: (sourceRail == null || sourceRail.isEmpty)
          ? 'Your queue'
          : sourceRail,
    );
  }

  /// Restore session to the player: reload the full queue at the saved
  /// index, then seek to the saved position.
  Future<void> restoreSession(
    ContinueSession session,
    MusicPlayerRepository musicRepo,
  ) async {
    AppLogger.session(
      'Restoring session: ${session.currentSong.videoId} '
      'at ${session.currentPosition.inSeconds}s '
      '(${session.queueSnapshot.length} songs)',
    );

    var resumePosition = session.currentPosition;
    final songDuration = session.currentSong.duration;
    if (songDuration != null && resumePosition > songDuration) {
      resumePosition = Duration.zero;
    }

    await musicRepo.playFromContext(
      tracks: session.queueSnapshot,
      startIndex: session.currentIndex,
      source: QueueSource.resumedSession,
    );

    if (resumePosition > Duration.zero) {
      await musicRepo.seek(resumePosition);
    }
  }

  /// Dismiss the current resume card without deleting the underlying
  /// queue (the user might still want it available from the mini
  /// player) — just stops showing the Continue Session card for this
  /// specific song until a new one starts playing.
  Future<void> dismiss(String songId) async {
    await _settings.setValue(_kDismissed, songId);
    AppLogger.session('Session dismissed: $songId');
  }
}
