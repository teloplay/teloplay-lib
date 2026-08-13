import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../core/playback/playback_engine.dart';
import '../models/now_playing_model.dart';

import '../providers/library_provider.dart';
import '../providers/music_player_provider.dart';
import '../providers/search_provider.dart';
import '../widgets/cached_artwork.dart';
import '../widgets/glass_container.dart';
import '../widgets/player/player_artwork.dart';
import '../widgets/player/player_controls.dart';
import '../widgets/player/player_metadata.dart';
import '../widgets/player/player_progress_bar.dart';
import '../widgets/playlist/add_to_playlist_sheet.dart';
import '../core/theme/app_theme_extension.dart';
import 'library/library_screen.dart';

class MusicPlayerScreen extends ConsumerStatefulWidget {
  // Phase 6 — Desktop Navigation Rule: sidebar-এ থাকা destination
  // (Library/Settings) header-এ duplicate করা হবে না। MobileShell
  // default true পাঠায় (header icons দেখাবে), DesktopShell false
  // পাঠায় (sidebar-ই single source of navigation truth)। এই screen
  // নিজে Platform check করে না — platform সিদ্ধান্ত shell-এর কাজ,
  // এই widget শুধু বলা কথা মেনে চলে (single responsibility)।
  const MusicPlayerScreen({super.key, this.showHeaderNavIcons = true});

  final bool showHeaderNavIcons;

  @override
  ConsumerState<MusicPlayerScreen> createState() => _MusicPlayerScreenState();
}

class _MusicPlayerScreenState extends ConsumerState<MusicPlayerScreen> {
  final _searchController = TextEditingController();
  final _focusNode = FocusNode();

  bool _searchFocused = false;
  bool _searchSubmitted = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(() {
      setState(() => _searchFocused = _focusNode.hasFocus);
    });

    // Bug fix — structured PlaybackError শোনা, non-blocking snackbar
    // দেখানো। addPostFrameCallback দিয়ে wrap করা হচ্ছে যাতে build()-এর
    // আগে ref ব্যবহার নিরাপদ থাকে।
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(musicPlayerRepositoryProvider).playbackErrorStream.listen((error) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(error.message),
            duration: const Duration(seconds: 3),
            behavior: SnackBarBehavior.floating,
          ),
        );
      });
    });
  }

  @override
  void dispose() {
    _searchController.dispose();
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _play(SearchResult track) async {
    try {
      setState(() => _error = null);
      await ref.read(musicPlayerRepositoryProvider).playVideoId(
        track.videoId,
        trackInfo: track,
      );
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  void _selectRecentSearch(String query) {
    _searchController.text = query;
    _searchController.selection = TextSelection.fromPosition(
      TextPosition(offset: query.length),
    );

    setState(() {
      _searchFocused = false;
      _searchSubmitted = true;
    });
    _focusNode.unfocus();

    ref.read(searchControllerProvider.notifier).search(query);
    ref.read(suggestionControllerProvider.notifier).clear();
  }

  void _selectSuggestion(String suggestion) => _selectRecentSearch(suggestion);

  static const _speedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

  void _showSpeedPicker(double currentSpeed) {
    final aurora = context.aurora;
    showModalBottomSheet(
      context: context,
      backgroundColor: aurora.surfaceElevated,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Playback Speed',
                  style: TextStyle(
                    color: aurora.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              ..._speedPresets.map((speed) {
                final isSelected = speed == currentSpeed;
                return ListTile(
                  title: Text(
                    '${speed}x',
                    style: TextStyle(
                      color: isSelected ? aurora.primary : aurora.textPrimary,
                      fontWeight:
                          isSelected ? FontWeight.bold : FontWeight.normal,
                    ),
                  ),
                  trailing: isSelected
                      ? Icon(Icons.check, color: aurora.primary)
                      : null,
                  onTap: () {
                    ref
                        .read(musicPlayerRepositoryProvider)
                        .setPlaybackSpeed(speed);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  static const _sleepTimerPresets = [
    Duration(minutes: 5),
    Duration(minutes: 15),
    Duration(minutes: 30),
    Duration(minutes: 45),
    Duration(minutes: 60),
  ];

  void _showSleepTimerSheet(SleepTimerState currentState) {
    final aurora = context.aurora;
    showModalBottomSheet(
      context: context,
      backgroundColor: aurora.surfaceElevated,
      builder: (context) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16),
                child: Text(
                  'Sleep Timer',
                  style: TextStyle(
                    color: aurora.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              if (currentState.isActive)
                ListTile(
                  leading: Icon(Icons.timer_off, color: aurora.error),
                  title: Text(
                    'Timer Off',
                    style: TextStyle(color: aurora.error),
                  ),
                  onTap: () {
                    ref.read(musicPlayerRepositoryProvider).cancelSleepTimer();
                    Navigator.pop(context);
                  },
                ),
              ..._sleepTimerPresets.map((duration) {
                return ListTile(
                  title: Text(
                    '${duration.inMinutes} Minutes',
                    style: TextStyle(color: aurora.textPrimary),
                  ),
                  onTap: () {
                    ref
                        .read(musicPlayerRepositoryProvider)
                        .startSleepTimer(duration);
                    Navigator.pop(context);
                  },
                );
              }),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
    );
  }

  /// "Add to Playlist" bottom sheet
  void _showAddToPlaylistSheet(SearchResult track) {
    AddToPlaylistSheet.show(
      context: context,
      track: track,
    );
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final repo = ref.watch(musicPlayerRepositoryProvider);

    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final isBuffering = ref.watch(playbackBufferingProvider).value ?? false;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playbackDurationProvider).value;

    final currentTrack = ref.watch(currentTrackProvider).value;
    final queue = ref.watch(queueProvider).value ?? const [];

    final isResolving = ref.watch(isResolvingProvider).value ?? false;

    final searchState = ref.watch(searchControllerProvider);
    // FIX: SearchState has .songs, not .results
    final searchResults = searchState.songs;

    final suggestionState = ref.watch(suggestionControllerProvider);

    final shuffleEnabled = ref.watch(shuffleEnabledProvider).value ?? false;
    final repeatMode = ref.watch(repeatModeProvider).value ?? PlaybackRepeatMode.off;
    final playbackSpeed = ref.watch(playbackSpeedProvider).value ?? 1.0;
    final sleepTimerState =
        ref.watch(sleepTimerProvider).value ?? SleepTimerState.inactive;

    final showRecentSearches =
        _searchFocused && _searchController.text.isEmpty;

    final showSuggestions = _searchFocused &&
        _searchController.text.isNotEmpty &&
        !_searchSubmitted;

    return Scaffold(
      backgroundColor: aurora.background,
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    Text(
                      'TeloPlay',
                      style: TextStyle(
                        color: aurora.primary,
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const Spacer(),
                    if (queue.isNotEmpty)
                      Text(
                        '${queue.length} in queue',
                        style: TextStyle(color: aurora.textSecondary, fontSize: 12),
                      ),
                    if (widget.showHeaderNavIcons) ...[
                      IconButton(
                        icon: Icon(Icons.library_music_outlined,
                            color: aurora.textSecondary),
                        tooltip: 'Library',
                        onPressed: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => const LibraryScreen(),
                            ),
                          );
                        },
                      ),
                      IconButton(
                        icon: Icon(Icons.settings_outlined,
                            color: aurora.textSecondary),
                        tooltip: 'Settings',
                        onPressed: () {
                          context.push('/settings');
                        },
                      ),
                    ],
                  ],
                ),
              ),

              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  controller: _searchController,
                  focusNode: _focusNode,
                  style: TextStyle(color: aurora.textPrimary),
                  onTapOutside: (_) {},
                  decoration: InputDecoration(
                    hintText: 'Search songs, artists, albums...',
                    hintStyle: TextStyle(color: aurora.textDisabled),
                    prefixIcon: Icon(Icons.search, color: aurora.textSecondary),
                    suffixIcon: searchState.isLoading
                        ? Padding(
                            padding: const EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: aurora.primary,
                              ),
                            ),
                          )
                        : _searchController.text.isNotEmpty
                            ? IconButton(
                                icon: Icon(Icons.clear, color: aurora.textSecondary),
                                onPressed: () {
                                  _searchController.clear();
                                  ref.read(searchControllerProvider.notifier).clear();
                                  ref.read(suggestionControllerProvider.notifier).clear();
                                  setState(() => _searchSubmitted = false);
                                },
                              )
                            : null,
                    filled: true,
                    fillColor: aurora.surfaceRaised,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: aurora.primary, width: 1),
                    ),
                  ),
                  onChanged: (value) {
                    setState(() {
                      _searchSubmitted = false;
                    });
                    ref.read(searchControllerProvider.notifier).onQueryChanged(value);
                    ref.read(suggestionControllerProvider.notifier).onQueryChanged(value);
                  },
                  onSubmitted: (value) {
                    setState(() => _searchSubmitted = true);
                    ref.read(searchControllerProvider.notifier).search(value);
                    ref.read(suggestionControllerProvider.notifier).clear();
                  },
                ),
              ),

              if (showRecentSearches)
                Consumer(
                  builder: (context, ref, _) {
                    final recentAsync = ref.watch(recentSearchesProvider);
                    return recentAsync.when(
                      data: (recent) {
                        if (recent.isEmpty) return const SizedBox.shrink();
                        return Padding(
                          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'Recent searches',
                                style: TextStyle(
                                  color: aurora.textSecondary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: recent.map((r) {
                                  // FIX: r is String (RecentSearch = String), not an object with .query
                                  final query = r;
                                  final chip = InkWell(
                                    borderRadius: BorderRadius.circular(20),
                                    onTap: () => _selectRecentSearch(query),
                                    child: Container(
                                      padding: const EdgeInsets.only(
                                        left: 14,
                                        right: 26,
                                        top: 8,
                                        bottom: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: aurora.surfaceRaised,
                                        borderRadius: BorderRadius.circular(20),
                                      ),
                                      child: Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(Icons.history,
                                              size: 14, color: aurora.textSecondary),
                                          const SizedBox(width: 6),
                                          Text(
                                            query,
                                            style: TextStyle(
                                              color: aurora.textPrimary,
                                              fontSize: 13,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  );

                                  final chipWithDelete = Stack(
                                    clipBehavior: Clip.none,
                                    children: [
                                      chip,
                                      Positioned(
                                        right: 4,
                                        top: 0,
                                        bottom: 0,
                                        child: Center(
                                          child: InkWell(
                                            borderRadius: BorderRadius.circular(12),
                                            onTap: () async {
                                              _focusNode.requestFocus();
                                              setState(() => _searchFocused = true);

                                              await ref
                                                  .read(searchHistoryRepositoryProvider)
                                                  .removeSearch(query);
                                              ref.invalidate(recentSearchesProvider);
                                            },
                                            child: Padding(
                                              padding: const EdgeInsets.all(4),
                                              child: Icon(
                                                Icons.close,
                                                size: 14,
                                                color: aurora.textSecondary,
                                              ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  );
                                  return chipWithDelete;
                                }).toList(),
                              ),
                            ],
                          ),
                        );
                      },
                      loading: () => const SizedBox.shrink(),
                      error: (_, __) => const SizedBox.shrink(),
                    );
                  },
                ),

              if (showSuggestions)
                Builder(
                  builder: (context) {
                    if (suggestionState.suggestions.isEmpty &&
                        !suggestionState.isLoading) {
                      return const SizedBox.shrink();
                    }
                    return Container(
                      margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                      decoration: BoxDecoration(
                        color: aurora.surfaceElevated,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (suggestionState.isLoading &&
                              suggestionState.suggestions.isEmpty)
                            Padding(
                              padding: const EdgeInsets.symmetric(vertical: 16),
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: aurora.primary,
                                ),
                              ),
                            )
                          else
                            ListView.separated(
                              shrinkWrap: true,
                              physics: const NeverScrollableScrollPhysics(),
                              itemCount: suggestionState.suggestions.length,
                              separatorBuilder: (_, __) => Divider(
                                height: 1,
                                color: aurora.surface,
                              ),
                              itemBuilder: (context, index) {
                                final suggestion = suggestionState.suggestions[index];
                                return InkWell(
                                  onTap: () => _selectSuggestion(suggestion),
                                  child: Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 14,
                                      vertical: 12,
                                    ),
                                    child: Row(
                                      children: [
                                        Icon(Icons.search,
                                            size: 16, color: aurora.textSecondary),
                                        const SizedBox(width: 10),
                                        Expanded(
                                          child: Text(
                                            suggestion,
                                            style: TextStyle(
                                              color: aurora.textPrimary,
                                              fontSize: 14,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                );
                              },
                            ),
                        ],
                      ),
                    );
                  },
                ),

              if (_error != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: aurora.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: aurora.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          _error!.length > 100 ? '${_error!.substring(0, 100)}...' : _error!,
                          style: TextStyle(color: aurora.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              if (searchState.error != null)
                Container(
                  margin: const EdgeInsets.all(16),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: aurora.error.withOpacity(0.15),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.error_outline, color: aurora.error, size: 20),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          searchState.error!.length > 100
                              ? '${searchState.error!.substring(0, 100)}...'
                              : searchState.error!,
                          style: TextStyle(color: aurora.error, fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ),

              if (currentTrack != null)
                Consumer(
                  builder: (context, ref, _) {
                    final aurora = context.aurora;
                    final accent = aurora.effectiveAccent;

                    return GestureDetector(
                      onHorizontalDragEnd: (details) {
                        final velocity = details.primaryVelocity ?? 0;
                        if (velocity < -250) {
                          ref.read(musicPlayerRepositoryProvider).next();
                        } else if (velocity > 250) {
                          ref.read(musicPlayerRepositoryProvider).previous();
                        }
                      },
                      onDoubleTap: () {
                        ref.read(libraryRepositoryProvider).toggleFavorite(
                              songId: currentTrack.videoId,
                              title: currentTrack.title,
                              author: currentTrack.author,
                              thumbnail: currentTrack.thumbnail,
                              durationSeconds: currentTrack.duration?.inSeconds,
                            );
                      },
                      child: GlassContainer(
                        margin: const EdgeInsets.all(16),
                        padding: const EdgeInsets.all(16),
                        borderRadius: BorderRadius.circular(20),
                        glowColor: accent,
                        glowOpacity: 0.22,
                        child: Column(
                          children: [
                            PlayerArtwork(
                              trackId: currentTrack.videoId,
                              imageUrl: currentTrack.thumbnail,
                              size: 250,
                            ),
                            const SizedBox(height: 16),
                            PlayerMetadata(
                              track: currentTrack,
                              onAddToPlaylist: _showAddToPlaylistSheet,
                            ),
                            const SizedBox(height: 16),
                            PlayerProgressBar(
                              position: position,
                              duration: duration,
                              onSeek: repo.seek,
                            ),
                            const SizedBox(height: 8),
                            PlayerControls(
                              shuffleEnabled: shuffleEnabled,
                              repeatMode: repeatMode,
                              playbackSpeed: playbackSpeed,
                              sleepTimerState: sleepTimerState,
                              isPlaying: isPlaying,
                              isBuffering: isBuffering,
                              isResolving: isResolving,
                              onToggleShuffle: () =>
                                  repo.setShuffleEnabled(!shuffleEnabled),
                              onCycleRepeat: repo.cycleRepeatMode,
                              onShowSpeedPicker: () =>
                                  _showSpeedPicker(playbackSpeed),
                              onShowSleepTimerSheet: () =>
                                  _showSleepTimerSheet(sleepTimerState),
                              onPrevious: repo.previous,
                              onTogglePause: repo.togglePause,
                              onNext: repo.next,
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),

              if (searchResults.isNotEmpty)
                ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: searchResults.length,
                  itemBuilder: (context, index) {
                    final track = searchResults[index];
                    return ListTile(
                      leading: CachedArtwork(
                        imageUrl: track.thumbnail,
                        width: 48,
                        height: 48,
                        borderRadius: BorderRadius.circular(4),
                        memCacheWidth: 96,
                        memCacheHeight: 96,
                        placeholderIcon: Icons.music_note,
                      ),
                      title: Text(
                        track.title,
                        style: TextStyle(color: aurora.textPrimary, fontSize: 14),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      subtitle: Text(
                        track.author,
                        style: TextStyle(color: aurora.textSecondary, fontSize: 12),
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(Icons.playlist_add, color: aurora.textSecondary, size: 20),
                            onPressed: () => repo.addToQueue(track),
                          ),
                          IconButton(
                            icon: Icon(Icons.play_arrow, color: aurora.primary, size: 20),
                            onPressed: () => ref.read(musicPlayerRepositoryProvider).playFromContext(
                              tracks: searchResults,
                              startIndex: index,
                              source: QueueSource.search,
                            ),
                          ),
                        ],
                      ),
                    );
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }
}