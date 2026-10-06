import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../core/playback/playback_engine.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';

/// Artist Page — Phase 6.5B, step 5.
class ArtistPageScreen extends ConsumerWidget {
  final String artistId;

  const ArtistPageScreen({super.key, required this.artistId});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.aurora;
    final tracksAsync = ref.watch(artistTracksProvider(artistId));

    return Scaffold(
      backgroundColor: theme.background,
      body: tracksAsync.when(
        loading: () => Center(
          child: CircularProgressIndicator(color: theme.primary),
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
    final theme = context.aurora;
    final artistName = tracks.first.author;
    final heroImage = tracks.first.thumbnail;

    return CustomScrollView(
      slivers: [
        SliverAppBar(
          backgroundColor: theme.background,
          expandedHeight: 280,
          pinned: true,
          leading: IconButton(
            icon: Icon(Icons.arrow_back, color: theme.textPrimary),
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
                    color: theme.surfaceRaised,
                  ),
                ),
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [
                        Colors.black.withOpacity(0.2),
                        theme.background,
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
                        style: TextStyle(
                          color: theme.textPrimary,
                          fontSize: 32,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        '${tracks.length} song${tracks.length == 1 ? '' : 's'}',
                        style: TextStyle(
                          color: theme.textSecondary,
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
        SliverToBoxAdapter(
          child: _SectionHeader(title: 'Popular Tracks', theme: theme),
        ),
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
        // ─── A2 — Albums: client-side grouping of the already-fetched
        // artist tracks by albumId (no new query, no catalog API).
        // Sections with no data hide (honest empty = omit). Related
        // Artists and Recently Released had no data path (P2 discovery;
        // no release dates in schema) and are removed, not stubbed.
        ..._albumSections(context, ref, theme),
        ..._singlesSections(theme),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  /// Groups [tracks] by non-empty albumId, preserving first-seen order.
  List<_AlbumGroup> get _albumGroups {
    final order = <String>[];
    final byId = <String, List<SearchResult>>{};
    for (final t in tracks) {
      final id = t.albumId;
      if (id == null || id.trim().isEmpty) continue;
      if (!byId.containsKey(id)) {
        order.add(id);
        byId[id] = [];
      }
      byId[id]!.add(t);
    }
    return order.map((id) {
      final group = byId[id]!;
      String name = 'Unknown Album';
      for (final t in group) {
        final n = t.albumName;
        if (n != null && n.trim().isNotEmpty) {
          name = n;
          break;
        }
      }
      return _AlbumGroup(
        albumId: id,
        name: name,
        thumbnail: group.first.thumbnail,
        trackCount: group.length,
      );
    }).toList();
  }

  List<Widget> _albumSections(
      BuildContext context, WidgetRef ref, AuroraColors theme) {
    final groups = _albumGroups;
    if (groups.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(title: 'Albums', theme: theme),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final album = groups[index];
            return _AlbumRow(album: album, theme: theme);
          },
          childCount: groups.length,
        ),
      ),
    ];
  }

  List<Widget> _singlesSections(AuroraColors theme) {
    final singles = tracks
        .where((t) => t.albumId == null || t.albumId!.trim().isEmpty)
        .toList();
    if (singles.isEmpty) return const [];
    return [
      SliverToBoxAdapter(
        child: _SectionHeader(title: 'Singles', theme: theme),
      ),
      SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final track = singles[index];
            return _TrackRow(
              artistId: artistId,
              tracks: singles,
              index: index,
              track: track,
            );
          },
          childCount: singles.length,
        ),
      ),
    ];
  }
}

class _SectionHeader extends StatelessWidget {
  final String title;
  final AuroraColors theme;

  const _SectionHeader({required this.title, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
      child: Text(
        title,
        style: TextStyle(
          color: theme.textPrimary,
          fontSize: 18,
          fontWeight: FontWeight.w600,
        ),
      ),
    );
  }
}

/// A2 — one album derived from already-fetched artist tracks.
class _AlbumGroup {
  const _AlbumGroup({
    required this.albumId,
    required this.name,
    required this.thumbnail,
    required this.trackCount,
  });
  final String albumId;
  final String name;
  final String thumbnail;
  final int trackCount;
}

/// A2 — album row navigating to the real album screen. No new query:
///
/// tap → existing `/album/:id` route.
class _AlbumRow extends StatelessWidget {
  const _AlbumRow({required this.album, required this.theme});
  final _AlbumGroup album;
  final AuroraColors theme;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      hoverColor: theme.surfaceElevated,
      onTap: () => context.push('/album/${album.albumId}'),
      leading: ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: Image.network(
          album.thumbnail,
          width: 44,
          height: 44,
          fit: BoxFit.cover,
          errorBuilder: (context, error, stackTrace) => Container(
            width: 44,
            height: 44,
            color: theme.surfaceRaised,
          ),
        ),
      ),
      title: Text(
        album.name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.textPrimary),
      ),
      subtitle: Text(
        '${album.trackCount} song${album.trackCount == 1 ? '' : 's'}',
        style: TextStyle(color: theme.textSecondary, fontSize: 12),
      ),
      trailing: Icon(
        Icons.chevron_right,
        size: 18,
        color: theme.textSecondary,
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
    final theme = context.aurora;
    final currentTrack = ref.watch(currentTrackProvider).value;
    final isActive = currentTrack?.videoId == track.videoId;

    return ListTile(
      // P1-M — desktop hover affordance.
      hoverColor: theme.surfaceElevated,
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
            color: theme.surfaceRaised,
          ),
        ),
      ),
      title: Text(
        track.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: isActive ? theme.primary : theme.textPrimary,
          fontWeight: isActive ? FontWeight.w600 : FontWeight.normal,
        ),
      ),
      subtitle: Text(
        track.author,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: TextStyle(color: theme.textSecondary, fontSize: 12),
      ),
      trailing: track.duration != null
          ? Text(
              _formatDuration(track.duration!),
              style: TextStyle(color: theme.textSecondary, fontSize: 12),
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
    final theme = context.aurora;
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
        icon: Icon(Icons.play_arrow, size: 20, color: theme.background),
        label: Text('Play', style: TextStyle(color: theme.background)),
        style: ElevatedButton.styleFrom(
          backgroundColor: theme.primary,
          foregroundColor: theme.background,
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
    final theme = context.aurora;
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
      icon: Icon(Icons.shuffle, size: 18, color: theme.textPrimary),
      label: Text('Shuffle', style: TextStyle(color: theme.textPrimary)),
      style: OutlinedButton.styleFrom(
        foregroundColor: theme.textPrimary,
        side: BorderSide(color: theme.surfaceRaised),
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
    final theme = context.aurora;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.textPrimary),
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
            'No songs found for this artist.',
            textAlign: TextAlign.center,
            style: TextStyle(color: theme.textSecondary, fontSize: 14),
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
    final theme = context.aurora;
    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        elevation: 0,
        leading: IconButton(
          icon: Icon(Icons.arrow_back, color: theme.textPrimary),
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
            style: TextStyle(color: theme.textSecondary, fontSize: 14),
          ),
        ),
      ),
    );
  }
}