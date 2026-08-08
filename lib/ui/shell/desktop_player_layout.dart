import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/playback/playback_engine.dart';
import '../../models/now_playing_model.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/cached_artwork.dart';
import '../../widgets/glass_container.dart';
import '../../widgets/player/player_artwork.dart';
import '../../widgets/player/player_controls.dart';
import '../../widgets/player/player_metadata.dart';
import '../../widgets/player/player_progress_bar.dart';

/// Phase 6 Batch 4 — replaces single-column MusicPlayerScreen body on
/// DesktopShell. Left: artwork+metadata+controls+progress+volume.
/// Right: queue list. "Add to playlist" sheet callback still routed
/// up via [onAddToPlaylist] (DesktopShell/caller decides sheet vs
/// popover presentation).
class DesktopPlayerLayout extends ConsumerWidget {
  const DesktopPlayerLayout({super.key, required this.onAddToPlaylist});

  final ValueChanged<SearchResult> onAddToPlaylist;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final repo = ref.watch(musicPlayerRepositoryProvider);

    final currentTrack = ref.watch(currentTrackProvider).value;
    final queue = ref.watch(queueProvider).value ?? const [];
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playbackDurationProvider).value;
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final isBuffering = ref.watch(playbackBufferingProvider).value ?? false;
    final isResolving = ref.watch(isResolvingProvider).value ?? false;
    final shuffleEnabled = ref.watch(shuffleEnabledProvider).value ?? false;
    final repeatMode = ref.watch(repeatModeProvider).value ?? PlaybackRepeatMode.off;
    final playbackSpeed = ref.watch(playbackSpeedProvider).value ?? 1.0;
    final sleepTimerState = ref.watch(sleepTimerProvider).value ?? SleepTimerState.inactive;
    final volume = ref.watch(volumeProvider).value ?? 100.0;

    if (currentTrack == null) {
      return Center(
        child: Text('Nothing playing', style: TextStyle(color: aurora.textSecondary)),
      );
    }

    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          flex: 3,
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                PlayerArtwork(trackId: currentTrack.videoId, imageUrl: currentTrack.thumbnail, size: 280),
                const SizedBox(height: 20),
                PlayerMetadata(track: currentTrack, onAddToPlaylist: onAddToPlaylist),
                const SizedBox(height: 16),
                PlayerProgressBar(position: position, duration: duration, onSeek: repo.seek),
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
                  onShowSpeedPicker: () {},
                  onShowSleepTimerSheet: () {},
                  onPrevious: repo.previous,
                  onTogglePause: repo.togglePause,
                  onNext: repo.next,
                ),
                const SizedBox(height: 16),
                _VolumeRow(volume: volume, isMuted: repo.isMuted, repo: repo),
              ],
            ),
          ),
        ),
        VerticalDivider(width: 1, color: aurora.glassBorder),
        Expanded(
          flex: 2,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Queue', style: TextStyle(color: aurora.textPrimary, fontSize: 16, fontWeight: FontWeight.bold)),
                const SizedBox(height: 12),
                Expanded(
                  child: queue.isEmpty
                      ? Center(child: Text('Queue empty', style: TextStyle(color: aurora.textSecondary)))
                      : ListView.builder(
                          itemCount: queue.length,
                          itemBuilder: (context, index) {
                            final t = queue[index];
                            final isCurrent = t.videoId == currentTrack.videoId;
                            return ListTile(
                              dense: true,
                              selected: isCurrent,
                              selectedTileColor: aurora.primary.withOpacity(0.08),
                              leading: CachedArtwork(
                                imageUrl: t.thumbnail,
                                cacheKey: t.videoId,
                                width: 36,
                                height: 36,
                                borderRadius: BorderRadius.circular(4),
                                memCacheWidth: 72,
                                memCacheHeight: 72,
                                placeholderIcon: Icons.music_note,
                              ),
                              title: Text(
                                t.title,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  color: isCurrent ? aurora.primary : aurora.textPrimary,
                                  fontSize: 13,
                                ),
                              ),
                              subtitle: Text(t.author, maxLines: 1, overflow: TextOverflow.ellipsis,
                                  style: TextStyle(color: aurora.textSecondary, fontSize: 11)),
                              onTap: () => repo.playFromQueue(index),
                            );
                          },
                        ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _VolumeRow extends StatelessWidget {
  const _VolumeRow({required this.volume, required this.isMuted, required this.repo});

  final double volume;
  final bool isMuted;
  final dynamic repo;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Row(
      children: [
        IconButton(
          icon: Icon(
            isMuted || volume == 0 ? Icons.volume_off : (volume < 50 ? Icons.volume_down : Icons.volume_up),
            color: aurora.textSecondary,
            size: 20,
          ),
          onPressed: repo.toggleMute,
        ),
        Expanded(
          child: Slider(
            value: volume.clamp(0.0, 100.0),
            min: 0,
            max: 100,
            activeColor: aurora.effectiveAccent,
            inactiveColor: aurora.surfaceRaised,
            onChanged: (v) => repo.setVolume(v),
          ),
        ),
      ],
    );
  }
}