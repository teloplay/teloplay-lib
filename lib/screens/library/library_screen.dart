import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../models/history_entry_model.dart';
import '../../models/playlist_model.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../widgets/cached_artwork.dart';
import 'downloaded_songs_screen.dart';
import 'favorites_screen.dart';
import 'history_screen.dart';
import 'playlist_detail_screen.dart';
import 'playlists_screen.dart';

/// Library central hub — Recently Played, Favorites, Most Played,
/// Playlists all together in small preview form, each "See all" goes
/// to its own full screen.
///
/// Design principle (roadmap Phase 2 target): this screen is intentionally
/// lightweight — each section is an independent `_buildXSection()` method,
/// handles its own data/loading/error. Future sections (Phase 7+ Smart
/// Queue/Continue Listening/Daily Mix) only need a new builder method
/// added to the Column below — no redesign of existing sections needed.
class LibraryScreen extends ConsumerStatefulWidget {
  final String? section;
  const LibraryScreen({super.key, this.section});

  @override
  ConsumerState createState() => _LibraryScreenState();
}

class _LibraryScreenState extends ConsumerState<LibraryScreen> {
  @override
  void initState() {
    super.initState();
    if (widget.section != null && widget.section != 'root') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSection(widget.section!));
    }
  }

  @override
  void didUpdateWidget(covariant LibraryScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.section != oldWidget.section &&
        widget.section != null &&
        widget.section != 'root') {
      WidgetsBinding.instance.addPostFrameCallback((_) => _openSection(widget.section!));
    }
  }

  void _openSection(String section) {
    switch (section) {
      case 'favorites':
        _openFavorites(context);
        break;
      case 'playlists':
        _openPlaylists(context);
        break;
      case 'offline':
      case 'offline/downloaded':
      case 'offline/cached':
        _openDownloadedSongs(context);
        break;
      case 'recent':
        _openHistory(context);
        break;
      case 'most-played':
        break;
    }
  }

  void _openFavorites(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const FavoritesScreen()),
    );
  }

  void _openHistory(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const HistoryScreen()),
    );
  }

  void _openPlaylists(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const PlaylistsScreen()),
    );
  }

  void _openPlaylistDetail(BuildContext context, String playlistId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => PlaylistDetailScreen(playlistId: playlistId),
      ),
    );
  }

  void _openDownloadedSongs(BuildContext context) {
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => const DownloadedSongsScreen()),
    );
  }

  Future<void> _createPlaylist(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    final aurora = Theme.of(context).extension<AuroraColors>() ?? AuroraColors.dark;

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: aurora.surfaceElevated,
        title: Text('New Playlist', style: TextStyle(color: aurora.textPrimary)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: TextStyle(color: aurora.textPrimary),
          decoration: InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: aurora.textSecondary),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text('Cancel', style: TextStyle(color: aurora.textSecondary)),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text('Create', style: TextStyle(color: aurora.primary)),
          ),
        ],
      ),
    );

    if (name == null || name.trim().isEmpty) return;
    if (!context.mounted) return;

    final playlistId = await ref
        .read(playlistRepositoryProvider)
        .createPlaylist(name: name.trim());

    if (!context.mounted) return;
    _openPlaylistDetail(context, playlistId);
  }

  Widget _sectionHeader(
    BuildContext context, {
    required String title,
    VoidCallback? onSeeAll,
  }) {
    final aurora = context.aurora;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: TextStyle(
              color: aurora.textPrimary,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: Text(
                'See all',
                style: TextStyle(color: aurora.primary, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildRecentlyPlayedSection(BuildContext context, WidgetRef ref) {
    final recentAsync = ref.watch(recentlyPlayedProvider);

    return recentAsync.when(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              title: 'Recently Played',
              onSeeAll: () => _openHistory(context),
            ),
            _HorizontalTrackRow(
              items: entries
                  .map((e) => _TrackCardData(
                        songId: e.songId,
                        title: e.title,
                        author: e.author,
                        thumbnail: e.thumbnail,
                      ))
                  .toList(),
              source: QueueSource.unknown,
            ),
          ],
        );
      },
      loading: () => const _SectionLoading(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildFavoritesSection(BuildContext context, WidgetRef ref) {
    final favoritesAsync = ref.watch(favoritesProvider);

    return favoritesAsync.when(
      data: (favorites) {
        if (favorites.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              title: 'Favorites',
              onSeeAll: () => _openFavorites(context),
            ),
            _HorizontalTrackRow(
              items: favorites
                  .map((f) => _TrackCardData(
                        songId: f.songId,
                        title: f.title,
                        author: f.author,
                        thumbnail: f.thumbnail,
                      ))
                  .toList(),
              source: QueueSource.favorites,
            ),
          ],
        );
      },
      loading: () => const _SectionLoading(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildDownloadedSection(BuildContext context, WidgetRef ref) {
    final cachedAsync = ref.watch(cachedSongsProvider);

    return cachedAsync.when(
      data: (entries) {
        if (entries.isEmpty) return const SizedBox.shrink();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              title: 'Downloaded',
              onSeeAll: () => _openDownloadedSongs(context),
            ),
            _HorizontalTrackRow(
              items: entries
                  .map((e) => _TrackCardData(
                        songId: e.songId,
                        title: e.title,
                        author: e.author,
                        thumbnail: e.thumbnail,
                      ))
                  .toList(),
              source: QueueSource.downloaded,
            ),
          ],
        );
      },
      loading: () => const _SectionLoading(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildMostPlayedSection(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, title: 'Most Played'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Coming soon',
            style: TextStyle(color: aurora.textSecondary, fontSize: 12),
          ),
        ),
      ],
    );
  }

  Widget _buildPlaylistsSection(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);
    final aurora = context.aurora;

    return playlistsAsync.when(
      data: (playlists) {
        if (playlists.isEmpty) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _sectionHeader(context, title: 'Playlists'),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Container(
                  padding: const EdgeInsets.all(20),
                  width: double.infinity,
                  decoration: BoxDecoration(
                    color: aurora.surfaceRaised,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withOpacity(0.05),
                    ),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.playlist_play,
                          color: aurora.textSecondary, size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'No Playlists yet',
                        style: TextStyle(
                            color: aurora.textSecondary, fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _createPlaylist(context, ref),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(
                              color: aurora.textSecondary.withOpacity(0.3)),
                        ),
                        child: Text(
                          'New Playlist',
                          style: TextStyle(color: aurora.textPrimary),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          );
        }

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionHeader(
              context,
              title: 'Playlists',
              onSeeAll: () => _openPlaylists(context),
            ),
            _HorizontalPlaylistRow(
              playlists: playlists,
              onTap: (playlistId) => _openPlaylistDetail(context, playlistId),
            ),
          ],
        );
      },
      loading: () => const _SectionLoading(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Scaffold(
      backgroundColor: aurora.background,
      appBar: AppBar(
        backgroundColor: aurora.background,
        elevation: 0,
        title: Text('Library', style: TextStyle(color: aurora.textPrimary)),
        iconTheme: IconThemeData(color: aurora.textPrimary),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildRecentlyPlayedSection(context, ref),
            _buildFavoritesSection(context, ref),
            _buildDownloadedSection(context, ref),
            _buildMostPlayedSection(context, ref),
            _buildPlaylistsSection(context, ref),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}

class _TrackCardData {
  final String songId;
  final String title;
  final String author;
  final String thumbnail;

  const _TrackCardData({
    required this.songId,
    required this.title,
    required this.author,
    required this.thumbnail,
  });
}

class _HorizontalTrackRow extends ConsumerWidget {
  final List<_TrackCardData> items;
  final QueueSource source;

  const _HorizontalTrackRow({required this.items, required this.source});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    return SizedBox(
      height: 156,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: items.length,
        itemBuilder: (context, index) {
          final item = items[index];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () {
                final tracks = items
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
                      source: source,
                    );
              },
              child: SizedBox(
                width: 110,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    CachedArtwork(
                      imageUrl: item.thumbnail,
                      width: 110,
                      height: 110,
                      borderRadius: BorderRadius.circular(8),
                      memCacheWidth: 220,
                      memCacheHeight: 220,
                      placeholderIcon: Icons.music_note,
                    ),
                    const SizedBox(height: 6),
                    Text(
                      item.title,
                      style: TextStyle(
                          color: aurora.textPrimary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.author,
                      style: TextStyle(
                          color: aurora.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

// FIX: Changed PlaylistModel to PlaylistSummary (actual class name in playlist_model.dart)
class _HorizontalPlaylistRow extends StatelessWidget {
  final List<PlaylistSummary> playlists;
  final void Function(String playlistId) onTap;

  const _HorizontalPlaylistRow({
    required this.playlists,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return SizedBox(
      height: 156,
      child: ListView.builder(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        itemCount: playlists.length,
        itemBuilder: (context, index) {
          final playlist = playlists[index];
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: GestureDetector(
              onTap: () => onTap(playlist.id),
              child: SizedBox(
                width: 110,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    playlist.coverThumbnail != null
                        ? CachedArtwork(
                            imageUrl: playlist.coverThumbnail!,
                            width: 110,
                            height: 110,
                            borderRadius: BorderRadius.circular(8),
                            memCacheWidth: 220,
                            memCacheHeight: 220,
                            placeholderIcon: Icons.playlist_play,
                          )
                        : Container(
                            width: 110,
                            height: 110,
                            decoration: BoxDecoration(
                              color: aurora.surface,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.playlist_play,
                              color: aurora.textSecondary,
                              size: 32,
                            ),
                          ),
                    const SizedBox(height: 6),
                    Text(
                      playlist.name,
                      style: TextStyle(
                          color: aurora.textPrimary, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${playlist.itemCount} songs',
                      style: TextStyle(
                          color: aurora.textSecondary, fontSize: 11),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SectionLoading extends StatelessWidget {
  const _SectionLoading();

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: aurora.primary,
        ),
      ),
    );
  }
}