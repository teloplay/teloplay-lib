import 'package:supabase_flutter/supabase_flutter.dart';
import '../../core/logging/app_logger.dart';

/// Phase 4 — Low-level Repository for Supabase cloud sync operations.
class SyncRepository {
  final SupabaseClient _client;

  SyncRepository([SupabaseClient? client])
      : _client = client ?? Supabase.instance.client;

  String? get currentUserId => _client.auth.currentUser?.id;

  // ═══════════════════════════════════════════════════════════════
  // Favorites Sync
  // ═══════════════════════════════════════════════════════════════

  Future<void> upsertFavorite({
    required String songId,
    required String title,
    required String author,
    required String thumbnail,
    int? durationSeconds,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _client.from('user_favorites').upsert(
      {
        'user_id': uid,
        'song_id': songId,
        'title': title,
        'author': author,
        'thumbnail': thumbnail,
        'duration_seconds': durationSeconds,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,song_id',
    );
    AppLogger.sync('Favorite synced to Supabase: $songId');
  }

  Future<void> deleteFavorite(String songId) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _client
        .from('user_favorites')
        .delete()
        .eq('user_id', uid)
        .eq('song_id', songId);
    AppLogger.sync('Favorite removed from Supabase: $songId');
  }

  // ═══════════════════════════════════════════════════════════════
  // Queue State Sync (with lastPositionMs)
  // ═══════════════════════════════════════════════════════════════

  Future<void> syncQueueState({
    required List<Map<String, dynamic>> queueJson,
    required int currentIndex,
    required int lastPositionMs,
    String? currentSongId,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _client.from('user_queue_state').upsert(
      {
        'user_id': uid,
        'queue_json': queueJson,
        'current_index': currentIndex,
        'last_position_ms': lastPositionMs,
        'current_song_id': currentSongId,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id',
    );
    AppLogger.sync('Queue state synced to Supabase (pos=${lastPositionMs}ms)');
  }

  // ═══════════════════════════════════════════════════════════════
  // Settings Sync
  // ═══════════════════════════════════════════════════════════════

  Future<void> syncSettings(Map<String, dynamic> settingsMap) async {
    final uid = currentUserId;
    if (uid == null) return;

    await _client.from('user_settings').upsert(
      {
        'user_id': uid,
        'settings_json': settingsMap,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id',
    );
    AppLogger.sync('Settings synced to Supabase');
  }

  // ═══════════════════════════════════════════════════════════════
  // Behaviour Summary Sync (Tiered Sync Policy)
  // ═══════════════════════════════════════════════════════════════

  Future<void> syncBehaviourSummary({
    required List<Map<String, dynamic>> topArtists,
    required int totalPlays,
    required int totalSkips,
    required int totalCompleted,
    required int totalListenMs,
  }) async {
    final uid = currentUserId;
    if (uid == null) return;

    final today = DateTime.now().toIso8601String().split('T').first;

    await _client.from('behaviour_summaries').upsert(
      {
        'user_id': uid,
        'summary_date': today,
        'top_artists': topArtists,
        'total_plays': totalPlays,
        'total_skips': totalSkips,
        'total_completed': totalCompleted,
        'total_listen_ms': totalListenMs,
        'updated_at': DateTime.now().toIso8601String(),
      },
      onConflict: 'user_id,summary_date',
    );
    AppLogger.sync('Daily behaviour summary synced to Supabase');
  }
}
