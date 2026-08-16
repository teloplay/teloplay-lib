import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../providers/library_provider.dart';
import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../data/repositories/library_repository.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';
import '../../widgets/playlist/add_to_playlist_sheet.dart';
import '../../providers/library_provider.dart';   // libraryRepositoryProvider-এর জন্য
import '../../models/history_entry_model.dart';    // BehaviourStats-এর জন্য

/// Phase 6.5B — Song Details Screen.
///
/// Route: `/song/:id` (top-level, chrome-less, same tier as `/player` —
/// see the locked route architecture). Pushed on top of whichever shell
/// tab is currently active; owns its own back button / transition.
///
/// ⚠️ Context-aware play (locked decision) — this screen NEVER builds its
/// own queue. It receives an optional [contextTracks]/[startIndex] from
/// whatever list it was opened from (search results, album track list,
/// playlist, favorites, etc.) and passes them straight through to
/// `MusicPlayerRepository.playFromContext()`. If opened with no context
/// (e.g. a bare deep link to `/song/:id`), it falls back to a
/// single-track queue containing just this song. Queue-building logic
/// stays centralized in the repository — this screen only forwards data.
///
/// ⚠️ Known schema gaps, intentionally NOT faked here:
///   - No `releaseYear` / `publishedAt` anywhere in the schema or either
///     playback engine (confirmed against Songs table + both Innertube
///     engines) — this field is omitted entirely, not shown as "Unknown".
///   - "Play Count" is NOT a stored column — it's computed on-demand via
///     `LibraryRepository.getBehaviourStats(songId)` (existing method,
///     Phase 2), which derives it from HistoryEntries.
///   - Duration: Android's Innertube engine returns `SearchResult.duration`,
///     but the Windows daemon's `search` command intentionally omits it
///     (documented in the roadmap as a known gap). Duration is shown only
///     if present on the passed-in [SearchResult] — never invented.
///   - Album/Artist navigation ("Go to Album" / "Go to Artist") only
///     renders if `albumId`/`artistId` are present on the Songs row —
///     `albumId`/`albumName` require the Phase 6.5B schema migration
///     (locked, not yet applied) and will simply be absent/null until
///     then, which this screen already handles (buttons conditionally
///     hidden, not disabled-and-confusing).
class SongDetailsScreen extends ConsumerStatefulWidget {
  const SongDetailsScreen({
    super.key,
    required this.songId,
    this.track,
    this.contextTracks,
    this.startIndex,
    this.source = QueueSource.songDetails,
  });

  /// The song's videoId — always required, this is the route param.
  final String songId;

  /// The track data if the caller already has it in-memory (e.g. tapped
  /// from a search result list) — avoids a redundant lookup/search call.
  /// If null, this screen will attempt to resolve minimal display data
  /// from the local Songs table (title/author/thumbnail from whatever
  /// was last persisted for this songId — e.g. via Favorites/History/
  /// Queue upsert), since a bare deep link has no other source.
  final SearchResult? track;

  /// The list this song was opened from (search results, album track
  /// list, playlist, etc.) — passed straight through to
  /// `playFromContext()`. Null means "no context", triggering the
  /// single-track fallback queue.
  final List<SearchResult>? contextTracks;

  /// This song's index within [contextTracks]. Required if
  /// [contextTracks] is provided; ignored otherwise.
  final int? startIndex;

  /// Where this screen was opened from — forwarded to `playFromContext()`
  /// for the "Playing from X" UI hint (future use) and analytics.
  final QueueSource source;

  @override
  ConsumerState<SongDetailsScreen> createState() => _SongDetailsScreenState();
}

class _SongDetailsScreenState extends ConsumerState<SongDetailsScreen> {
  SongDetailsData? _data;
  bool _loading = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    // ⚠️ Fix-First List #6 — videoId validation, defense-in-depth. The
    // search screen already blocks navigation for an empty videoId (see
    // search_screen.dart _openSong), but this screen is also reachable
    // from other entry points (deep links, history, etc.), so the same
    // guard belongs here too — with a message that names the real cause
    // instead of the generic "Song not found" a failed library lookup
    // would otherwise show.
    if (widget.songId.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'This song is missing its playback ID and can\'t be opened.';
      });
      return;
    }

    try {
      final libraryRepo = ref.read(libraryRepositoryProvider);

      // Resolve display track — prefer what the caller already gave us
      // (no redundant lookup needed), otherwise fall back to whatever's
      // persisted locally for this songId.
      SearchResult? track = widget.track;
      track ??= await libraryRepo.getPlayableSongById(widget.songId);

      if (track == null) {
        setState(() {
          _loading = false;
          _error = 'Song not found in your library.';
        });
        return;
      }

      final results = await Future.wait([
        libraryRepo.getSongMetadata(widget.songId),
        libraryRepo.getBehaviourStats(songId: widget.songId),
        libraryRepo.isFavorite(widget.songId),
      ]);

      if (!mounted) return;

      setState(() {
        _data = SongDetailsData(
          track: track!,
          metadata: results[0] as SongMetadata?,
          stats: results[1] as BehaviourStats,
          isFavorite: results[2] as bool,
        );
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Unable to load song details';
      });
    }
  }

  Future<void> _play() async {
    final data = _data;
    if (data == null) return;

    final repo = ref.read(musicPlayerRepositoryProvider);

    // Priority order (locked): context queue → single-song fallback.
    // Never build a new queue here — always forward through
    // playFromContext(), which is the single centralized entry point.
    if (widget.contextTracks != null && widget.startIndex != null) {
      await repo.playFromContext(
        tracks: widget.contextTracks!,
        startIndex: widget.startIndex!,
        source: widget.source,
      );
    } else {
      await repo.playFromContext(
        tracks: [data.track],
        startIndex: 0,
        source: widget.source,
      );
    }
  }

  Future<void> _toggleFavorite() async {
    final data = _data;
    if (data == null) return;

    final libraryRepo = ref.read(libraryRepositoryProvider);
    final newState = await libraryRepo.toggleFavorite(
      songId: data.track.videoId,
      title: data.track.title,
      author: data.track.author,
      thumbnail: data.track.thumbnail,
      durationSeconds: data.track.duration?.inSeconds,
    );

    if (!mounted) return;
    setState(() {
      _data = data.copyWith(isFavorite: newState);
    });
  }

  void _addToQueue() {
    final data = _data;
    if (data == null) return;
    ref.read(musicPlayerRepositoryProvider).addToQueue(data.track);
  }

  void _goToAlbum() {
    final albumId = _data?.metadata?.albumId;
    if (albumId == null) return;
    context.push('/album/$albumId');
  }

  void _goToArtist() {
    final artistId = _data?.metadata?.artistId;
    if (artistId == null) return;
    context.push('/artist/$artistId');
  }

  void _showAddToPlaylist() {
    final data = _data;
    if (data == null) return;
    AddToPlaylistSheet.show(context: context, track: data.track);
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return Scaffold(
      backgroundColor: aurora.background,
      body: SafeArea(
        child: _loading
            ? const Center(child: CircularProgressIndicator())
            : _error != null
                ? _ErrorState(message: _error!, onBack: () => context.pop())
                : _buildContent(context, aurora, _data!),
      ),
    );
  }

  Widget _buildContent(BuildContext context, AuroraColors aurora, SongDetailsData data) {
    final track = data.track;
    final meta = data.metadata;

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
            padding: const EdgeInsets.all(24),
            child: Column(
              children: [
                Hero(
                  tag: 'artwork-${track.videoId}',
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: CachedArtwork(
                      imageUrl: track.thumbnail,
                      cacheKey: track.videoId,
                      width: 220,
                      height: 220,
                      memCacheWidth: 440,
                      memCacheHeight: 440,
                      placeholderIcon: Icons.music_note,
                    ),
                  ),
                ),
                const SizedBox(height: 24),
                Text(
                  track.title,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: aurora.textPrimary,
                    fontSize: 22,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  track.author,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: aurora.textSecondary, fontSize: 15),
                ),

                // ─── Metadata row — only shows fields that actually
                // exist. No "Unknown" placeholders for data we don't
                // have (releaseYear doesn't exist anywhere in the
                // schema/engines, so it's simply never rendered).
                const SizedBox(height: 12),
                Wrap(
                  alignment: WrapAlignment.center,
                  spacing: 12,
                  runSpacing: 4,
                  children: [
                    if (meta?.albumName != null)
                      _MetaChip(label: meta!.albumName!, icon: Icons.album),
                    if (track.duration != null)
                      _MetaChip(
                        label: _formatDuration(track.duration!),
                        icon: Icons.schedule,
                      ),
                    if (data.stats.playCount > 0)
                      _MetaChip(
                        label: '${data.stats.playCount} plays',
                        icon: Icons.play_circle_outline,
                      ),
                  ],
                ),

                const SizedBox(height: 28),

                // ─── Primary actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    _PrimaryPlayButton(onTap: _play),
                    const SizedBox(width: 16),
                    _ActionIconButton(
                      icon: data.isFavorite ? Icons.favorite : Icons.favorite_border,
                      color: data.isFavorite ? aurora.primary : aurora.textSecondary,
                      onTap: _toggleFavorite,
                      tooltip: 'Favorite',
                    ),
                    const SizedBox(width: 12),
                    _ActionIconButton(
                      icon: Icons.playlist_add,
                      color: aurora.textSecondary,
                      onTap: _addToQueue,
                      tooltip: 'Add to queue',
                    ),
                    const SizedBox(width: 12),
                    _ActionIconButton(
                      icon: Icons.library_add,
                      color: aurora.textSecondary,
                      onTap: _showAddToPlaylist,
                      tooltip: 'Add to playlist',
                    ),
                    const SizedBox(width: 12),
                    _ActionIconButton(
                      icon: Icons.share,
                      color: aurora.textSecondary,
                      // ⚠️ Share (QR/deep-link) is Phase 7+ scope —
                      // wiring the button now, actual share_service.dart
                      // doesn't exist yet. No-op until then.
                      onTap: () {},
                      tooltip: 'Share',
                    ),
                  ],
                ),

                // ─── Go To Album / Go To Artist — only rendered if the
                // data actually exists (albumId requires the pending
                // schema migration; artistId is already in Songs from
                // Phase 0.9 but may still be null for older rows).
                if (meta?.albumId != null || meta?.artistId != null) ...[
                  const SizedBox(height: 20),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      if (meta?.albumId != null)
                        TextButton.icon(
                          onPressed: _goToAlbum,
                          icon: Icon(Icons.album, size: 16, color: aurora.primary),
                          label: Text('Go to Album', style: TextStyle(color: aurora.primary)),
                        ),
                      if (meta?.albumId != null && meta?.artistId != null)
                        const SizedBox(width: 8),
                      if (meta?.artistId != null)
                        TextButton.icon(
                          onPressed: _goToArtist,
                          icon: Icon(Icons.person, size: 16, color: aurora.primary),
                          label: Text('Go to Artist', style: TextStyle(color: aurora.primary)),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),

        // ─── Related content — More From Artist / Similar Songs /
        // Recommended Next. Per roadmap, "Similar Songs"/"Recommended
        // Next" require the Phase 7+ recommendation engine — not built
        // yet. "More From Artist" is queryable NOW if artistId exists
        // (Songs.artistId, Phase 0.9), so only that section renders;
        // the other two are simply omitted rather than shown empty or
        // faked, consistent with how this screen treats every other
        // not-yet-available field.
        if (meta?.artistId != null)
          SliverToBoxAdapter(
            child: _MoreFromArtistSection(artistId: meta!.artistId!),
          ),

        const SliverToBoxAdapter(child: SizedBox(height: 32)),
      ],
    );
  }

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes;
    final seconds = d.inSeconds % 60;
    return '$minutes:${seconds.toString().padLeft(2, '0')}';
  }
}

/// Bundles everything this screen needs after the parallel loads finish.
class SongDetailsData {
  final SearchResult track;
  final SongMetadata? metadata;
  final BehaviourStats stats;
  final bool isFavorite;

  const SongDetailsData({
    required this.track,
    required this.metadata,
    required this.stats,
    required this.isFavorite,
  });

  SongDetailsData copyWith({bool? isFavorite}) => SongDetailsData(
        track: track,
        metadata: metadata,
        stats: stats,
        isFavorite: isFavorite ?? this.isFavorite,
      );
}

// ─────────────────────────────────────────────────────────────────────
// Small presentational widgets — kept local to this file since they're
// not (yet) reused elsewhere. If Album/Artist/Playlist Details end up
// wanting the same chip/button styles, extract then (per WORKFLOW RULES
// — don't invent a shared widget preemptively).
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

class _PrimaryPlayButton extends StatelessWidget {
  const _PrimaryPlayButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Material(
      color: aurora.primary,
      shape: const CircleBorder(),
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: const Padding(
          padding: EdgeInsets.all(16),
          child: Icon(Icons.play_arrow, color: Colors.white, size: 28),
        ),
      ),
    );
  }
}

class _ActionIconButton extends StatelessWidget {
  const _ActionIconButton({
    required this.icon,
    required this.color,
    required this.onTap,
    required this.tooltip,
  });
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final String tooltip;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color),
      onPressed: onTap,
      tooltip: tooltip,
    );
  }
}

class _MoreFromArtistSection extends ConsumerWidget {
  const _MoreFromArtistSection({required this.artistId});
  final String artistId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    // ⚠️ Deliberately NOT implemented in this batch — needs
    // LibraryRepository.getSongsByArtist(artistId) which doesn't exist
    // yet (only getMostPlayed/getRecentlyPlayed/getCachedSongs exist).
    // Rendering the section header now (matches Song Details Screen's
    // spec — "Related Content: More From Artist") with a placeholder,
    // to be filled when Artist Page's query layer is built (next step
    // per the locked order). Avoids inventing a query here that Artist
    // Page will need to duplicate/reconcile against later.
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'More from this artist',
            style: TextStyle(color: aurora.textPrimary, fontSize: 15, fontWeight: FontWeight.w600),
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