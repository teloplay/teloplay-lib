import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../providers/music_player_provider.dart' show settingsRepositoryProvider;

/// Onboarding completion tracking (roadmap Section 13 / Phase 0 item #13).
///
/// ⚠️ Fix (Phase 0 v11 stabilization): getting_started_screen.dart and
/// checklist_badge.dart both referenced `onboardingCompletionProvider`
/// and `onboardingDismissedProvider` — neither was ever defined anywhere
/// in the codebase. [SettingsRepository] is also String-only
/// (getValue/setValue), not the `setBool`/generic-typed store both
/// files assumed.
///
/// Keys match the roadmap's "Completion tracking" list exactly:
/// onboarding_play_first_song, onboarding_try_mini_player,
/// onboarding_explore_library, onboarding_build_queue,
/// onboarding_customize_experience.
class OnboardingKeys {
  static const playFirstSong = 'onboarding_play_first_song';
  static const tryMiniPlayer = 'onboarding_try_mini_player';
  static const exploreLibrary = 'onboarding_explore_library';
  static const buildQueue = 'onboarding_build_queue';
  static const customizeExperience = 'onboarding_customize_experience';
  static const dismissed = 'onboarding_dismissed';

  static const all = [
    playFirstSong,
    tryMiniPlayer,
    exploreLibrary,
    buildQueue,
    customizeExperience,
  ];
}

/// Map of item id -> completed. Missing/empty-string values read as false
/// (SettingsRepository has no per-key "unset" state beyond that).
final onboardingCompletionProvider =
    FutureProvider.autoDispose<Map<String, bool>>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final values = await settings.getValues(OnboardingKeys.all);
  return {
    for (final id in OnboardingKeys.all) id: values[id] == 'true',
  };
});

final onboardingDismissedProvider = FutureProvider.autoDispose<bool>((ref) async {
  final settings = ref.watch(settingsRepositoryProvider);
  final value = await settings.getValue(OnboardingKeys.dismissed);
  return value == 'true';
});

/// Mark a single onboarding item complete. Call sites (per roadmap
/// Section 13):
/// - playFirstSong: after the first successful play event
/// - tryMiniPlayer: when the mini player is tapped/expanded
/// - exploreLibrary: on /library visit
/// - buildQueue: when queue.add() is called
/// - customizeExperience: on /settings visit
class OnboardingTracker {
  final Ref _ref;
  OnboardingTracker(this._ref);

  Future<void> markComplete(String key) async {
    final settings = _ref.read(settingsRepositoryProvider);
    await settings.setValue(key, 'true');
    _ref.invalidate(onboardingCompletionProvider);
  }

  Future<void> dismiss() async {
    final settings = _ref.read(settingsRepositoryProvider);
    await settings.setValue(OnboardingKeys.dismissed, 'true');
    _ref.invalidate(onboardingDismissedProvider);
  }
}

final onboardingTrackerProvider = Provider<OnboardingTracker>((ref) {
  return OnboardingTracker(ref);
});
