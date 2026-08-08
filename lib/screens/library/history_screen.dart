import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../models/history_entry_model.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';

/// পূর্ণ, raw play-History — নতুন থেকে পুরনো ক্রমে, প্রতিটা play event
/// আলাদা row (একই গান একাধিকবার শোনা হলে একাধিক entry)।
///
/// ⚠️ Recently Played (distinct, track-level) থেকে ইচ্ছাকৃতভাবে আলাদা
/// screen — দেখো history_entry_model.dart-এর top-level নোট।
///
/// ⚠️ Bug fix ১ — "A dismissed Dismissible widget is still part of the
/// tree"। ConsumerStatefulWidget + local `_removedIds` Set দিয়ে
/// optimistic-removal (দেখো নিচে build()/onDismissed())।
///
/// ⚠️ Bug fix ২ — ট্যাপ করলে play হতো না (ListTile-এ onTap মিসিং ছিল)।
/// এখন onTap যোগ করা হয়েছে, MusicPlayerRepository.playVideoId() কল
/// করে (FavoritesScreen-এর play-button-এর মতোই SearchResult বানিয়ে)।
///
/// ⚠️ সব UI-facing string ইংরেজিতে করা হলো (roadmap নীতি: "ব্যাখ্যা
/// বাংলায়, কোড/কমেন্ট/ডকুমেন্টেশন ইংরেজিতে" — এটা code comment-এর
/// কথা বলে, কিন্তু UI string-ও ভুলবশত বাংলায় লেখা হয়েছিল, এখন সংশোধন)।
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
  // অপ্টিমিস্টিকভাবে সরিয়ে ফেলা HistoryEntries.id-গুলো — DB delete
  // ব্যাকগ্রাউন্ডে চলাকালীন UI থেকে সাথে সাথে বাদ দেওয়ার জন্য।
  final Set<String> _removedIds = {};

  String _formatPlayedAt(DateTime playedAt) {
    final now = DateTime.now();
    final diff = now.difference(playedAt);

    if (diff.inMinutes < 1) return 'Just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return '${playedAt.day}/${playedAt.month}/${playedAt.year}';
  }

  IconData _outcomeIcon(HistoryLogEntry entry) {
    if (entry.completed) return Icons.check_circle_outline;
    if (entry.skipped) return Icons.skip_next_outlined;
    return Icons.error_outline;
  }

  Color _outcomeColor(HistoryLogEntry entry) {
    if (entry.completed) return Colors.greenAccent;
    if (entry.skipped) return Colors.orangeAccent;
    return Colors.grey;
  }

  Future<void> _play(HistoryLogEntry entry) async {
    await ref.read(musicPlayerRepositoryProvider).playVideoId(
          entry.songId,
          trackInfo: SearchResult(
            videoId: entry.songId,
            title: entry.title,
            author: entry.author,
            thumbnail: entry.thumbnail,
          ),
        );
  }

  void _confirmClearAll(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text(
          'Clear all History?',
          style: TextStyle(color: Colors.white, fontSize: 16),
        ),
        content: const Text(
          'This action cannot be undone.',
          style: TextStyle(color: Colors.grey),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel', style: TextStyle(color: Colors.grey)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(libraryRepositoryProvider).clearHistory();
              ref.invalidate(historyProvider);
            },
            child: const Text('Clear all',
                style: TextStyle(color: Colors.redAccent)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('History', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined, color: Colors.grey),
            tooltip: 'Clear all',
            onPressed: () => _confirmClearAll(context, ref),
          ),
        ],
      ),
      body: historyAsync.when(
        data: (allEntries) {
          // অপ্টিমিস্টিকভাবে সরানো entry-গুলো এখানেই filter করে বাদ
          // দেওয়া হচ্ছে — provider এখনো পুরনো data থাকলেও UI-তে সাথে
          // সাথে বাদ পড়ে যাবে।
          final entries =
              allEntries.where((e) => !_removedIds.contains(e.id)).toList();

          if (entries.isEmpty) {
            return Center(
              child: Text(
                'No History yet',
                style: TextStyle(color: Colors.grey[600]),
              ),
            );
          }

          return ListView.builder(
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final entry = entries[index];
              return Dismissible(
                key: ValueKey(entry.id),
                direction: DismissDirection.endToStart,
                background: Container(
                  color: Colors.red.shade900,
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: const Icon(Icons.delete, color: Colors.white),
                ),
                onDismissed: (_) {
                  // সাথে সাথে (synchronously) local state আপডেট —
                  // Dismissible widget-টা পরের rebuild-এই tree থেকে
                  // বাদ পড়ে যাবে, DB delete-এর অপেক্ষা করতে হয় না।
                  setState(() {
                    _removedIds.add(entry.id);
                  });

                  // ব্যাকগ্রাউন্ডে আসল delete + provider refresh —
                  // fire-and-forget, UI-কে block করে না।
                  ref
                      .read(libraryRepositoryProvider)
                      .deleteHistoryEntry(entry.id)
                      .then((_) {
                    ref.invalidate(historyProvider);
                  });
                },
                child: ListTile(
                  onTap: () => _play(entry),
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
                    style: const TextStyle(color: Colors.white, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Row(
                    children: [
                      Icon(_outcomeIcon(entry),
                          size: 12, color: _outcomeColor(entry)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${entry.author} · ${_formatPlayedAt(entry.playedAt)}',
                          style: TextStyle(color: Colors.grey[500], fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: const Icon(Icons.play_arrow,
                        color: Colors.greenAccent, size: 20),
                    onPressed: () => _play(entry),
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
            'Failed to load History',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      ),
    );
  }
}