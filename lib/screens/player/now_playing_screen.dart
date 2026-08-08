import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../models/now_playing_model.dart';
import '../../providers/album_accent_provider.dart';
import '../../providers/library_provider.dart';
import '../../providers/music_player_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/player/player_artwork.dart';
import '../../widgets/player/player_controls.dart';
import '../../widgets/player/player_metadata.dart';
import '../../widgets/player/player_progress_bar.dart';
import '../../widgets/player/speed_sleep_sheets.dart';
import '../../widgets/playlist/add_to_playlist_sheet.dart';

/// Phase 6.5 Batch 5 — real NowPlayingScreen (replaces the previous
/// thin `MusicPlayerScreen(showHeaderNavIcons: false)` wrapper).
///
/// This is the Hero-morph destination for both `FloatingMiniPlayer`
/// (mobile + the old desktop temp bar) and `DesktopBottomPlayerBar`
/// (new desktop persistent bar) — tag `'player-artwork-<trackId>'`
/// matches `PlayerArtwork`'s Hero (added this same batch).
///
/// Deliberately does NOT include:
/// - Search bar / recent-search chips / suggestions (stays in
///   MusicPlayerScreen for now — MusicPlayerScreen is still reachable
///   via legacy paths but is no longer the primary player surface).
/// - Any navigation-tab chrome (Library/Settings icons) — this is an
///   overlay route, not a shell tab (per Phase 6.5 navigation
///   reframing: Player is no longer a nav destination).
///
/// Swipe-down-to-dismiss included for touch/mobile parity with the
/// mini-player's swipe-up-to-expand gesture.
class NowPlayingScreen extends ConsumerWidget {
  const NowPlayingScreen({super.key});

  /// Same "Add to Playlist" bottom-sheet pattern as
  /// `MusicPlayerScreen._showAddToPlaylistSheet` — duplicated here
  /// deliberately rather than extracted into a shared service in this
  /// batch (scope: NowPlayingScreen + desktop bar, not a playlist-sheet
  /// refactor). Candidate for a future `widgets/playlist/` extraction
  /// if a third call site appears.
  void _showAddToPlaylistSheet(BuildContext context, WidgetRef ref, SearchResult track) {
    AddToPlaylistSheet.show(
      context: context,
      track: track,
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final repo = ref.watch(musicPlayerRepositoryProvider);

    final currentTrack = ref.watch(currentTrackProvider).value;
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final isBuffering = ref.watch(playbackBufferingProvider).value ?? false;
    final isResolving = ref.watch(isResolvingProvider).value ?? false;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playbackDurationProvider).value;
    final shuffleEnabled = ref.watch(shuffleEnabledProvider).value ?? false;
    final repeatMode = ref.watch(repeatModeProvider).value ?? PlaybackRepeatMode.off;
    final playbackSpeed = ref.watch(playbackSpeedProvider).value ?? 1.0;
    final sleepTimerState = ref.watch(sleepTimerProvider).value ?? SleepTimerState.inactive;
    final accentState = ref.watch(albumAccentProvider);
    final accent = accentState.accentColor ?? aurora.primary;

    if (currentTrack == null) {
      // Nothing playing — shouldn't normally be reachable (mini-player
      // hides itself when currentTrack is null, so there's no tap
      // target to get here), but guard anyway in case of direct
      // deep-link / back-navigation edge cases.
      return Scaffold(
        backgroundColor: aurora.background,
        appBar: AppBar(
          backgroundColor: Colors.transparent,
          elevation: 0,
          leading: IconButton(
            icon: Icon(Icons.keyboard_arrow_down, color: aurora.textPrimary),
            onPressed: () => Navigator.of(context).maybePop(),
          ),
        ),
        body: Center(
          child: Text('Nothing playing', style: TextStyle(color: aurora.textSecondary)),
        ),
      );
    }

    return Scaffold(
      backgroundColor: aurora.background,
      body: SafeArea(
        child: GestureDetector(
          onVerticalDragEnd: (details) {
            if ((details.primaryVelocity ?? 0) > 250) {
              Navigator.of(context).maybePop();
            }
          },
          onHorizontalDragEnd: (details) {
            final velocity = details.primaryVelocity ?? 0;
            if (velocity < -250) {
              repo.next();
            } else if (velocity > 250) {
              repo.previous();
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
          child: Column(
            children: [
              // Collapse handle / back affordance
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    IconButton(
                      icon: Icon(Icons.keyboard_arrow_down, color: aurora.textPrimary),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SizedBox(height: 16),
                      GlassContainer(
                        padding: const EdgeInsets.all(20),
                        borderRadius: BorderRadius.circular(24),
                        glowColor: accent,
                        glowOpacity: 0.22,
                        child: Column(
                          children: [
                            PlayerArtwork(
                              trackId: currentTrack.videoId,
                              imageUrl: currentTrack.thumbnail,
                              size: 280,
                            ),
                            const SizedBox(height: 20),
                            PlayerMetadata(
                              track: currentTrack,
                              onAddToPlaylist: (track) =>
                                  _showAddToPlaylistSheet(context, ref, track),
                            ),
                            const SizedBox(height: 20),
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
                              onToggleShuffle: () => repo.setShuffleEnabled(!shuffleEnabled),
                              onCycleRepeat: repo.cycleRepeatMode,
                              onShowSpeedPicker: () =>
                                  showSpeedPickerSheet(context, ref, playbackSpeed),
                              onShowSleepTimerSheet: () =>
                                  showSleepTimerSheet(context, ref, sleepTimerState),
                              onPrevious: repo.previous,
                              onTogglePause: repo.togglePause,
                              onNext: repo.next,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}