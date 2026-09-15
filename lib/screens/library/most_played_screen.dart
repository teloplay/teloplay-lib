import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../models/history_entry_model.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';
import '../../widgets/context_menu.dart';
import '../../widgets/sort/track_sort_bottom_sheet.dart';

/// Phase 3 — Most Played Screen
class MostPlayedScreen extends ConsumerStatefulWidget {
  const MostPlayedScreen({super.key});

  @override
  ConsumerState<MostPlayedScreen> createState() => _MostPlayedScreenState();
}

class _MostPlayedScreenState extends ConsumerState<MostPlayedScreen> {
  TrackSortOption _sortOption = TrackSortOption.customOrder;

  void _showSortSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (ctx) => TrackSortBottomSheet(
        currentSort: _sortOption,
        onSortChanged: (s) => setState(() => _sortOption = s),
      ),
    );
  }

  void _play(List<RecentlyPlayedEntry> list, int index) {
    final tracks = list
        .map((e) => SearchResult(
              videoId: e.songId,
              title: e.title,
              author: e.author,
              thumbnail: e.thumbnail,
            ))
        .toList();
    ref.read(musicPlayerRepositoryProvider).playFromContext(
          tracks: tracks,
          startIndex: index,
          source: QueueSource.unknown,
        );
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final mostPlayedAsync = ref.watch(mostPlayedProvider);

    return Scaffold(
      backgroundColor: aurora.background,
      appBar: AppBar(
        backgroundColor: aurora.background,
        elevation: 0,
        title: Text('Most Played', style: TextStyle(color: aurora.textPrimary)),
        iconTheme: IconThemeData(color: aurora.textPrimary),
        actions: [
          IconButton(
            icon: Icon(Icons.sort_rounded, color: aurora.textSecondary),
            onPressed: () => _showSortSheet(context),
          ),
        ],
      ),
      body: mostPlayedAsync.when(
        data: (list) {
          if (list.isEmpty) {
            return Center(
              child: Text('No played songs yet', style: TextStyle(color: aurora.textSecondary)),
            );
          }
          return ListView.builder(
            itemCount: list.length,
            itemBuilder: (context, index) {
              final item = list[index];
              final song = SearchResult(
                videoId: item.songId,
                title: item.title,
                author: item.author,
                thumbnail: item.thumbnail,
              );
              return ListTile(
                onTap: () => _play(list, index),
                onLongPress: () => showContextMenu(
                  context: context,
                  title: item.title,
                  subtitle: item.author,
                  type: ContextMenuType.song,
                  onAddToQueue: () => ref.read(musicPlayerRepositoryProvider).addToQueue(song),
                  onToggleFavorite: () => ref.read(libraryRepositoryProvider).toggleFavorite(
                        songId: item.songId,
                        title: item.title,
                        author: item.author,
                        thumbnail: item.thumbnail,
                      ),
                ),
                leading: ClipRRect(
                  borderRadius: BorderRadius.circular(6),
                  child: CachedArtwork(
                    imageUrl: item.thumbnail,
                    width: 48,
                    height: 48,
                    fit: BoxFit.cover,
                  ),
                ),
                title: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: aurora.textPrimary)),
                subtitle: Text(item.author, maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: aurora.textSecondary)),
                trailing: IconButton(
                  icon: Icon(Icons.play_arrow_rounded, color: aurora.primary),
                  onPressed: () => _play(list, index),
                ),
              );
            },
          );
        },
        loading: () => Center(child: CircularProgressIndicator(color: aurora.primary)),
        error: (_, __) => Center(child: Text('Failed to load', style: TextStyle(color: aurora.textSecondary))),
      ),
    );
  }
}
