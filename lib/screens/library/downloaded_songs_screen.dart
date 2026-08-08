import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../models/history_entry_model.dart';
import '../../providers/cache_service_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';

/// Library-র "Downloaded Songs" (Phase 3 — Smart Cache) full screen —
/// cachedLocally=true সব track, cache size অনুযায়ী descending।
///
/// ⚠️ HistoryScreen-এর optimistic-removal প্যাটার্ন অনুসরণ করা হয়েছে
/// (ConsumerStatefulWidget + local `_removedIds` Set) — কারণ delete
/// এখানে filesystem I/O সহ (CacheService.evictTrack()), DB-only delete
/// (deleteHistoryEntry()) থেকে ধীর হতে পারে। optimistic removal ছাড়া
/// delete button চাপার পর UI কিছুক্ষণ পুরনো state দেখাত।
///
/// ⚠️ evictTrack() `false` রিটার্ন করলে (currently-playing guard hit) —
/// optimistic removal revert করা হয় (row ফিরিয়ে আনা), কারণ delete
/// আসলে হয়নি, UI থেকে চিরতরে সরিয়ে দেওয়া ভুল হতো। SnackBar দিয়ে কারণ
/// জানানো হয়।
class DownloadedSongsScreen extends ConsumerStatefulWidget {
  const DownloadedSongsScreen({super.key});

  @override
  ConsumerState<DownloadedSongsScreen> createState() =>
      _DownloadedSongsScreenState();
}

class _DownloadedSongsScreenState
    extends ConsumerState<DownloadedSongsScreen> {
  final Set<String> _removedIds = {};

  // ⚠️ Context-based Queue (Phase 1 fix) — এখন পুরো visible list (already
  // _removedIds filtered) queue হিসেবে সেট হয়, tap করা entry থেকে শুরু
  // করে। entries/index দুটোই caller (itemBuilder)-এ already আছে, তাই
  // আলাদা lookup লাগছে না।
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
    // সাথে সাথে optimistic removal — filesystem delete শেষ হওয়ার
    // অপেক্ষা না করে UI থেকে বাদ।
    setState(() {
      _removedIds.add(entry.songId);
    });

    final cacheService = ref.read(cacheServiceProvider);
    final evicted = await cacheService.evictTrack(entry.songId);

    if (!evicted) {
      // currently-playing guard hit — revert।
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
    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Remove download?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: Text(
          '${entry.title} (${entry.formattedSize}) will be removed from '
          'local storage.',
          style: const TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () {
              Navigator.pop(dialogContext);
              _delete(entry);
            },
            child:
                const Text('Remove', style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cachedAsync = ref.watch(cachedSongsProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('Downloaded Songs',
            style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
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
                style: TextStyle(color: Colors.grey[600]),
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
                    style: TextStyle(color: Colors.grey[500], fontSize: 12),
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
                        style:
                            const TextStyle(color: Colors.white, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        '${entry.author} · ${entry.formattedSize}',
                        style: TextStyle(color: Colors.grey[500], fontSize: 12),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline,
                            color: Colors.grey, size: 20),
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
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load downloaded songs',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      ),
    );
  }
}