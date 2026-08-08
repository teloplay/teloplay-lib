import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';

/// Phase 6.5B — Album Details Screen.
///
/// Route: `/album/:id` (top-level, chrome-less, same tier as `/song/:id` —
/// see the locked route architecture).
///
/// ⚠️ Architecture rule (locked): this screen NEVER queries Songs
/// directly and never assumes a normalized Albums table. Its ONLY data
/// source is `LibraryRepository.getSongsByAlbumId()` via
/// `albumTracksProvider` — if a future Albums table replaces the flat
/// `Songs.albumId`/`albumName` columns, only the repository method's
/// internals change; this screen's shape stays identical.
///
/// ⚠️ No separate Albums row exists yet — header data (name, artist,
/// track count, total duration) is entirely DERIVED from the track
/// list itself (first track's albumName/author). Release Year is
/// omitted entirely (not shown as "Unknown") since it doesn't exist
/// anywhere in the schema — same no-invented-fields discipline as
/// SongDetailsScreen's releaseYear omission.
///
/// ⚠️ Context-aware play (locked decision, same as SongDetailsScreen) —
/// this screen never builds its own queue outside of playFromContext().
/// Play Album / Shuffle / individual track tap all funnel through the
/// single centralized entry point.
class AlbumDetailsScreen extends ConsumerWidget {
  const AlbumDetailsScreen({super.key, required this.albumId});

  final String albumId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final tracksAsync = ref.watch(albumTracksProvider(albumId));

    return Scaffold(
      backgroundColor: aurora.background,
      body: SafeArea(
        child: tracksAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (err, _) => _ErrorState(
            message: 'Unable to load album',
            onBack: () => context.pop(),
          ),
          data: (tracks) {
            if (tracks.isEmpty) {
              return _EmptyState(onBack: () => context.pop());
            }
            return _AlbumContent(albumId: albumId, tracks: tracks);
          },
        ),
      ),
    );
  }
}

class _AlbumContent extends ConsumerWidget {
  const _AlbumContent({required this.albumId, required this.tracks});

  final String albumId;
  final List<SearchResult> tracks;

  // ─── Derived header data — no separate Albums row exists, so
  // everything comes from the track list itself.
  String get _albumName {
    for (final t in tracks) {
      // SearchResult doesn't carry albumName directly (that's
      // SongMetadata-only) — AlbumDetailsScreen is opened with a
      // resolved albumId, so we fall back to a generic label if the
      // list itself can't tell us the name. In practice, callers
      // (Album card taps) should pass a display name via route extra
      // in a future batch; for now this stays honest rather than
      // guessing.
      break;
    }
    return 'Album';
  }

  String get _artistName => tracks.first.author;

  int get _trackCount => tracks.length;

  Duration? get _totalDuration {
    var hasAny = false;
    var totalMs = 0;
    for (final t in tracks) {
      if (t.duration != null) {
        hasAny = true;
        totalMs += t.duration!.inMilliseconds;
      }
    }
    // ⚠️ Only meaningful if every track has a known duration — a
    // partial sum would understate the real total and mislead the
    // user, so if even one track's duration is missing (known gap,
    // e.g. Windows daemon search doesn't return duration), we show
    // nothing rather than a wrong number.
    if (!hasAny || totalMs == 0) return null;
    final allKnown = tracks.every((t) => t.duration != null);
    return allKnown ? Duration(milliseconds: totalMs) : null;
  }

  Future<void> _playAlbum(WidgetRef ref) async {
    final repo = ref.read(musicPlayerRepositoryProvider);
    await repo.playFromContext(
      tracks: tracks,
      startIndex: 0,
      source: QueueSource.album,
    );
  }

  Future<void> _shufflePlay(WidgetRef ref) async {
    final repo = ref.read(musicPlayerRepositoryProvider);
    final shuffled = List<SearchResult>.from(tracks)..shuffle();
    await repo.playFromContext(
      tracks: shuffled,
      startIndex: 0,
      source: QueueSource.album,
    );
  }

  Future<void> _playTrack(WidgetRef ref, int index) async {
    final repo = ref.read(musicPlayerRepositoryProvider);
    await repo.playFromContext(
      tracks: tracks,
      startIndex: index,
      source: QueueSource.album,
    );
  }

  void _addAllToQueue(WidgetRef ref) {
    final repo = ref.read(musicPlayerRepositoryProvider);
    for (final t in tracks) {
      repo.addToQueue(t);
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final currentTrackAsync = ref.watch(currentTrackProvider);
    final currentVideoId = currentTrackAsync.value?.videoId;

    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                IconButton(
                  icon: Icon(Icons.arrow_back, color: aurora.textPrimary),
                  onPressed: () => context.pop(),
                ),
              ],
            ),
          ),
        ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
            child: Column(
              children: [
                Hero(
                  tag: 'album-artwork-$albumId',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedArtwork(
                      imageUrl: tracks.first.thumbnail,
                      cacheKey: albumId,
                      width: 200,
                      height: 200,
                      memCacheWidth: 400,
                      memCacheHeight: 400,
                      placeholderIcon: Icons.album,
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  _albumName,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: aurora.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  _artistName,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: aurora.textSecondary, fontSize: 15),
                ),

                // ─── Derived metadata row — only shows fields we
                // actually have. Release Year omitted entirely (not
                // in schema, never invented).
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    _MetaChip(
                      label: '$_trackCount ${_trackCount == 1 ? 'song' : 'songs'}',
                      icon: Icons.music_note,
                    ),
                    if (_totalDuration != null)
                      _MetaChip(
                        label: _formatTotalDuration(_totalDuration!),
                        icon: Icons.schedule,
                      ),
                  ],
                ),

                const SizedBox(height: 28),

                // ─── Primary actions — Play Album is the primary CTA
                // (per locked feedback: most user actions are "just
                // play the album", not shuffle — Play gets the large
                // filled button, Shuffle is a secondary outlined
                // action next to it).
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Expanded(
                      child: _PrimaryPlayAlbumButton(
                        onTap: () => _playAlbum(ref),
                      ),
                    ),
                    const SizedBox(width: 12),
                    _SecondaryIconButton(
                      icon: Icons.shuffle,
                      tooltip: 'Shuffle play',
                      onTap: () => _shufflePlay(ref),
                    ),
                    const SizedBox(width: 8),
                    _SecondaryIconButton(
                      icon: Icons.playlist_add,
                      tooltip: 'Add all to queue',
                      onTap: () => _addAllToQueue(ref),
                    ),
                  ],
                ),

                // ─── Favorite / Share — album-level favorite has no
                // backend concept yet (Favorites table is per-song,
                // Phase 2). Rendered as disabled placeholders per
                // locked spec ("may exist as disabled/placeholder
                // actions if backend support is not ready yet") rather
                // than omitted, so the row visually matches Song
                // Details' action layout and the future wiring point
                // is obvious.
                const SizedBox(height: 12),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _SecondaryIconButton(
                      icon: Icons.favorite_border,
                      tooltip: 'Favorite (coming soon)',
                      onTap: null,
                    ),
                    const SizedBox(width: 8),
                    _SecondaryIconButton(
                      icon: Icons.share,
                      tooltip: 'Share (coming soon)',
                      onTap: null,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),

        // ─── Track list
        SliverPadding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          sliver: SliverList.builder(
            itemCount: tracks.length,
            itemBuilder: (context, index) {
              final track = tracks[index];
              final isPlaying = track.videoId == currentVideoId;
              return _TrackRow(
                index: index,
                track: track,
                isPlaying: isPlaying,
                onTap: () => _playTrack(ref, index),
              );
            },
          ),
        ),

        // ─── Future sections — More From Artist / Similar Albums.
        // Deliberately NOT implemented in this batch (same discipline
        // as SongDetailsScreen's _MoreFromArtistSection) — needs
        // LibraryRepository.getSongsByArtist(artistId), which doesn't
        // exist yet. Rendering headers now with "Coming soon" to avoid
        // Artist Page (next locked step) having to duplicate/reconcile
        // this query later.
        SliverToBoxAdapter(
          child: _ComingSoonSection(title: 'More from this artist'),
        ),
        SliverToBoxAdapter(
          child: _ComingSoonSection(title: 'Similar albums'),
        ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  String _formatTotalDuration(Duration d) {
    final hours = d.inHours;
    final minutes = d.inMinutes % 60;
    if (hours > 0) {
      return '$hours hr $minutes min';
    }
    return '$minutes min';
  }
}

// ─────────────────────────────────────────────────────────────────────
// Small presentational widgets — kept local, matching SongDetailsScreen's
// pattern (extract to shared widgets only when a third screen wants the
// same styling, per WORKFLOW RULES — don't invent shared widgets
// preemptively).
// ─────────────────────────────────────────────────────────────────────

class _MetaChip extends StatelessWidget {
  const _MetaChip({required this.label, required this.icon});
  final String label;
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: aurora.textSecondary),
        const SizedBox(width: 4),
        Text(label, style: TextStyle(color: aurora.textSecondary, fontSize: 13)),
      ],
    );
  }
}

class _PrimaryPlayAlbumButton extends StatelessWidget {
  const _PrimaryPlayAlbumButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Material(
      color: aurora.primary,
      borderRadius: BorderRadius.circular(24),
      child: InkWell(
        borderRadius: BorderRadius.circular(24),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.symmetric(vertical: 14),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.play_arrow, color: Colors.white, size: 22),
              SizedBox(width: 8),
              Text(
                'Play Album',
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SecondaryIconButton extends StatelessWidget {
  const _SecondaryIconButton({
    required this.icon,
    required this.tooltip,
    required this.onTap,
  });
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final enabled = onTap != null;
    return IconButton(
      icon: Icon(
        icon,
        color: enabled ? aurora.textSecondary : aurora.textSecondary.withOpacity(0.35),
      ),
      onPressed: onTap,
      tooltip: tooltip,
    );
  }
}

class _TrackRow extends StatelessWidget {
  const _TrackRow({
    required this.index,
    required this.track,
    required this.isPlaying,
    required this.onTap,
  });

  final int index;
  final SearchResult track;
  final bool isPlaying;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
          child: Row(
            children: [
              SizedBox(
                width: 28,
                child: isPlaying
                    ? Icon(Icons.volume_up, size: 16, color: aurora.primary)
                    : Text(
                        '${index + 1}',
                        style: TextStyle(
                          color: aurora.textSecondary,
                          fontSize: 13,
                        ),
                      ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      track.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: isPlaying ? aurora.primary : aurora.textPrimary,
                        fontSize: 14,
                        fontWeight: isPlaying ? FontWeight.w600 : FontWeight.w400,
                      ),
                    ),
                  ],
                ),
              ),
              if (track.duration != null) ...[
                const SizedBox(width: 8),
                Text(
                  _formatDuration(track.duration!),
                  style: TextStyle(color: aurora.textSecondary, fontSize: 13),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

class _ComingSoonSection extends StatelessWidget {
  const _ComingSoonSection({required this.title});
  final String title;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: TextStyle(
              color: aurora.textPrimary,
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Coming soon',
            style: TextStyle(color: aurora.textSecondary, fontSize: 13),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onBack});
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.album_outlined, color: aurora.textSecondary, size: 40),
          const SizedBox(height: 12),
          Text(
            'No songs found for this album',
            style: TextStyle(color: aurora.textSecondary),
          ),
          const SizedBox(height: 16),
          TextButton(onPressed: onBack, child: const Text('Go back')),
        ],
      ),
    );
  }
}

class _ErrorState extends StatelessWidget {
  const _ErrorState({required this.message, required this.onBack});
  final String message;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.error_outline, color: aurora.textSecondary, size: 40),
          const SizedBox(height: 12),
          Text(message, style: TextStyle(color: aurora.textSecondary)),
          const SizedBox(height: 16),
          TextButton(onPressed: onBack, child: const Text('Go back')),
        ],
      ),
    );
  }
}