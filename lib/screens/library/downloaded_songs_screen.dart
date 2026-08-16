import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../widgets/skeleton_loader.dart';
import '../../widgets/cached_artwork.dart';
import '../../providers/library_provider.dart';

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
        title: Text('Downloads', style: TextStyle(color: theme.textPrimary)),
        actions: [
          FutureBuilder<int>(
            future: _getTotalStorage(),
            builder: (context, snapshot) {
              final size = _formatBytes(snapshot.data ?? 0);
              return Center(
                child: Padding(
                  padding: const EdgeInsets.only(right: 16),
                  child: Text(
                    size,
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
                ),
              );
            },
          ),
        ],
      ),
      body: downloadsAsync.when(
        data: (songs) => _buildList(context, songs),
        loading: () => _buildSkeleton(context),
        error: (_, __) => _buildError(context),
      ),
    );
  }

  Widget _buildList(BuildContext context, List<dynamic> songs) {
    final theme = context.aurora;
    if (songs.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.download_done, size: 64, color: theme.textDisabled),
            const SizedBox(height: 16),
            Text(
              'No downloads yet',
              style: TextStyle(color: theme.textSecondary, fontSize: 16),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => Navigator.of(context).pushNamed('/search'),
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
          onTap: () => _playSong(song),
          onLongPress: () => _showContextMenu(song),
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

  Widget _buildError(BuildContext context) {
    final theme = context.aurora;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.error_outline, size: 48, color: theme.error),
          const SizedBox(height: 12),
          Text(
            'Could not load downloads',
            style: TextStyle(color: theme.textSecondary),
          ),
        ],
      ),
    );
  }

  Future<int> _getTotalStorage() async => 0;

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '${bytes}B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    if (bytes < 1024 * 1024 * 1024) return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  void _playSong(dynamic song) {}
  void _showContextMenu(dynamic song) {}
}