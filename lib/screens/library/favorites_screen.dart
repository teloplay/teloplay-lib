import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';

/// সব favorite গান — reactive, heart button টগল হলে সাথে সাথে
/// আপডেট হয় (favoritesProvider Stream-based বলে manual refresh লাগে না)।
class FavoritesScreen extends ConsumerWidget {
  const FavoritesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritesProvider);

    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('Favorites', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: favoritesAsync.when(
        data: (favorites) {
          if (favorites.isEmpty) {
            return Center(
              child: Text(
                'No Favorites yet',
                style: TextStyle(color: Colors.grey[600]),
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
                  style: const TextStyle(color: Colors.white, fontSize: 14),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  fav.author,
                  style: TextStyle(color: Colors.grey[500], fontSize: 12),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    IconButton(
                      icon: const Icon(Icons.favorite,
                          color: Colors.redAccent, size: 20),
                      tooltip: 'Remove from Favorites',
                      onPressed: () {
                        ref
                            .read(libraryRepositoryProvider)
                            .removeFavorite(fav.songId);
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.play_arrow,
                          color: Colors.greenAccent, size: 20),
                      onPressed: () {
                        // ⚠️ Context-based Queue (Phase 1 fix) — পুরো
                        // favorites list-ই queue হিসেবে সেট হচ্ছে, tap
                        // করা track থেকে শুরু করে।
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
        loading: () => const Center(
          child: CircularProgressIndicator(color: Colors.greenAccent),
        ),
        error: (e, _) => Center(
          child: Text(
            'Failed to load Favorites',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ),
      ),
    );
  }
}