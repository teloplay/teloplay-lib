import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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
    final controller = TextEditingController(text: currentName);

    final newName = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('Rename Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Save', style: TextStyle(color: Colors.greenAccent)),
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

  void _onReorder(
    WidgetRef ref,
    List<PlaylistItemEntry> items,
    int oldIndex,
    int newIndex,
  ) {
    // ⚠️ ReorderableListView-এর নিজস্ব quirk — item নিচের দিকে সরালে
    // newIndex ১ বেশি আসে (Flutter-এর documented আচরণ), তাই adjust
    // করা হচ্ছে।
    if (newIndex > oldIndex) newIndex -= 1;

    final reordered = List<PlaylistItemEntry>.from(items);
    final moved = reordered.removeAt(oldIndex);
    reordered.insert(newIndex, moved);

    final orderedItemIds = reordered.map((e) => e.itemId).toList();

    // Optimistic-এর দরকার নেই — playlistDetailProvider Stream-based,
    // reorderItems() persist হওয়া মাত্র UI নিজে থেকেই নতুন ক্রম দেখাবে।
    // fire-and-forget: reorder UI-blocking হওয়া উচিত না।
    ref.read(playlistRepositoryProvider).reorderItems(
          playlistId: playlistId,
          orderedItemIds: orderedItemIds,
        );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final detailAsync = ref.watch(playlistDetailProvider(playlistId));

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        iconTheme: const IconThemeData(color: Colors.white),
        title: detailAsync.maybeWhen(
          data: (detail) => GestureDetector(
            onTap: detail != null
                ? () => _showRenameDialog(context, ref, detail.name)
                : null,
            child: Text(
              detail?.name ?? 'Playlist',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          orElse: () => const Text('Playlist', style: TextStyle(color: Colors.white)),
        ),
      ),
      body: detailAsync.when(
        data: (detail) {
          if (detail == null) {
            // Playlist delete হয়ে গেছে (অন্য কোনো জায়গা থেকে) এই
            // screen খোলা অবস্থাতেই — graceful fallback।
            return Center(
              child: Text(
                'এই playlist আর নেই',
                style: TextStyle(color: Colors.grey[500]),
              ),
            );
          }

          if (detail.items.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.music_off, color: Colors.grey[600], size: 48),
                  const SizedBox(height: 12),
                  Text(
                    'এখনো কোনো গান নেই',
                    style: TextStyle(color: Colors.grey[500], fontSize: 14),
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
                  color: Colors.redAccent,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                  ref.read(playlistRepositoryProvider).removeItem(
                        playlistId: playlistId,
                        itemId: item.itemId,
                      );
                },
                child: ListTile(
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
                    style: const TextStyle(color: Colors.white),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    item.author,
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  onTap: () {
                    // ⚠️ Context-based Queue (Phase 1 fix) — পুরো
                    // playlist queue হিসেবে সেট হচ্ছে (এখনকার scale-এ
                    // পুরো list-ই যথেষ্ট, windowing পরে দরকার হলে যোগ
                    // হবে), tap করা track থেকে শুরু করে।
                    final tracks = detail.items
                        .map((i) => SearchResult(
                              videoId: i.songId,
                              title: i.title,
                              author: i.author,
                              thumbnail: i.thumbnail,
                            ))
                        .toList();

                    ref.read(musicPlayerRepositoryProvider).playFromContext(
                          tracks: tracks,
                          startIndex: index,
                          source: QueueSource.playlist,
                        );
                  },
                  trailing: ReorderableDragStartListener(
                    index: index,
                    child: const Icon(Icons.drag_handle, color: Colors.grey),
                  ),
                ),
              );
            },
          );
        },
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
        error: (e, _) => Center(
          child: Text(
            'Playlist load করা যায়নি',
            style: TextStyle(color: Colors.grey[500]),
          ),
        ),
      ),
    );
  }
}