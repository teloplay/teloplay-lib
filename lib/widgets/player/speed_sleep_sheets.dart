import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/now_playing_model.dart';
import '../../providers/music_player_provider.dart';

/// Phase 6.5 Batch 5 — extracted from `MusicPlayerScreen`'s private
/// `_showSpeedPicker`/`_showSleepTimerSheet` methods. Both
/// `NowPlayingScreen` and `MusicPlayerScreen` now call these (and
/// `DesktopBottomPlayerBar`'s speed button can wire to
/// [showSpeedPickerSheet] too, once it needs its own popover instead
/// of relying on a caller-provided callback).
///
/// Kept as free functions (not a class) — no state, just two
/// `showModalBottomSheet` presenters. `ref` is passed in explicitly so
/// callers control which `WidgetRef` is used (no global scope assumed).

const _speedPresets = [0.5, 0.75, 1.0, 1.25, 1.5, 1.75, 2.0];

void showSpeedPickerSheet(BuildContext context, WidgetRef ref, double currentSpeed) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Playback Speed',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            ..._speedPresets.map((speed) {
              final isSelected = speed == currentSpeed;
              return ListTile(
                title: Text(
                  '${speed}x',
                  style: TextStyle(
                    color: isSelected ? Colors.greenAccent : Colors.white,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  ),
                ),
                trailing: isSelected ? const Icon(Icons.check, color: Colors.greenAccent) : null,
                onTap: () {
                  ref.read(musicPlayerRepositoryProvider).setPlaybackSpeed(speed);
                  Navigator.pop(sheetContext);
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

const _sleepTimerPresets = [
  Duration(minutes: 5),
  Duration(minutes: 15),
  Duration(minutes: 30),
  Duration(minutes: 45),
  Duration(minutes: 60),
];

void showSleepTimerSheet(BuildContext context, WidgetRef ref, SleepTimerState currentState) {
  showModalBottomSheet(
    context: context,
    backgroundColor: const Color(0xFF1E1E1E),
    builder: (sheetContext) {
      return SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Padding(
              padding: EdgeInsets.all(16),
              child: Text(
                'Sleep Timer',
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ),
            if (currentState.isActive)
              ListTile(
                leading: const Icon(Icons.timer_off, color: Colors.redAccent),
                title: const Text('Timer Off', style: TextStyle(color: Colors.redAccent)),
                onTap: () {
                  ref.read(musicPlayerRepositoryProvider).cancelSleepTimer();
                  Navigator.pop(sheetContext);
                },
              ),
            ..._sleepTimerPresets.map((duration) {
              return ListTile(
                title: Text('${duration.inMinutes} Minutes', style: const TextStyle(color: Colors.white)),
                onTap: () {
                  ref.read(musicPlayerRepositoryProvider).startSleepTimer(duration);
                  Navigator.pop(sheetContext);
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