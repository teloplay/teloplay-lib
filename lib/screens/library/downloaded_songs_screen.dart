import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../core/playback/playback_engine.dart';
import '../../providers/cache_service_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../screens/profile/profile_providers.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/cached_artwork.dart';
import '../../widgets/context_menu.dart' show ContextMenuType;
import '../../widgets/inline_load_error.dart';
import '../../widgets/track_menu.dart';

/// Downloaded songs screen with theme-migrated colors.
class DownloadedSongsScreen extends ConsumerWidget {
  const DownloadedSongsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.aurora;
    final downloadsAsync = ref.watch(cachedSongsProvider);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.textPrimary),
          onPressed: () => Navigator.of(context).pop(),
        ),
        // D2 — honest cache terminology: this screen lists songs
        // available offline via the cache layer, NOT permanent/owned
        // downloads (per Experience Spec §10 [DECIDED]).
        title: Text('Available offline (cache)',
            style: TextStyle(color: theme.textPrimary)),
        // A4 — real storage total from the canonical profile storage
        // provider (sums CacheRepository sizes; honest cache semantics,
        // never hardcoded). Loading shows nothing yet; error shows
        // nothing rather than a wrong number.
        actions: [
          Consumer(
            builder: (context, ref, _) {
              final infoAsync = ref.watch(profileStorageInfoProvider);
              return infoAsync.when(
                data: (info) => Center(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 16),
                    child: Text(
                      _formatBytes(info.totalCacheSizeBytes),
                      style: TextStyle(
                          color: theme.textSecondary, fontSize: 12),
                    ),
                  ),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              );
            },
          ),
        ],
      ),
      body: downloadsAsync.when(
        data: (songs) => _buildList(context, ref, songs),
        loading: () => _buildSkeleton(context),
        error: (_, __) => _buildError(context, ref),
      ),
    );
  }

  Widget _buildList(BuildContext context, WidgetRef ref, List<dynamic> songs) {
    final theme = context.aurora;
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 64, color: theme.textDisabled),
            const SizedBox(height: 16),
            Text(
              // D2 — cache wording, no permanent-download promise.
              'Nothing available offline yet',
              style: TextStyle(color: theme.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => context.go('/home?tab=search'),
              style: ElevatedButton.styleFrom(
                backgroundColor: theme.primary,
                foregroundColor: Colors.white,
              ),
              child: const Text('Browse songs'),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: songs.length,
      itemBuilder: (context, index) {
        final song = songs[index];
        return ListTile(
          // P1-M — desktop hover affordance.
          hoverColor: theme.surfaceElevated,
          leading: ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: CachedArtwork(
              imageUrl: song.thumbnail,
              width: 56,
              height: 56,
              borderRadius: BorderRadius.circular(6),
              placeholderIcon: Icons.music_note,
            ),
          ),
          title: Text(
            song.title,
            style: TextStyle(color: theme.textPrimary, fontSize: 16),
          ),
          subtitle: Text(
            // FIX: CachedSongEntry has no 'artist' field.
            // Try 'author', 'channelName', or fallback to empty.
            _getArtistName(song),
            style: TextStyle(color: theme.textSecondary, fontSize: 14),
          ),
          // ⚠️ Bug fix — CachedSongEntry has no 'quality' or 'fileSize'
          // getters (model only exposes songId/title/author/thumbnail/
          // cacheSizeBytes — see models/history_entry_model.dart). The
          // previous code called song.quality and song.fileSize, which
          // don't exist on this class, so building this ListTile threw
          // NoSuchMethodError every time the Downloads screen opened.
          // There's no bitrate/quality data in this model at all (the
          // cache layer doesn't track that), so the quality chip is
          // dropped rather than showing a fake hardcoded '320kbps'.
          // Size now comes from the real cacheSizeBytes field via the
          // model's own formattedSize getter, which already exists for
          // exactly this purpose.
          trailing: Text(
            song.formattedSize,
            style: TextStyle(color: theme.textSecondary, fontSize: 12),
          ),
          onTap: () => _playSong(context, ref, song),
          onLongPress: () => _showContextMenu(context, ref, song),
        );
      },
    );
  }

  /// Safely extract artist name from CachedSongEntry.
  /// Tries common field names, falls back to empty.
  String _getArtistName(dynamic song) {
    // Try common field names in order of preference
    if (song.author != null && song.author.toString().isNotEmpty) {
      return song.author;
    }
    if (song.channelName != null && song.channelName.toString().isNotEmpty) {
      return song.channelName;
    }
    if (song.artist != null && song.artist.toString().isNotEmpty) {
      return song.artist;
    }
    if (song.uploader != null && song.uploader.toString().isNotEmpty) {
      return song.uploader;
    }
    return 'Unknown Artist';
  }

  Widget _buildSkeleton(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: 8,
      itemBuilder: (_, __) => const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: SkeletonLoader(
          width: double.infinity,
          height: 56,
        ),
      ),
    );
  }

  Widget _buildError(BuildContext context, WidgetRef ref) {
    // D6 — curated message + Retry re-running the actual provider
    // (local cache query; retry is meaningful). No raw exceptions.
    return Center(
      child: InlineLoadError(
        message: "Couldn't load offline songs",
        onRetry: () => ref.invalidate(cachedSongsProvider),
      ),
    );
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _playSong(BuildContext context, WidgetRef ref, dynamic song) {
    // P1-L — adjacent dead tap in the same rows: play via the normal path
    // (cache-hit resolves to the local file, verified flow).
    ref.read(musicPlayerRepositoryProvider).playVideoId(
          song.songId as String,
          trackInfo: SearchResult(
            videoId: song.songId as String,
            title: (song.title ?? '').toString(),
            author: _getArtistName(song),
            thumbnail: (song.thumbnail ?? '').toString(),
          ),
        );
  }

  void _showContextMenu(BuildContext context, WidgetRef ref, dynamic song) {
    // P1-L — previously an empty stub: long-press did nothing.
    final track = SearchResult(
      videoId: song.songId as String,
      title: (song.title ?? '').toString(),
      author: _getArtistName(song),
      thumbnail: (song.thumbnail ?? '').toString(),
    );
    showTrackMenu(
      context: context,
      ref: ref,
      track: track,
      type: ContextMenuType.downloaded,
      onDeleteDownload: () async {
        await ref.read(cacheServiceProvider).evictTrack(track.videoId);
        ref.invalidate(cachedSongsProvider);
      },
    );
  }
}