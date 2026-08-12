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
        SliverToBoxAdapter(
          child: _SectionHeader(title: 'Albums', theme: theme),
        ),
        SliverToBoxAdapter(
          child: _ComingSoonCard(label: 'Album grouping coming soon', theme: theme),
        ),
        SliverToBoxAdapter(
          child: _SectionHeader(title: 'Singles', theme: theme),
        ),
        SliverToBoxAdapter(
          child: _ComingSoonCard(label: 'Singles view coming soon', theme: theme),
        ),
        SliverToBoxAdapter(
          child: _SectionHeader(title: 'Related Artists', theme: theme),
        ),
        SliverToBoxAdapter(
          child: _ComingSoonCard(label: 'Coming soon', theme: theme),
        ),
        SliverToBoxAdapter(
          child: _SectionHeader(title: 'Recently Released', theme: theme),
        ),
        SliverToBoxAdapter(
          child: _ComingSoonCard(label: 'Coming soon', theme: theme),
        ),
        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
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

class _ComingSoonCard extends StatelessWidget {
  final String label;
  final AuroraColors theme;

  const _ComingSoonCard({required this.label, required this.theme});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(vertical: 24),
        decoration: BoxDecoration(
          color: theme.surfaceRaised,
          borderRadius: BorderRadius.circular(12),
        ),
        alignment: Alignment.center,
        child: Text(
          label,
          style: TextStyle(color: theme.textSecondary, fontSize: 13),
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
    final theme = context.aurora;
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