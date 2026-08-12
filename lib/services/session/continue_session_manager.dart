import 'dart:convert';

import '../../core/logging/app_logger.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/settings_repository.dart';
import '../../models/continue_session.dart';
import '../../models/song_model.dart';

/// Manages multi-song session persistence and restoration.
/// Saves: current song + position + full queue snapshot + source rail.
class ContinueSessionManager {
  final AppDatabase _db;
  final SettingsRepository _settings;

  ContinueSessionManager({
    required AppDatabase db,
    required SettingsRepository settings,
  })  : _db = db,
        _settings = settings;

  /// Save current session state.
  Future<void> saveSession({
    required SongModel currentSong,
    required Duration currentPosition,
    required List<SongModel> queueSnapshot,
    required int currentIndex,
    required String sourceRail,
  }) async {
    final session = ContinueSession(
      sessionId: DateTime.now().millisecondsSinceEpoch.toString(),
      currentSong: currentSong,
      currentPosition: currentPosition,
      queueSnapshot: queueSnapshot,
      currentIndex: currentIndex,
      lastPlayedAt: DateTime.now(),
      sourceRail: sourceRail,
    );

    // Save to Drift
    await _db.into(_db.continueSessions).insertOnConflictUpdate(
      ContinueSessionsCompanion(
        id: Value(session.sessionId),
        currentSongId: Value(currentSong.id),
        currentPositionMs: Value(currentPosition.inMilliseconds),
        queueSnapshot: Value(jsonEncode(queueSnapshot.map((s) => s.toJson()).toList())),
        currentIndex: Value(currentIndex),
        sourceRail: Value(sourceRail),
        lastPlayedAt: Value(DateTime.now()),
      ),
    );

    // Backup to Settings (for faster cold-start read)
    await _settings.setString('resume_sessionId', session.sessionId);
    await _settings.setString('resume_currentSongId', currentSong.id);
    await _settings.setInt('resume_currentPositionMs', currentPosition.inMilliseconds);
    await _settings.setString('resume_queueSnapshot', jsonEncode(queueSnapshot.map((s) => s.toJson()).toList()));
    await _settings.setInt('resume_currentIndex', currentIndex);
    await _settings.setString('resume_sourceRail', sourceRail);
    await _settings.setDateTime('resume_timestamp', DateTime.now());

    AppLogger.session('Session saved: ${session.sessionId} (${queueSnapshot.length} songs)');
  }

  /// Check and restore session on app launch.
  Future<ContinueSession?> checkForResume() async {
    final sessionId = await _settings.getString('resume_sessionId');
    final currentSongId = await _settings.getString('resume_currentSongId');
    final currentPosition = await _settings.getInt('resume_currentPositionMs');
    final queueJson = await _settings.getString('resume_queueSnapshot');
    final currentIndex = await _settings.getInt('resume_currentIndex');
    final sourceRail = await _settings.getString('resume_sourceRail');
    final timestamp = await _settings.getDateTime('resume_timestamp');

    if (currentSongId == null || currentPosition == null) return null;

    // Discard if older than 7 days
    if (timestamp != null && DateTime.now().difference(timestamp).inDays > 7) {
      await clearSession();
      return null;
    }

    // Reconstruct queue
    List<SongModel> queue = [];
    if (queueJson != null) {
      try {
        final List<dynamic> parsed = jsonDecode(queueJson);
        queue = parsed.map((j) => SongModel.fromJson(j)).toList();
      } catch (e) {
        AppLogger.error('Failed to parse queue snapshot: $e');
      }
    }

    // Get current song from library
    final song = await _getSongById(currentSongId);
    if (song == null) {
      await clearSession();
      return null;
    }

    // Filter unavailable songs from queue
    final availableQueue = queue.where((s) => s.isAvailable).toList();

    return ContinueSession(
      sessionId: sessionId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      currentSong: song,
      currentPosition: Duration(milliseconds: currentPosition),
      queueSnapshot: availableQueue,
      currentIndex: currentIndex ?? 0,
      lastPlayedAt: timestamp ?? DateTime.now(),
      sourceRail: sourceRail ?? 'Unknown',
    );
  }

  /// Restore session to player.
  Future<void> restoreSession(ContinueSession session) async {
    AppLogger.session('Restoring session: ${session.sessionId}');

    // Validate position
    final songDuration = session.currentSong.duration;
    if (songDuration != null && session.currentPosition > songDuration) {
      session = session.copyWith(currentPosition: Duration.zero);
    }

    // TODO: Wire to player service
    // playerService.loadQueue(session.queueSnapshot, startIndex: session.currentIndex);
    // playerService.seek(session.currentPosition);
    // playerService.play();
  }

  /// Clear all resume data.
  Future<void> clearSession() async {
    await _settings.remove('resume_sessionId');
    await _settings.remove('resume_currentSongId');
    await _settings.remove('resume_currentPositionMs');
    await _settings.remove('resume_queueSnapshot');
    await _settings.remove('resume_currentIndex');
    await _settings.remove('resume_sourceRail');
    await _settings.remove('resume_timestamp');

    AppLogger.session('Session cleared');
  }

  Future<SongModel?> _getSongById(String id) async {
    // Delegate to library repository
    try {
      // return await libraryRepository.getSongById(id);
      return null; // Placeholder
    } catch (e) {
      return null;
    }
  }
}