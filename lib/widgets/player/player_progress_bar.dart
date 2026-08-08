import 'package:flutter/material.dart';

import '../../core/theme/app_theme.dart';
import '../../core/theme/app_theme_extension.dart';

/// ⚠️ Phase 6 — শেয়ার্ড content widget। Track duration না থাকলে caller
/// এই widget-ই দেখাবে না (দেখো music_player_screen.dart-এর
/// `if (duration != null)` guard — সেটা এখন এই widget-এর ভেতরেই হয়ে
/// গেছে, caller-কে আলাদা guard লিখতে হয় না)।
///
/// Progress fill color album accent (`context.aurora.effectiveAccent`) —
/// এটাই দুটো জায়গার একটা (roadmap-এ locked) যেখানে dynamic accent সরাসরি
/// প্রভাব ফেলে (বাকি ৩টা: player glow, player background tint,
/// mini-player accent)। Time stamp-এ `AppTheme.timeStampStyle`
/// (tabular figures) ব্যবহার করা হচ্ছে যাতে সেকেন্ড বদলানোর সময় সংখ্যা
/// jitter/shift না করে।
class PlayerProgressBar extends StatelessWidget {
  const PlayerProgressBar({
    super.key,
    required this.position,
    required this.duration,
    required this.onSeek,
  });

  final Duration position;
  final Duration? duration;
  final ValueChanged<Duration> onSeek;

  String _formatDuration(Duration d) {
    final minutes = d.inMinutes.remainder(60).toString().padLeft(2, '0');
    final seconds = d.inSeconds.remainder(60).toString().padLeft(2, '0');
    return '$minutes:$seconds';
  }

  @override
  Widget build(BuildContext context) {
    final duration = this.duration;
    if (duration == null) return const SizedBox.shrink();

    final aurora = context.aurora;
    final accent = aurora.effectiveAccent;

    return Column(
      children: [
        SliderTheme(
          data: SliderThemeData(
            trackHeight: 4,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            activeTrackColor: accent,
            inactiveTrackColor: aurora.surfaceRaised,
            thumbColor: accent,
            overlayColor: accent.withOpacity(0.2),
          ),
          child: Slider(
            value: duration.inMilliseconds > 0
                ? (position.inMilliseconds / duration.inMilliseconds)
                    .clamp(0.0, 1.0)
                : 0.0,
            onChanged: (v) {
              onSeek(Duration(
                milliseconds: (v * duration.inMilliseconds).round(),
              ));
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                _formatDuration(position),
                style: AppTheme.timeStampStyle.copyWith(
                  color: aurora.textSecondary,
                ),
              ),
              Text(
                _formatDuration(duration),
                style: AppTheme.timeStampStyle.copyWith(
                  color: aurora.textSecondary,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}