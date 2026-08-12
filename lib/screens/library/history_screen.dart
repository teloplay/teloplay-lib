import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../core/playback/playback_engine.dart';
import '../../models/history_entry_model.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';

/// পূর্ণ, raw play-History — নতুন থেকে পুরনো ক্রমে, প্রতিটা play event
/// আলাদা row (একই গান একাধিকবার শোনা হলে একাধিক entry)।
class HistoryScreen extends ConsumerStatefulWidget {
  const HistoryScreen({super.key});

  @override
  ConsumerState<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends ConsumerState<HistoryScreen> {
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

  Color _outcomeColor(HistoryLogEntry entry, AuroraColors theme) {
    if (entry.completed) return theme.success;
    if (entry.skipped) return theme.secondary;
    return theme.textDisabled;
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
    final theme = context.aurora;
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: theme.surface,
        title: Text(
          'Clear all History?',
          style: TextStyle(color: theme.textPrimary, fontSize: 16),
        ),
        content: Text(
          'This action cannot be undone.',
          style: TextStyle(color: theme.textSecondary),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text('Cancel', style: TextStyle(color: theme.textSecondary)),
          ),
          TextButton(
            onPressed: () async {
              Navigator.pop(context);
              await ref.read(libraryRepositoryProvider).clearHistory();
              ref.invalidate(historyProvider);
            },
            child: Text('Clear all', style: TextStyle(color: theme.error)),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;
    final historyAsync = ref.watch(historyProvider);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        title: Text('History', style: TextStyle(color: theme.textPrimary)),
        iconTheme: IconThemeData(color: theme.textPrimary),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_sweep_outlined, color: theme.textSecondary),
            tooltip: 'Clear all',
            onPressed: () => _confirmClearAll(context, ref),
          ),
        ],
      ),
      body: historyAsync.when(
        data: (allEntries) {
          final entries =
              allEntries.where((e) => !_removedIds.contains(e.id)).toList();

          if (entries.isEmpty) {
            return Center(
              child: Text(
                'No History yet',
                style: TextStyle(color: theme.textDisabled),
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
                  color: theme.error.withOpacity(0.8),
                  alignment: Alignment.centerRight,
                  padding: const EdgeInsets.only(right: 20),
                  child: Icon(Icons.delete, color: theme.background),
                ),
                onDismissed: (_) {
                  setState(() {
                    _removedIds.add(entry.id);
                  });

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
                    style: TextStyle(color: theme.textPrimary, fontSize: 14),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Row(
                    children: [
                      Icon(_outcomeIcon(entry),
                          size: 12, color: _outcomeColor(entry, theme)),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          '${entry.author} · ${_formatPlayedAt(entry.playedAt)}',
                          style: TextStyle(color: theme.textSecondary, fontSize: 12),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                  trailing: IconButton(
                    icon: Icon(Icons.play_arrow,
                        color: theme.primary, size: 20),
                    onPressed: () => _play(entry),
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
            'Failed to load History',
            style: TextStyle(color: theme.textDisabled),
          ),
        ),
      ),
    );
  }
}