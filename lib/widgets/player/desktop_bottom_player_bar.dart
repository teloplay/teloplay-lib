import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/library_provider.dart';
import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../models/now_playing_model.dart';
import '../../providers/album_accent_provider.dart';
import '../../providers/music_player_provider.dart';
import '../cached_artwork.dart';
import '../player/speed_sleep_sheets.dart';

/// Phase 6.5 — Spotify-style Desktop player bar.
/// 3-column single row: [artwork+meta] [transport+progress] [utility+volume]
class DesktopBottomPlayerBar extends ConsumerWidget {
  const DesktopBottomPlayerBar({
    super.key,
    required this.onAddToPlaylist,
    required this.isQueuePanelVisible,
    required this.onToggleQueuePanel,
    this.onShowSpeedPicker,
    this.onExpand,
  });

  final ValueChanged<SearchResult> onAddToPlaylist;
  final bool isQueuePanelVisible;
  final VoidCallback onToggleQueuePanel;
  final VoidCallback? onShowSpeedPicker;
  final VoidCallback? onExpand;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final repo = ref.watch(musicPlayerRepositoryProvider);

    final track = ref.watch(currentTrackProvider).value;
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final isBuffering = ref.watch(playbackBufferingProvider).value ?? false;
    final isResolving = ref.watch(isResolvingProvider).value ?? false;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playbackDurationProvider).value;
    final shuffleEnabled = ref.watch(shuffleEnabledProvider).value ?? false;
    final repeatMode = ref.watch(repeatModeProvider).value ?? PlaybackRepeatMode.off;
    final volume = ref.watch(volumeProvider).value ?? 100.0;
    final accentState = ref.watch(albumAccentProvider);
    final accent = accentState.accentColor ?? aurora.primary;
    final isFav = track == null
        ? false
        : ref.watch(isFavoriteProvider(track.videoId));

    if (track == null) {
      return Container(
        height: 78,
        color: aurora.surface,
        alignment: Alignment.center,
        child: Text('Nothing playing', style: TextStyle(color: aurora.textSecondary)),
      );
    }

    return Container(
      height: 78,
      decoration: BoxDecoration(
        color: aurora.surface,
        border: Border(top: BorderSide(color: aurora.glassBorder, width: 1)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        children: [
          // ── LEFT: artwork + title/artist + favorite/add ──
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(4),
                  onTap: onExpand,
                  child: CachedArtwork(
                    imageUrl: track.thumbnail,
                    cacheKey: track.videoId,
                    width: 52,
                    height: 52,
                    borderRadius: BorderRadius.circular(4),
                    memCacheWidth: 104,
                    memCacheHeight: 104,
                    placeholderIcon: Icons.music_note,
                  ),
                ),
                const SizedBox(width: 12),
                Flexible(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: aurora.textPrimary,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                          letterSpacing: -0.1,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        track.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: aurora.textSecondary,
                          fontSize: 11,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                _SmallIconButton(
                  icon: isFav ? Icons.favorite : Icons.favorite_border,
                  color: isFav ? accent : aurora.textSecondary,
                  size: 16,
                  onTap: () {
                    ref.read(libraryRepositoryProvider).toggleFavorite(
                          songId: track.videoId,
                          title: track.title,
                          author: track.author,
                          thumbnail: track.thumbnail,
                          durationSeconds: track.duration?.inSeconds,
                        );
                  },
                ),
                _SmallIconButton(
                  icon: Icons.add_circle_outline,
                  color: aurora.textSecondary,
                  size: 16,
                  onTap: () => onAddToPlaylist(track),
                ),
              ],
            ),
          ),

          // ── CENTER: transport controls + progress bar ──
          Expanded(
            flex: 4,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                _TransportControls(
                  isPlaying: isPlaying,
                  isBuffering: isBuffering,
                  isResolving: isResolving,
                  shuffleEnabled: shuffleEnabled,
                  repeatMode: repeatMode,
                  onPrevious: repo.previous,
                  onTogglePause: repo.togglePause,
                  onNext: repo.next,
                  onToggleShuffle: () => repo.setShuffleEnabled(!shuffleEnabled),
                  onCycleRepeat: repo.cycleRepeatMode,
                  aurora: aurora,
                ),
                const SizedBox(height: 6),
                _ProgressRow(
                  position: position,
                  duration: duration,
                  accent: accent,
                  onSeek: repo.seek,
                ),
              ],
            ),
          ),

          // ── RIGHT: utility icons + volume ──
          Expanded(
            flex: 3,
            child: Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                _SmallIconButton(
                  icon: Icons.speed,
                  color: aurora.textSecondary,
                  size: 16,
                  onTap: onShowSpeedPicker,
                ),
                _SmallIconButton(
                  icon: Icons.queue_music,
                  color: isQueuePanelVisible ? accent : aurora.textSecondary,
                  size: 18,
                  onTap: onToggleQueuePanel,
                ),
                const SizedBox(width: 4),
                _VolumeControl(
                  volume: volume,
                  isMuted: repo.isMuted,
                  onToggleMute: repo.toggleMute,
                  onVolumeChange: repo.setVolume,
                  accent: accent,
                  aurora: aurora,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Small circular icon button, Spotify utility-row style
class _SmallIconButton extends StatelessWidget {
  const _SmallIconButton({
    required this.icon,
    required this.color,
    required this.size,
    this.onTap,
  });

  final IconData icon;
  final Color color;
  final double size;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      icon: Icon(icon, color: color, size: size),
      onPressed: onTap,
      constraints: const BoxConstraints(minWidth: 34, minHeight: 34),
      padding: EdgeInsets.zero,
      splashRadius: 20,
    );
  }
}

/// Transport controls row — shuffle, prev, play (filled circle), next, repeat
class _TransportControls extends StatelessWidget {
  const _TransportControls({
    required this.isPlaying,
    required this.isBuffering,
    required this.isResolving,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.onPrevious,
    required this.onTogglePause,
    required this.onNext,
    required this.onToggleShuffle,
    required this.onCycleRepeat,
    required this.aurora,
  });

  final bool isPlaying;
  final bool isBuffering;
  final bool isResolving;
  final bool shuffleEnabled;
  final PlaybackRepeatMode repeatMode;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePause;
  final VoidCallback onNext;
  final VoidCallback onToggleShuffle;
  final VoidCallback onCycleRepeat;
  final dynamic aurora;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        // _TransportControls-এর ভেতরে icon sizes বাড়ান:

_SmallIconButton(
  icon: Icons.shuffle,
  color: shuffleEnabled ? aurora.primary : aurora.textSecondary,
  size: 18,  // was 16
  onTap: onToggleShuffle,
),
_SmallIconButton(
  icon: Icons.skip_previous,
  color: aurora.textPrimary,
  size: 24,  // was 20
  onTap: onPrevious,
),
const SizedBox(width: 6),  // was 4
// Play/Pause circle বড় করুন:
GestureDetector(
  onTap: onTogglePause,
  child: Container(
    width: 38,   // was 32
    height: 38,  // was 32
    decoration: const BoxDecoration(
      shape: BoxShape.circle,
      color: Colors.white,
    ),
    child: isBuffering || isResolving
        ? const Padding(
            padding: EdgeInsets.all(9),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Colors.black,
            ),
          )
        : Icon(
            isPlaying ? Icons.pause : Icons.play_arrow,
            color: Colors.black,
            size: 22,  // was 18
          ),
  ),
),
const SizedBox(width: 6),  // was 4
_SmallIconButton(
  icon: Icons.skip_next,
  color: aurora.textPrimary,
  size: 24,  // was 20
  onTap: onNext,
),
_SmallIconButton(
  icon: repeatMode == PlaybackRepeatMode.one ? Icons.repeat_one : Icons.repeat,
  color: repeatMode != PlaybackRepeatMode.off ? aurora.primary : aurora.textSecondary,
  size: 18,  // was 16
  onTap: onCycleRepeat,
),
      ],
    );
  }
}

/// Progress bar row with time labels either side — Spotify layout
class _ProgressRow extends StatefulWidget {
  const _ProgressRow({
    required this.position,
    required this.duration,
    required this.accent,
    required this.onSeek,
  });

  final Duration position;
  final Duration? duration;
  final Color accent;
  final ValueChanged<Duration> onSeek;

  @override
  State<_ProgressRow> createState() => _ProgressRowState();
}

class _ProgressRowState extends State<_ProgressRow> {
  bool _hovered = false;
  double? _dragRatio;

  // ✅ FIX: New track এ progress reset
  @override
  void didUpdateWidget(covariant _ProgressRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.duration != widget.duration) {
      setState(() => _dragRatio = null);
    }
  }

  String _format(Duration d) {
    final m = d.inMinutes.toString();
    final s = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final dur = widget.duration;

    if (dur == null) {
      return const SizedBox(height: 14);
    }

    final progress = _dragRatio ??
        (dur.inMilliseconds > 0
            ? (widget.position.inMilliseconds / dur.inMilliseconds).clamp(0.0, 1.0)
            : 0.0);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: 36,
          child: Text(
            _format(widget.position),
            textAlign: TextAlign.right,
            style: TextStyle(color: aurora.textSecondary, fontSize: 11),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 360,
          child: MouseRegion(
            onEnter: (_) => setState(() => _hovered = true),
            onExit: (_) => setState(() => _hovered = false),
            child: LayoutBuilder(
              builder: (context, constraints) {
                void seekAt(double dx) {
                  final ratio = (dx / constraints.maxWidth).clamp(0.0, 1.0);
                  setState(() => _dragRatio = ratio);
                  widget.onSeek(Duration(
                    milliseconds: (ratio * dur.inMilliseconds).round(),
                  ));
                }

                return GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTapDown: (d) => seekAt(d.localPosition.dx),
                  onHorizontalDragStart: (d) => seekAt(d.localPosition.dx),
                  onHorizontalDragUpdate: (d) => seekAt(d.localPosition.dx),
                  onHorizontalDragEnd: (_) =>
                      setState(() => _dragRatio = null),
                  child: SizedBox(
                    height: 14,
                    child: Stack(
                      alignment: Alignment.centerLeft,
                      children: [
                        Container(
                          height: _hovered ? 4 : 3,
                          decoration: BoxDecoration(
                            color: aurora.surfaceRaised,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                        FractionallySizedBox(
                          widthFactor: progress,
                          child: Container(
                            height: _hovered ? 4 : 3,
                            decoration: BoxDecoration(
                              color: _hovered ? widget.accent : aurora.textPrimary,
                              borderRadius: BorderRadius.circular(2),
                            ),
                          ),
                        ),
                        if (_hovered)
                          Positioned(
                            left: (progress * constraints.maxWidth) - 5,
                            child: Container(
                              width: 10,
                              height: 20,
                              decoration: const BoxDecoration(
                                color: Colors.white,
                                shape: BoxShape.circle,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 36,
          child: Text(
            _format(dur),
            style: TextStyle(color: aurora.textSecondary, fontSize: 11),
          ),
        ),
      ],
    );
  }
}

/// Volume control with mute icon + slider + mouse-wheel scroll support
class _VolumeControl extends StatefulWidget {
  const _VolumeControl({
    required this.volume,
    required this.isMuted,
    required this.onToggleMute,
    required this.onVolumeChange,
    required this.accent,
    required this.aurora,
  });

  final double volume;
  final bool isMuted;
  final VoidCallback onToggleMute;
  final ValueChanged<double> onVolumeChange;
  final Color accent;
  final dynamic aurora;

  @override
  State<_VolumeControl> createState() => _VolumeControlState();
}

class _VolumeControlState extends State<_VolumeControl> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: Listener(
        onPointerSignal: (event) {
          if (event is PointerScrollEvent) {
            final step = event.scrollDelta.dy > 0 ? -5.0 : 5.0;
            widget.onVolumeChange((widget.volume + step).clamp(0.0, 100.0));
          }
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _SmallIconButton(
              icon: widget.isMuted || widget.volume == 0
                  ? Icons.volume_off
                  : (widget.volume < 50 ? Icons.volume_down : Icons.volume_up),
              color: widget.aurora.textSecondary,
              size: 16,
              onTap: widget.onToggleMute,
            ),
            SizedBox(
              width: 90,
              child: SliderTheme(
                data: SliderTheme.of(context).copyWith(
                  trackHeight: 3,
                  thumbShape: RoundSliderThumbShape(
                    enabledThumbRadius: _hovered ? 5 : 0,
                  ),
                  overlayShape: SliderComponentShape.noOverlay,
                ),
                child: Slider(
                  value: widget.volume.clamp(0.0, 100.0),
                  min: 0,
                  max: 100,
                  activeColor: _hovered ? widget.accent : widget.aurora.textPrimary,
                  inactiveColor: widget.aurora.surfaceRaised,
                  onChanged: widget.onVolumeChange,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}