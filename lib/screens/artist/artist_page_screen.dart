import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/playback/playback_engine.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';

/// Artist Page — Phase 6.5B, step 5.
///
/// ⚠️ No Artists table exists yet — everything here is derived from
/// [artistTracksProvider] (flat `Songs.artistId` grouping), mirroring
/// AlbumDetailsScreen's approach to the missing Albums table:
///
/// - Artist display name: taken from the first track's `author` field
///   (Songs rows sharing an artistId are expected to share an author
///   string — this is a display convenience, not a separate identity
///   concept).
/// - Artist image / monthly listeners: NOT in schema — never invented.
///   Falls back to first track's thumbnail as a stand-in visual, no
///   fake listener count is shown.
/// - Popular Tracks: all artist tracks, shown in repository order
///   (addedAt desc) — NOT labelled as "ranked by plays" anywhere in
///   the UI, since no artist-scope play-count ranking exists yet.
/// - Albums / Singles: SearchResult doesn't carry albumId directly, so
///   real grouping needs a per-track metadata fetch (N+1) — left as a
///   future wiring point, shown as "Coming soon" placeholders.
/// - Related Artists / Recently Released: no data source exists —
///   "Coming soon" placeholders, same pattern as AlbumDetailsScreen's
///   "More from this artist" / "Similar albums" placeholders.
class ArtistPageScreen extends ConsumerWidget {
  final String artistId;

  const ArtistPageScreen({super.key, required this.artistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tracksAsync = ref.watch(artistTracksProvider(artistId));

    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      body: tracksAsync.when(
        loading: () => const Center(
          child: CircularProgressIndicator(color: Color(0xFF6D5DFC)),
        ),
        error: (err, _) => _ErrorState(artistId: artistId, error: err),
        data: (tracks) {
          if (tracks.isEmpty) {
            return _EmptyState(artistId: artistId);
          }
          return _ArtistContent(artistId: artistId, tracks: tracks);
        },
      ),
    );
  }
}

class _ArtistContent extends ConsumerWidget {
  final String artistId;
  final List<SearchResult> tracks;

  const _ArtistContent({required this.artistId, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final artistName = tracks.first.author;
    final heroImage = tracks.first.thumbnail;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: const Color(0xFF0A0A0A),
          expandedHeight: 280,
          pinned: true,
          leading: IconButton(
            icon: const Icon(Icons.arrow_back, color: Colors.white),
            onPressed: () {
              if (context.canPop()) {
                context.pop();
              } else {
                context.go('/home');
              }
            },
          ),
          flexibleSpace: FlexibleSpaceBar(
            background: Stack(
              fit: StackFit.expand,
              children: [
                Image.network(
                  heroImage,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) => Container(
                    color: const Color(0xFF141B2D),
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.2),
                        const Color(0xFF0A0A0A),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  left: 20,
                  right: 20,
                  bottom: 20,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        artistName,
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${tracks.length} song${tracks.length == 1 ? '' : 's'}',
                        style: const TextStyle(
                          color: Color(0xFF8A93A8),
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
            child: Row(
              children: [
                _PlayAllButton(artistId: artistId, tracks: tracks),
                const SizedBox(width: 12),
                _ShuffleButton(artistId: artistId, tracks: tracks),
              ],
            ),
          ),
        ),
        const SliverToBoxAdapter(child: _SectionHeader(title: 'Popular Tracks')),
        SliverList(
          delegate: SliverChildBuilderDelegate(
            (context, index) {
              final track = tracks[index];
              return _TrackRow(
                artistId: artistId,
                tracks: tracks,
                index: index,
                track: track,
              );
            },
            childCount: tracks.length,
          ),
        ),
        const SliverToBoxAdapter(child: _SectionHeader(title: 'Albums')),
        const SliverToBoxAdapter(
          child: _ComingSoonCard(label: 'Album grouping coming soon'),
        ),
        const SliverToBoxAdapter(child: _SectionHeader(title: 'Singles')),
        const SliverToBoxAdapter(
          child: _ComingSoonCard(label: 'Singles view coming soon'),
        ),
        const SliverToBoxAdapter(child: _SectionHeader(title: 'Related Artists')),
        const SliverToBoxAdapter(child: _ComingSoonCard(label: 'Coming soon')),
        const SliverToBoxAdapter(child: _SectionHeader(title: 'Recently Released')),
        const SliverToBoxAdapter(child: _ComingSoonCard(label: 'Coming soon')),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;

  const _SectionHeader({required this.title});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

class _ComingSoonCard extends StatelessWidget {
  final String label;

  const _ComingSoonCard({required this.label});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: const Color(0xFF141B2D),
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: const TextStyle(color: Color(0xFF8A93A8), fontSize: 13),
        ),
      ),
    );
  }
}

class _TrackRow extends ConsumerWidget {
  final String artistId;
  final List<SearchResult> tracks;
  final int index;
  final SearchResult track;

  const _TrackRow({
    required this.artistId,
    required this.tracks,
    required this.index,
    required this.track,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentTrack = ref.watch(currentTrackProvider).value;
    final isActive = currentTrack?.videoId == track.videoId;

    return ListTile(
      onTap: () {
        ref.read(musicPlayerRepositoryProvider).playFromContext(
              tracks: tracks,
              startIndex: index,
              source: QueueSource.artist,
            );
      },
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          track.thumbnail,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 44,
            height: 44,
            color: const Color(0xFF1B2338),
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isActive ? const Color(0xFF6D5DFC) : Colors.white,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        track.author,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: const TextStyle(color: Color(0xFF8A93A8), fontSize: 12),
      ),
      trailing: track.duration != null
          ? Text(
              _formatDuration(track.duration!),
              style: const TextStyle(color: Color(0xFF8A93A8), fontSize: 12),
            )
          : null,
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _PlayAllButton extends ConsumerWidget {
  final String artistId;
  final List<SearchResult> tracks;

  const _PlayAllButton({required this.artistId, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Expanded(
      child: ElevatedButton.icon(
        onPressed: tracks.isEmpty
            ? null
            : () {
                ref.read(musicPlayerRepositoryProvider).playFromContext(
                      tracks: tracks,
                      startIndex: 0,
                      source: QueueSource.artist,
                    );
              },
        icon: const Icon(Icons.play_arrow, size: 20),
        label: const Text('Play'),
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF6D5DFC),
          foregroundColor: Colors.white,
          padding: const EdgeInsets.symmetric(vertical: 14),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(24),
          ),
        ),
      ),
    );
  }
}

class _ShuffleButton extends ConsumerWidget {
  final String artistId;
  final List<SearchResult> tracks;

  const _ShuffleButton({required this.artistId, required this.tracks});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return OutlinedButton.icon(
      onPressed: tracks.isEmpty
          ? null
          : () {
              final shuffled = List<SearchResult>.from(tracks)..shuffle();
              ref.read(musicPlayerRepositoryProvider).playFromContext(
                    tracks: shuffled,
                    startIndex: 0,
                    source: QueueSource.artist,
                  );
            },
      icon: const Icon(Icons.shuffle, size: 18),
      label: const Text('Shuffle'),
      style: OutlinedButton.styleFrom(
        foregroundColor: Colors.white,
        side: const BorderSide(color: Color(0xFF1B2338)),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(24),
        ),
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  final String artistId;

  const _EmptyState({required this.artistId});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: const Center(
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'No songs found for this artist.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Color(0xFF8A93A8), fontSize: 14),
          ),
        ),
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  final String artistId;
  final Object error;

  const _ErrorState({required this.artistId, required this.error});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0A0A0A),
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            if (context.canPop()) {
              context.pop();
            } else {
              context.go('/home');
            }
          },
        ),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32),
          child: Text(
            'Could not load artist page.\n$error',
            textAlign: TextAlign.center,
            style: const TextStyle(color: Color(0xFF8A93A8), fontSize: 14),
          ),
        ),
      ),
    );
  }
}