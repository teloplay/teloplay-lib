import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';

/// All favorite songs — reactive, heart button toggles instantly
/// (favoritesProvider is Stream-based so no manual refresh needed).
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final favoritesAsync = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: aurora.background,
      appBar: AppBar(
        backgroundColor: aurora.background,
        elevation: 0,
        title: Text('Favorites', style: TextStyle(color: aurora.textPrimary)),
        iconTheme: IconThemeData(color: aurora.textPrimary),
      ),
      body: favoritesAsync.when(
        data: (favorites) {
          if (favorites.isEmpty) {
            return Center(
              child: Text(
                'No Favorites yet',
                style: TextStyle(color: aurora.textSecondary),
              ),
            );
          }

          return ListView.builder(
            itemCount: favorites.length,
            itemBuilder: (context, index) {
              final fav = favorites[index];
              return ListTile(
                leading: CachedArtwork(
                  imageUrl: fav.thumbnail,
                  width: 48,
                  height: 48,
                  borderRadius: BorderRadius.circular(4),
                  memCacheWidth: 96,
                  memCacheHeight: 96,
                  placeholderIcon: Icons.music_note,
                ),
                title: Text(
                  fav.title,
                  style: TextStyle(color: aurora.textPrimary, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  fav.author,
                  style: TextStyle(color: aurora.textSecondary, fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: Icon(Icons.favorite,
                          color: aurora.primary, size: 20),
                      tooltip: 'Remove from Favorites',
                      onPressed: () {
                        ref
                            .read(libraryRepositoryProvider)
                            .removeFavorite(fav.songId);
                      },
                    ),
                    IconButton(
                      icon: Icon(Icons.play_arrow,
                          color: aurora.primary, size: 20),
                      onPressed: () {
                        final tracks = favorites
                            .map((f) => SearchResult(
                                  videoId: f.songId,
                                  title: f.title,
                                  author: f.author,
                                  thumbnail: f.thumbnail,
                                ))
                            .toList();

                        ref.read(musicPlayerRepositoryProvider).playFromContext(
                              tracks: tracks,
                              startIndex: index,
                              source: QueueSource.favorites,
                            );
                      },
                    ),
                  ],
                ),
              );
            },
          );
        },
        loading: () => Center(
          child: CircularProgressIndicator(color: aurora.primary),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load Favorites',
            style: TextStyle(color: aurora.textSecondary),
          ),
        ),
      ),
    );
  }
}