import 'dart:convert';

import 'package:drift/drift.dart';

import '../../core/logging/app_logger.dart';
import '../../core/playback/playback_engine.dart';
import '../../data/drift/database.dart';
import '../../data/repositories/settings_repository.dart';
import '../../models/continue_session.dart';

/// Manages multi-song session persistence and restoration.
/// Saves: current song + position + full queue snapshot + source rail.
///
/// ⚠️ Fix (Phase 0 v11 stabilization) — rewritten against the actual
/// codebase surface:
/// - Song type is [SearchResult] (playback_engine.dart), not a
///   nonexistent `SongModel`.
/// - [SettingsRepository] only exposes String getValue/setValue/getValues
///   (no getInt/getDateTime/remove) — all values below are encoded as
///   String and parsed back explicitly.
/// - [ContinueSessions] is the real Drift table name (was referenced as
///   `db.continueSessions` before the table existed at all).
class ContinueSessionManager {
  final AppDatabase _db;
  final SettingsRepository _settings;

  static const _kSessionId = 'resume_sessionId';
  static const _kCurrentSongJson = 'resume_currentSongJson';
  static const _kCurrentPositionMs = 'resume_currentPositionMs';
  static const _kQueueSnapshot = 'resume_queueSnapshot';
  static const _kCurrentIndex = 'resume_currentIndex';
  static const _kSourceRail = 'resume_sourceRail';
  static const _kTimestamp = 'resume_timestamp';

  ContinueSessionManager({
    required AppDatabase db,
    required SettingsRepository settings,
  })  : _db = db,
        _settings = settings;

  /// Save current session state.
  Future<void> saveSession({
    required SearchResult currentSong,
    required Duration currentPosition,
    required List<SearchResult> queueSnapshot,
    required int currentIndex,
    required String sourceRail,
  }) async {
    final sessionId = DateTime.now().millisecondsSinceEpoch.toString();
    final queueJson = jsonEncode(queueSnapshot.map(searchResultToJson).toList());

    // Save to Drift (source of truth — full fidelity)
    try {
      await _db.into(_db.continueSessions).insertOnConflictUpdate(
            ContinueSessionsCompanion.insert(
              id: sessionId,
              currentSongId: currentSong.videoId,
              currentPositionMs: currentPosition.inMilliseconds,
              queueSnapshot: queueJson,
              currentIndex: currentIndex,
              sourceRail: sourceRail,
              lastPlayedAt: Value(DateTime.now()),
            ),
          );
    } catch (e) {
      AppLogger.error('ContinueSessionManager.saveSession (Drift) failed', e);
    }

    // Backup to Settings (String-only API — for faster cold-start read
    // before the Drift database connection is warmed up).
    await _settings.setValue(_kSessionId, sessionId);
    await _settings.setValue(_kCurrentSongJson, jsonEncode(searchResultToJson(currentSong)));
    await _settings.setValue(_kCurrentPositionMs, currentPosition.inMilliseconds.toString());
    await _settings.setValue(_kQueueSnapshot, queueJson);
    await _settings.setValue(_kCurrentIndex, currentIndex.toString());
    await _settings.setValue(_kSourceRail, sourceRail);
    await _settings.setValue(_kTimestamp, DateTime.now().toIso8601String());

    AppLogger.session('Session saved: $sessionId (${queueSnapshot.length} songs)');
  }

  /// Check and restore session on app launch. Settings backup is the
  /// fast/cold-start path — it carries everything needed, so Drift isn't
  /// queried on the hot launch path.
  Future<ContinueSession?> checkForResume() async {
    final sessionId = await _settings.getValue(_kSessionId);
    final songJson = await _settings.getValue(_kCurrentSongJson);
    final positionMsStr = await _settings.getValue(_kCurrentPositionMs);
    final queueJson = await _settings.getValue(_kQueueSnapshot);
    final indexStr = await _settings.getValue(_kCurrentIndex);
    final sourceRail = await _settings.getValue(_kSourceRail);
    final timestampStr = await _settings.getValue(_kTimestamp);

    if (songJson == null ||
        songJson.isEmpty ||
        positionMsStr == null ||
        positionMsStr.isEmpty) {
      return null;
    }

    final timestamp = timestampStr != null ? DateTime.tryParse(timestampStr) : null;

    // Discard if older than 7 days
    if (timestamp != null && DateTime.now().difference(timestamp).inDays > 7) {
      await clearSession();
      return null;
    }

    SearchResult currentSong;
    try {
      currentSong = searchResultFromJson(jsonDecode(songJson) as Map<String, dynamic>);
    } catch (e) {
      AppLogger.error('Failed to parse resume current song: $e');
      await clearSession();
      return null;
    }

    // Reconstruct queue
    List<SearchResult> queue = [];
    if (queueJson != null) {
      try {
        final List<dynamic> parsed = jsonDecode(queueJson);
        queue = parsed
            .map((j) => searchResultFromJson(j as Map<String, dynamic>))
            .toList();
      } catch (e) {
        AppLogger.error('Failed to parse queue snapshot: $e');
      }
    }

    return ContinueSession(
      sessionId: sessionId ?? DateTime.now().millisecondsSinceEpoch.toString(),
      currentSong: currentSong,
      currentPosition: Duration(milliseconds: int.tryParse(positionMsStr) ?? 0),
      queueSnapshot: queue,
      currentIndex: int.tryParse(indexStr ?? '') ?? 0,
      lastPlayedAt: timestamp ?? DateTime.now(),
      sourceRail: sourceRail ?? 'Unknown',
    );
  }

  /// Restore session to player.
  ///
  /// NOTE: actual player wiring (loadQueue/seek/play) is intentionally
  /// left as a TODO — this manager only owns persistence, not playback
  /// control. Wiring belongs wherever MusicPlayerRepository is available
  /// (see Phase 1 v11 "Continue Session Manager Integration").
  Future<ContinueSession> restoreSession(ContinueSession session) async {
    AppLogger.session('Restoring session: ${session.sessionId}');

    final songDuration = session.currentSong.duration;
    if (songDuration != null && session.currentPosition > songDuration) {
      return session.copyWith(currentPosition: Duration.zero);
    }
    return session;
  }

  /// Clear all resume data (both Settings backup and Drift row).
  Future<void> clearSession() async {
    // SettingsRepository has no remove() — empty string is the
    // established "cleared" sentinel for this String-only key/value store.
    await _settings.setValue(_kSessionId, '');
    await _settings.setValue(_kCurrentSongJson, '');
    await _settings.setValue(_kCurrentPositionMs, '');
    await _settings.setValue(_kQueueSnapshot, '');
    await _settings.setValue(_kCurrentIndex, '');
    await _settings.setValue(_kSourceRail, '');
    await _settings.setValue(_kTimestamp, '');

    try {
      await (_db.delete(_db.continueSessions)).go();
    } catch (e) {
      AppLogger.error('ContinueSessionManager.clearSession (Drift) failed', e);
    }

    AppLogger.session('Session cleared');
  }
}
