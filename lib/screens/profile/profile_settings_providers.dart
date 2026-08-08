import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme.dart';
import '../../data/repositories/settings_repository.dart';
import '../../providers/database_provider.dart';

/// ⚠️ Phase 6.5 Batch 6 (Batch B) — Profile screen-এর Playback &
/// Experience section-এর জন্য settings state, `SettingsRepository`
/// (Phase 1-এ তৈরি, generic key-value wrapper `SettingsEntries`-এর
/// উপর) দিয়ে persist হয়।
///
/// ⚠️ প্রতিটা toggle-এর নিজস্ব ছোট `AsyncNotifier` — একটা single বড়
/// "AppSettings" object না রেখে আলাদা রাখা হয়েছে, কারণ প্রতিটা toggle
/// independent lifecycle-এ (কেউ audio_quality future-এ যোগ হবে, কেউ
/// এখনই কার্যকর) — একটাতে write করলে অন্যগুলো অকারণে rebuild না হোক।

const _keyThemeMode = 'theme_mode'; // 'dark' | 'amoled'
const _keyDynamicColors = 'dynamic_album_colors'; // 'true' | 'false'
const _keyReduceMotion = 'reduce_motion';
const _keyBatterySaverUi = 'battery_saver_ui';

final settingsRepositoryProvider = Provider<SettingsRepository>((ref) {
  final db = ref.watch(appDatabaseProvider);
  return SettingsRepository(db);
});

/// ── Theme Mode ──────────────────────────────────────────────────
class ThemeModeNotifier extends AsyncNotifier<AppThemeMode> {
  @override
  Future<AppThemeMode> build() async {
    final repo = ref.watch(settingsRepositoryProvider);
    final raw = await repo.getValue(_keyThemeMode);
    return raw == 'amoled' ? AppThemeMode.amoled : AppThemeMode.dark;
  }

  Future<void> setMode(AppThemeMode mode) async {
    final repo = ref.read(settingsRepositoryProvider);
    state = AsyncData(mode);
    await repo.setValue(_keyThemeMode, mode == AppThemeMode.amoled ? 'amoled' : 'dark');
  }
}

final themeModeProvider = AsyncNotifierProvider<ThemeModeNotifier, AppThemeMode>(
  ThemeModeNotifier.new,
);

/// ── Boolean toggle scaffolding (Dynamic Colors / Reduce Motion / Battery Saver) ──
/// তিনটা toggle-ই একই shape (bool, default true/false, single key) —
/// একটা reusable base class দিয়ে duplication কমানো হলো।
abstract class _BoolSettingNotifier extends AsyncNotifier<bool> {
  String get key;
  bool get defaultValue;

  @override
  Future<bool> build() async {
    final repo = ref.watch(settingsRepositoryProvider);
    final raw = await repo.getValue(key);
    if (raw == null) return defaultValue;
    return raw == 'true';
  }

  Future<void> setValue(bool value) async {
    final repo = ref.read(settingsRepositoryProvider);
    state = AsyncData(value);
    await repo.setValue(key, value.toString());
  }
}

class DynamicColorsNotifier extends _BoolSettingNotifier {
  @override
  String get key => _keyDynamicColors;
  @override
  bool get defaultValue => true; // ⚠️ Phase 6-এ Dynamic Album Identity default ON
}

final dynamicColorsProvider = AsyncNotifierProvider<DynamicColorsNotifier, bool>(
  DynamicColorsNotifier.new,
);

class ReduceMotionNotifier extends _BoolSettingNotifier {
  @override
  String get key => _keyReduceMotion;
  @override
  bool get defaultValue => false;
}

final reduceMotionProvider = AsyncNotifierProvider<ReduceMotionNotifier, bool>(
  ReduceMotionNotifier.new,
);

class BatterySaverUiNotifier extends _BoolSettingNotifier {
  @override
  String get key => _keyBatterySaverUi;
  @override
  bool get defaultValue => false;
}

final batterySaverUiProvider = AsyncNotifierProvider<BatterySaverUiNotifier, bool>(
  BatterySaverUiNotifier.new,
);