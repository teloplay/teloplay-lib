import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/logging/app_logger.dart';
import '../core/theme/app_theme.dart';
import 'music_player_provider.dart' show settingsRepositoryProvider;

/// ⚠️ Phase 6 (Smart Player UI & Theme Polish) — runtime Dark/AMOLED
/// switching, persisted via the generic key-value repository (same pattern
/// as shuffle/repeat/speed) — no new storage mechanism.
///
/// P1-C — persistence is real now (was TODO): [build] returns dark
/// immediately for first-frame safety, then loads the saved value in the
/// background; [setMode]/[toggle] update state instantly (UI never waits)
/// and persist with write-verify (setValue swallows errors, so success is
/// confirmed by reading back). Returns false only when persistence failed —
/// callers surface that (snackbar); in-memory state is always correct.
class ThemeModeNotifier extends Notifier<AppThemeMode> {
  static const _settingsKey = 'app_theme_mode';

  @override
  AppThemeMode build() {
    _loadSaved();
    return AppThemeMode.dark;
  }

  Future<void> _loadSaved() async {
    try {
      final saved =
          await ref.read(settingsRepositoryProvider).getValue(_settingsKey);
      if (saved == AppThemeMode.amoled.name) {
        state = AppThemeMode.amoled;
      }
    } catch (e) {
      AppLogger.error('ThemeModeNotifier: saved theme load failed', e);
    }
  }

  Future<bool> _persist(AppThemeMode mode) async {
    try {
      final repo = ref.read(settingsRepositoryProvider);
      await repo.setValue(_settingsKey, mode.name);
      final check = await repo.getValue(_settingsKey);
      return check == mode.name;
    } catch (e) {
      AppLogger.error('ThemeModeNotifier: theme persist failed', e);
      return false;
    }
  }

  Future<bool> setMode(AppThemeMode mode) async {
    state = mode;
    return _persist(mode);
  }

  Future<bool> toggle() async {
    final next =
        state == AppThemeMode.dark ? AppThemeMode.amoled : AppThemeMode.dark;
    return setMode(next);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, AppThemeMode>(ThemeModeNotifier.new);