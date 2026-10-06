import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../core/playback/playback_engine.dart';
import '../../models/playlist_model.dart';
import '../../providers/music_player_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../widgets/cached_artwork.dart';

/// একটা নির্দিষ্ট playlist-এর ভেতরের গানের list — drag & drop দিয়ে
/// reorder করা যায়, প্রতিটা item swipe/button দিয়ে remove করা যায়,
/// title ট্যাপ করলে playlist rename করা যায়।
class PlaylistDetailScreen extends ConsumerWidget {
  final String playlistId;

  const PlaylistDetailScreen({super.key, required this.playlistId});

  Future<void> _showRenameDialog(
    BuildContext context,
    WidgetRef ref,
    String currentName,
  ) async {
    final theme = context.aurora;
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: theme.surface,
        title: Text('Rename Playlist', style: TextStyle(color: theme.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: theme.textPrimary),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: Text('Save', style: TextStyle(color: theme.primary)),
          ),
        ],
      ),
    );

    if (newName == null || newName.trim().isEmpty) return;
    if (newName.trim() == currentName) return;

    await ref.read(playlistRepositoryProvider).renamePlaylist(
          playlistId: playlistId,
          newName: newName.trim(),
        );
  }

  /// D1 — shared items→tracks mapping (row tap and Play All use the
  /// same list; no duplicated conversion, no second queue).
  static List<SearchResult> _tracksOf(List<PlaylistItemEntry> items) {
    return items
        .map((i) => SearchResult(
              videoId: i.songId,
              title: i.title,
              author: i.author,
              thumbnail: i.thumbnail,
            ))
        .toList();
  }

  /// D1 — Play All establishes the playlist as the playback context via
  /// the canonical path. playFromContext REPLACES the queue, so repeat
  /// taps cannot duplicate contexts; empty lists never reach here (no
  /// header renders for them).
  void _playAll(WidgetRef ref, List<PlaylistItemEntry> items) {
    ref.read(musicPlayerRepositoryProvider).playFromContext(
          tracks: _tracksOf(items),
          startIndex: 0,
          source: QueueSource.playlist,
        );
  }

  void _onReorder(
    WidgetRef ref,
    List<PlaylistItemEntry> items,
    int oldIndex,
    int newIndex,
  ) {
    if (newIndex > oldIndex) newIndex -= 1;

    final reordered = List<PlaylistItemEntry>.from(items);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final orderedItemIds = reordered.map((e) => e.itemId).toList();

    ref.read(playlistRepositoryProvider).reorderItems(
          playlistId: playlistId,
          orderedItemIds: orderedItemIds,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.aurora;
    final detailAsync = ref.watch(playlistDetailProvider(playlistId));

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        iconTheme: IconThemeData(color: theme.textPrimary),
        title: detailAsync.maybeWhen(
          data: (detail) => GestureDetector(
            onTap: detail != null
                ? () => _showRenameDialog(context, ref, detail.name)
                : null,
            child: Text(
              detail?.name ?? 'Playlist',
              style: TextStyle(color: theme.textPrimary),
            ),
          ),
          orElse: () => Text('Playlist', style: TextStyle(color: theme.textPrimary)),
        ),
        // D1 — Play All (non-empty only; empty playlists render no
        // header, so no playback attempt is possible).
        actions: detailAsync.maybeWhen(
          data: (detail) => detail == null || detail.items.isEmpty
              ? null
              : [
                  IconButton(
                    icon: const Icon(Icons.play_circle_fill_rounded),
                    tooltip: 'Play All',
                    onPressed: () => _playAll(ref, detail.items),
                  ),
                ],
          orElse: () => null,
        ),
      ),
      body: detailAsync.when(
        data: (detail) {
          if (detail == null) {
            return Center(
              child: Text(
                'This playlist no longer exists',
                style: TextStyle(color: theme.textSecondary),
              ),
            );
          }

          if (detail.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.music_off, color: theme.textDisabled, size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'No songs yet',
                    style: TextStyle(color: theme.textSecondary, fontSize: 14),
                  ),
                ],
              ),
            );
          }

          return ReorderableListView.builder(
            itemCount: detail.items.length,
            onReorder: (oldIndex, newIndex) =>
                _onReorder(ref, detail.items, oldIndex, newIndex),
            itemBuilder: (context, index) {
              final item = detail.items[index];
              return Dismissible(
                key: ValueKey(item.itemId),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: theme.error,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: Icon(Icons.delete, color: theme.background),
                ),
                onDismissed: (_) {
                  ref.read(playlistRepositoryProvider).removeItem(
                        playlistId: playlistId,
                        itemId: item.itemId,
                      );
                },
                child: ListTile(
                  // P1-M — desktop hover affordance.
                  hoverColor: theme.surfaceElevated,
                  key: ValueKey('tile_${item.itemId}'),
                  leading: CachedArtwork(
                    imageUrl: item.thumbnail,
                    width: 48,
                    height: 48,
                    borderRadius: BorderRadius.circular(6),
                    memCacheWidth: 96,
                    memCacheHeight: 96,
                    placeholderIcon: Icons.music_note,
                  ),
                  title: Text(
                    item.title,
                    style: TextStyle(color: theme.textPrimary),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.author,
                    style: TextStyle(color: theme.textSecondary, fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    ref.read(musicPlayerRepositoryProvider).playFromContext(
                          tracks: _tracksOf(detail.items),
                          startIndex: index,
                          source: QueueSource.playlist,
                        );
                  },
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: Icon(Icons.drag_handle, color: theme.textSecondary),
                  ),
                ),
              );
            },
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: theme.primary),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load playlist',
            style: TextStyle(color: theme.textSecondary),
          ),
        ),
      ),
    );
  }
}