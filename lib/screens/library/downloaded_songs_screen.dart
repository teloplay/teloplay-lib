import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../core/playback/playback_engine.dart';
import '../../models/history_entry_model.dart';
import '../../providers/cache_service_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';

/// Library-র "Downloaded Songs" (Phase 3 — Smart Cache) full screen —
/// cachedLocally=true সব track, cache size অনুযায়ী descending।
class DownloadedSongsScreen extends ConsumerStatefulWidget {
  const DownloadedSongsScreen({super.key});

  @override
  ConsumerState<DownloadedSongsScreen> createState =>
      _DownloadedSongsScreenState();
}

class _DownloadedSongsScreenState
    extends ConsumerState<DownloadedSongsScreen> {
  final Set<String> _removedIds = {};

  Future<void> _play(List<CachedSongEntry> entries, int index) async {
    final tracks = entries
        .map((e) => SearchResult(
              videoId: e.songId,
              title: e.title,
              author: e.author,
              thumbnail: e.thumbnail,
            ))
        .toList();

    await ref.read(musicPlayerRepositoryProvider).playFromContext(
          tracks: tracks,
          startIndex: index,
          source: QueueSource.downloaded,
        );
  }

  Future<void> _delete(CachedSongEntry entry) async {
    setState(() {
      _removedIds.add(entry.songId);
    });

    final cacheService = ref.read(cacheServiceProvider);
    final evicted = await cacheService.evictTrack(entry.songId);

    if (!evicted) {
      if (mounted) {
        setState(() {
          _removedIds.remove(entry.songId);
        });
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Currently playing — can\'t remove download right now',
            ),
          ),
        );
      }
      return;
    }

    ref.invalidate(cachedSongsProvider);
  }

  void _confirmDelete(BuildContext context, CachedSongEntry entry) {
    final theme = context.aurora;
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        title: Text(
          'Remove download?',
          style: TextStyle(color: theme.textPrimary, fontSize: 16),
        ),
        content: Text(
          '${entry.title} (${entry.formattedSize}) will be removed from '
          'local storage.',
          style: TextStyle(color: theme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _delete(entry);
            },
            child: Text('Remove', style: TextStyle(color: theme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;
    final cachedAsync = ref.watch(cachedSongsProvider);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        title: Text('Downloaded Songs',
            style: TextStyle(color: theme.textPrimary)),
        iconTheme: IconThemeData(color: theme.textPrimary),
      ),
      body: cachedAsync.when(
        data: (allEntries) {
          final entries = allEntries
              .where((e) => !_removedIds.contains(e.songId))
              .toList();

          if (entries.isEmpty) {
            return Center(
              child: Text(
                'No downloaded songs yet',
                style: TextStyle(color: theme.textDisabled),
              ),
            );
          }

          final totalBytes =
              entries.fold<int>(0, (sum, e) => sum + e.cacheSizeBytes);
          final totalMb = totalBytes / (1024 * 1024);

          return Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                    horizontal: 16, vertical: 8),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    '${entries.length} songs · ${totalMb.toStringAsFixed(1)} MB',
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (context, index) {
                    final entry = entries[index];
                    return ListTile(
                      onTap: () => _play(entries, index),
                      leading: CachedArtwork(
                        imageUrl: entry.thumbnail,
                        width: 48,
                        height: 48,
                        borderRadius: BorderRadius.circular(4),
                        memCacheWidth: 96,
                        memCacheHeight: 96,
                        placeholderIcon: Icons.music_note,
                      ),
                      title: Text(
                        entry.title,
                        style: TextStyle(color: theme.textPrimary, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${entry.author} · ${entry.formattedSize}',
                        style: TextStyle(color: theme.textSecondary, fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: Icon(Icons.delete_outline,
                            color: theme.textSecondary, size: 20),
                        tooltip: 'Remove download',
                        onPressed: () => _confirmDelete(context, entry),
                      ),
                    );
                  },
                ),
              ),
            ],
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: theme.primary),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load downloaded songs',
            style: TextStyle(color: theme.textDisabled),
          ),
        ),
      ),
    );
  }
}