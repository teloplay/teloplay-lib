import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../models/history_entry_model.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/music_player_provider.dart';
import 'home_providers.dart';
import 'widgets/album_card.dart';
import 'widgets/album_carousel.dart';
import 'widgets/album_grid.dart';

/// Home feed: a greeting, then shelves built from the existing home
/// providers. Nothing here fetches data itself — `recentlyPlayed`,
/// `favorites`, `mostPlayed` and `cachedSongs` were already wired for the
/// old rails, this just renders them as carousels plus a grid.
///
/// Loading renders an empty shelf rather than a spinner (the design brief
/// bans spinners; skeletons belong on the artwork, which CachedArtwork
/// already handles).
class HomeFeed extends ConsumerWidget {
  const HomeFeed({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;

    return ListView(
      padding: const EdgeInsets.only(bottom: AppSpacing.xxl),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
          child: Text(_greeting(), style: AppTypography.trackTitle.copyWith(color: aurora.textPrimary, fontSize: 26)),
        ),
        _Shelf(title: 'Recently played', async: ref.watch(recentlyPlayedForHomeProvider)),
        _FavoriteShelf(ref: ref),
        _Shelf(title: 'Most played', async: ref.watch(mostPlayedForHomeProvider)),
        _CachedGrid(ref: ref),
      ],
    );
  }

  /// Time-of-day greeting. Local clock only — no network, no locale table.
  static String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Still up?';
    if (hour < 12) return 'Good morning';
    if (hour < 17) return 'Good afternoon';
    if (hour < 21) return 'Good evening';
    return 'Wind down';
  }

  static void _play(WidgetRef ref, String id, String title, String author, String thumbnail) {
    ref.read(musicPlayerRepositoryProvider).playVideoId(
          id,
          trackInfo: SearchResult(videoId: id, title: title, author: author, thumbnail: thumbnail),
        );
  }
}

/// Shelf over a `RecentlyPlayedEntry` provider. Both `recentlyPlayed` and
/// `mostPlayed` return that type, so one widget covers both rails.
class _Shelf extends StatelessWidget {
  const _Shelf({required this.title, required this.async});

  final String title;
  final AsyncValue<List<RecentlyPlayedEntry>> async;

  @override
  Widget build(BuildContext context) {
    final entries = async.value;
    if (entries == null || entries.isEmpty) return const SizedBox.shrink();

    return Consumer(
      builder: (context, ref, _) => AlbumCarousel(
        title: title,
        items: [
          for (final e in entries)
            AlbumCardData(
              id: e.songId,
              title: e.title,
              subtitle: e.author,
              thumbnail: e.thumbnail,
              onTap: () => HomeFeed._play(ref, e.songId, e.title, e.author, e.thumbnail),
            ),
        ],
      ),
    );
  }
}

class _FavoriteShelf extends StatelessWidget {
  const _FavoriteShelf({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final favorites = ref.watch(favoritesForHomeProvider).value;
    if (favorites == null || favorites.isEmpty) return const SizedBox.shrink();

    return AlbumCarousel(
      title: 'Favorites',
      items: [
        for (final e in favorites)
          AlbumCardData(
            id: e.songId,
            title: e.title,
            subtitle: e.author,
            thumbnail: e.thumbnail,
            onTap: () => HomeFeed._play(ref, e.songId, e.title, e.author, e.thumbnail),
          ),
      ],
    );
  }
}

class _CachedGrid extends StatelessWidget {
  const _CachedGrid({required this.ref});

  final WidgetRef ref;

  @override
  Widget build(BuildContext context) {
    final cached = ref.watch(cachedSongsForHomeProvider).value;
    if (cached == null || cached.isEmpty) return const SizedBox.shrink();

    return AlbumGrid(
      title: 'Available offline',
      items: [
        for (final e in cached)
          AlbumCardData(
            id: e.songId,
            title: e.title,
            subtitle: e.author,
            thumbnail: e.thumbnail,
            onTap: () => HomeFeed._play(ref, e.songId, e.title, e.author, e.thumbnail),
          ),
      ],
    );
  }
}
