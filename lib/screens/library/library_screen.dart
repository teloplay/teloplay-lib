import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../models/history_entry_model.dart'; // CachedSongEntry
import '../../models/playlist_model.dart';
import '../../providers/library_provider.dart'; // cachedSongsProvider এখানেই
import '../../providers/music_player_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../widgets/cached_artwork.dart';
import 'downloaded_songs_screen.dart';
import 'favorites_screen.dart';
import 'history_screen.dart';
import 'playlist_detail_screen.dart';
import 'playlists_screen.dart';

/// Library-এর central hub — Recently Played, Favorites, Most Played,
/// Playlists সব একসাথে ছোট preview আকারে, প্রতিটার "সব দেখুন" নিজ নিজ
/// full screen-এ নিয়ে যায়।
///
/// ⚠️ Design নীতি (roadmap Phase 2 লক্ষ্য অনুযায়ী): এই screen ইচ্ছাকৃতভাবে
/// lightweight রাখা হয়েছে — প্রতিটা section একটা independent
/// `_buildXSection()` method, নিজের data/loading/error নিজে handle করে।
/// ভবিষ্যতে নতুন section (যেমন Phase 7+ Smart Queue/Continue Listening/
/// Daily Mix) যোগ করতে শুধু একটা নতুন builder method লিখে নিচের
/// `Column`-এ একটা entry বসালেই হবে — বাকি section-গুলোর কোনো redesign
/// লাগবে না, প্রতিটা section সম্পূর্ণ স্বনির্ভর।
///
/// ⚠️ Playlists section (এই ব্যাচ): আগে placeholder ছিল (disabled
/// button, "No Playlists yet" hardcoded), এখন playlistsProvider দিয়ে
/// আসল data দেখায় — খালি থাকলে placeholder + কাজ-করা "New Playlist"
/// button, গান থাকলে horizontal preview row (Recently Played/
/// Favorites-এর একই _HorizontalPlaylistRow প্যাটার্নে)।
///
/// ⚠️ Downloaded section (Phase 3 — Smart Cache, এই ব্যাচ): cachedSongsProvider
/// দিয়ে Library-তে locally cached গানগুলো preview row হিসেবে দেখানো হয়,
/// Recently Played/Favorites-এর একই _HorizontalTrackRow প্যাটার্নে —
/// "See all" DownloadedSongsScreen-এ নিয়ে যায়।
///
/// [section] — one of: null (hub), 'favorites', 'playlists', 'offline',
/// 'offline/downloaded', 'offline/cached', 'recent', 'most-played'.
/// Set by the /library/:section nested route (app_router.dart, UI-Batch 2).
/// When non-null, immediately pushes the matching existing full screen
/// on top (so PremiumSidebar's deep-links reuse existing screens instead
/// of duplicating their UI here).
class LibraryScreen extends ConsumerStatefulWidget {
  final String? section;
  const LibraryScreen({super.key, this.section});

  @override
  ConsumerState<LibraryScreen> createState() => _LibraryScreenState();
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
        // ⚠️ No dedicated Most Played screen exists yet (Phase 7+
        // per roadmap) — stays on the hub for now, hub already shows
        // the "Coming soon" Most Played section.
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

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        backgroundColor: const Color(0xFF1E1E1E),
        title: const Text('New Playlist', style: TextStyle(color: Colors.white)),
        content: TextField(
          controller: controller,
          autofocus: true,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            hintText: 'Playlist name',
            hintStyle: TextStyle(color: Colors.grey),
          ),
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
            child: const Text('Create', style: TextStyle(color: Colors.greenAccent)),
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
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 16,
              fontWeight: FontWeight.bold,
            ),
          ),
          if (onSeeAll != null)
            TextButton(
              onPressed: onSeeAll,
              child: const Text(
                'See all',
                style: TextStyle(color: Colors.greenAccent, fontSize: 12),
              ),
            ),
        ],
      ),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Recently Played section
  // ═══════════════════════════════════════════════════════════════

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
  source: QueueSource.unknown,   // ← এই লাইনটা যোগ করো
),
          ],
        );
      },
      loading: () => const _SectionLoading(),
      // Non-critical section — ব্যর্থ হলে চুপচাপ hide, পুরো Library
      // screen ভাঙা উচিত না।
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Favorites section
  // ═══════════════════════════════════════════════════════════════

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
  source: QueueSource.favorites,   // ← এই লাইনটা যোগ করো
),
          ],
        );
      },
      loading: () => const _SectionLoading(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Downloaded Songs section (Phase 3 — Smart Cache)
  // ═══════════════════════════════════════════════════════════════

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
  source: QueueSource.downloaded,   // ← এই লাইনটা যোগ করো
),
          ],
        );
      },
      loading: () => const _SectionLoading(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Most Played section — placeholder (অপরিবর্তিত, Phase 7+)
  // ═══════════════════════════════════════════════════════════════
  //
  // ⚠️ LibraryRepository.getMostPlayed() এখনো Phase 7+ এর TODO
  // (roadmap-এ স্পষ্টভাবে Advanced/Future-এ রাখা হয়েছে, Behaviour
  // Tracking data-নির্ভর aggregation)। এখন শুধু slot রাখা হচ্ছে যাতে
  // ভবিষ্যতে যোগ করার সময় এই screen-এর layout না বদলাতে হয় — শুধু
  // এই method-এর ভেতরটা বদলে আসল data বসিয়ে দিলেই চলবে।

  Widget _buildMostPlayedSection(BuildContext context, WidgetRef ref) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _sectionHeader(context, title: 'Most Played'),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Coming soon',
            style: TextStyle(color: Colors.grey[600], fontSize: 12),
          ),
        ),
      ],
    );
  }

  // ═══════════════════════════════════════════════════════════════
  // Playlists section — এই ব্যাচে আসল data দিয়ে wire করা হলো
  // ═══════════════════════════════════════════════════════════════

  Widget _buildPlaylistsSection(BuildContext context, WidgetRef ref) {
    final playlistsAsync = ref.watch(playlistsProvider);

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
                    color: const Color(0xFF1E1E1E),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Column(
                    children: [
                      Icon(Icons.playlist_play, color: Colors.grey[600], size: 32),
                      const SizedBox(height: 8),
                      Text(
                        'No Playlists yet',
                        style: TextStyle(color: Colors.grey[500], fontSize: 13),
                      ),
                      const SizedBox(height: 12),
                      OutlinedButton(
                        onPressed: () => _createPlaylist(context, ref),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.grey[700]!),
                        ),
                        child: const Text(
                          'New Playlist',
                          style: TextStyle(color: Colors.white),
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
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('Library', style: TextStyle(color: Colors.white)),
        iconTheme: const IconThemeData(color: Colors.white),
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

// ─────────────────────────────────────────────────────────────────────────
// Shared small widgets — Recently Played ও Favorites দুটো section-ই একই
// horizontal-card layout ব্যবহার করে, তাই একবার লিখে reuse করা হচ্ছে।
// ─────────────────────────────────────────────────────────────────────────

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
    return SizedBox(
      height: 156,  // was 150 — fixes 2px text-overflow (title + author line-height)
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
                  mainAxisSize: MainAxisSize.min,  // ADD: don't force extra height
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
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      item.author,
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
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

/// Playlists section-এর horizontal preview row — _HorizontalTrackRow
/// থেকে আলাদা কারণ playlist card-এ author-এর জায়গায় item count দেখায়,
/// এবং cover thumbnail null হতে পারে (খালি playlist এই list-এ আসবে না
/// যেহেতু empty-state আলাদাভাবে handle হয়, কিন্তু defensive fallback
/// রাখা হলো)।
class _HorizontalPlaylistRow extends StatelessWidget {
  final List<PlaylistSummary> playlists;
  final void Function(String playlistId) onTap;

  const _HorizontalPlaylistRow({required this.playlists, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 156,  // was 150
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
                  mainAxisSize: MainAxisSize.min,  // ADD
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
                              color: const Color(0xFF2A2A2A),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Icon(
                              Icons.playlist_play,
                              color: Colors.grey[600],
                              size: 32,
                            ),
                          ),
                    const SizedBox(height: 6),
                    Text(
                      playlist.name,
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${playlist.itemCount} songs',
                      style: TextStyle(color: Colors.grey[500], fontSize: 11),
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
    return const Padding(
      padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SizedBox(
        height: 20,
        width: 20,
        child: CircularProgressIndicator(
          strokeWidth: 2,
          color: Colors.greenAccent,
        ),
      ),
    );
  }
}