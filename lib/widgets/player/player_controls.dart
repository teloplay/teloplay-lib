import 'package:flutter/material.dart';

import '../../core/playback/playback_engine.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../models/now_playing_model.dart';

/// ⚠️ Phase 6 — শেয়ার্ড content widget। Shuffle/Repeat/Speed/Sleep-timer
/// row + main transport (prev/play-pause/next) row। Bottom-sheet
/// (speed picker/sleep-timer picker) খোলার callback caller থেকে আসে —
/// এই widget নিজে কোনো `showModalBottomSheet` কল করে না, কারণ Desktop
/// layout ভবিষ্যতে bottom-sheet-এর বদলে popover/inline panel ব্যবহার
/// করতে চাইতে পারে (presentation platform-নির্দিষ্ট, action শেয়ার্ড —
/// দেখো PlayerMetadata-এর একই নীতি)।
class PlayerControls extends StatelessWidget {
  const PlayerControls({
    super.key,
    required this.shuffleEnabled,
    required this.repeatMode,
    required this.playbackSpeed,
    required this.sleepTimerState,
    required this.isPlaying,
    required this.isBuffering,
    required this.isResolving,
    required this.onToggleShuffle,
    required this.onCycleRepeat,
    required this.onShowSpeedPicker,
    required this.onShowSleepTimerSheet,
    required this.onPrevious,
    required this.onTogglePause,
    required this.onNext,
  });

  final bool shuffleEnabled;
  final PlaybackRepeatMode repeatMode;
  final double playbackSpeed;
  final SleepTimerState sleepTimerState;
  final bool isPlaying;
  final bool isBuffering;
  final bool isResolving;

  final VoidCallback onToggleShuffle;
  final VoidCallback onCycleRepeat;
  final VoidCallback onShowSpeedPicker;
  final VoidCallback onShowSleepTimerSheet;
  final VoidCallback onPrevious;
  final VoidCallback onTogglePause;
  final VoidCallback onNext;

  IconData _repeatIcon(PlaybackRepeatMode mode) {
    switch (mode) {
      case PlaybackRepeatMode.one:
        return Icons.repeat_one;
      case PlaybackRepeatMode.all:
      case PlaybackRepeatMode.off:
        return Icons.repeat;
    }
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final accent = aurora.effectiveAccent;

    // ⚠️ Fix — this widget is used both inside a tall column
    // (NowPlayingScreen/mobile) and inside DesktopBottomPlayerBar's
    // tight ~56-64px-tall slot. LayoutBuilder branches on available
    // height: below ~90px (desktop bottom bar) → compact single-row
    // layout (transport controls only, shuffle/repeat/speed/sleep-timer
    // become smaller icon-only buttons inline with transport, sleep
    // countdown text dropped — DesktopBottomPlayerBar has no room for
    // it and the sleep-timer sheet itself still shows the countdown).
    // Above ~90px (NowPlayingScreen/mobile) → original two-row layout,
    // completely unchanged behavior/spacing from before this patch.
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 90;

        if (compact) {
          return Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              IconButton(
                iconSize: 18,
                icon: Icon(Icons.shuffle,
                    color: shuffleEnabled ? accent : aurora.textSecondary),
                tooltip: 'Shuffle',
                onPressed: onToggleShuffle,
              ),
              IconButton(
                iconSize: 26,
                icon: Icon(Icons.skip_previous, color: aurora.textPrimary),
                onPressed: onPrevious,
              ),
              SizedBox(
                width: 40,
                height: 40,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    if (isResolving)
                      SizedBox(
                        width: 40,
                        height: 40,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: accent,
                        ),
                      ),
                    Container(
                      width: 36,
                      height: 36,
                      decoration: BoxDecoration(color: accent, shape: BoxShape.circle),
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        iconSize: 20,
                        icon: Icon(
                          isBuffering
                              ? Icons.hourglass_top
                              : isPlaying
                                  ? Icons.pause
                                  : Icons.play_arrow,
                          color: aurora.background,
                        ),
                        onPressed: onTogglePause,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                iconSize: 26,
                icon: Icon(Icons.skip_next, color: aurora.textPrimary),
                onPressed: onNext,
              ),
              IconButton(
                iconSize: 18,
                icon: Icon(
                  _repeatIcon(repeatMode),
                  color: repeatMode == PlaybackRepeatMode.off
                      ? aurora.textSecondary
                      : accent,
                ),
                tooltip: 'Repeat',
                onPressed: onCycleRepeat,
              ),
            ],
          );
        }

        // ── Original tall layout — unchanged ──
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceEvenly,
              children: [
                IconButton(
                  icon: Icon(
                    Icons.shuffle,
                    color: shuffleEnabled ? accent : aurora.textSecondary,
                    size: 20,
                  ),
                  tooltip: 'Shuffle',
                  onPressed: onToggleShuffle,
                ),
                IconButton(
                  icon: Icon(
                    _repeatIcon(repeatMode),
                    color: repeatMode == PlaybackRepeatMode.off
                        ? aurora.textSecondary
                        : accent,
                    size: 20,
                  ),
                  tooltip: 'Repeat',
                  onPressed: onCycleRepeat,
                ),
                IconButton(
                  icon: Text(
                    '${playbackSpeed}x',
                    style: TextStyle(
                      color: playbackSpeed != 1.0 ? accent : aurora.textSecondary,
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  tooltip: 'Playback speed',
                  onPressed: onShowSpeedPicker,
                ),
                IconButton(
                  icon: Icon(
                    sleepTimerState.isActive
                        ? Icons.bedtime
                        : Icons.bedtime_outlined,
                    color: sleepTimerState.isActive
                        ? accent
                        : aurora.textSecondary,
                    size: 20,
                  ),
                  tooltip: 'Sleep timer',
                  onPressed: onShowSleepTimerSheet,
                ),
              ],
            ),
            if (sleepTimerState.isActive)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(
                  sleepTimerState.isFading
                      ? 'Fading out...'
                      : '${sleepTimerState.remaining!.inMinutes}:'
                          '${(sleepTimerState.remaining!.inSeconds % 60).toString().padLeft(2, '0')} left',
                  style: TextStyle(color: aurora.textSecondary, fontSize: 11),
                ),
              ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                IconButton(
                  icon: Icon(Icons.skip_previous, color: aurora.textPrimary, size: 36),
                  onPressed: onPrevious,
                ),
                const SizedBox(width: 16),
                SizedBox(
                  width: 64,
                  height: 64,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      if (isResolving)
                        SizedBox(
                          width: 64,
                          height: 64,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: accent,
                          ),
                        ),
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: accent,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          icon: Icon(
                            isBuffering
                                ? Icons.hourglass_top
                                : isPlaying
                                    ? Icons.pause
                                    : Icons.play_arrow,
                            color: aurora.background,
                            size: 36,
                          ),
                          onPressed: onTogglePause,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 16),
                IconButton(
                  icon: Icon(Icons.skip_next, color: aurora.textPrimary, size: 36),
                  onPressed: onNext,
                ),
              ],
            ),
          ],
        );
      },
    );
  }
}