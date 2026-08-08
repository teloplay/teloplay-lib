import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/theme/app_theme.dart';
import 'music_player_provider.dart' show settingsRepositoryProvider;

/// ⚠️ Phase 6 (Smart Player UI & Theme Polish) — runtime Dark/AMOLED
/// switching। `settingsRepositoryProvider` (Phase 1-এ তৈরি generic
/// key-value repository, shuffle/repeat/speed একই প্যাটার্নে persist
/// করে) ব্যবহার করে persist করা হচ্ছে — নতুন কোনো storage mechanism
/// লাগেনি।
///
/// ⚠️ TODO (এই ব্যাচে placeholder key ব্যবহার করা হচ্ছে —
/// `settings_repository.dart`-এর প্রকৃত get/set method signature
/// দেখে পরের ব্যাচে এই TODO resolve করা হবে; আপাতত in-memory
/// StateNotifier হিসেবেই কাজ করবে, persist অংশ commented রাখা হলো
/// যাতে ভুল method-name দিয়ে compile-error না আসে)।
class ThemeModeNotifier extends Notifier<AppThemeMode> {
  static const _settingsKey = 'app_theme_mode';

  @override
  AppThemeMode build() {
    // TODO(Phase 6 patch): settings_repository.dart চূড়ান্ত হলে এখানে
    // saved value load করা হবে, e.g.:
    // final saved = ref.read(settingsRepositoryProvider).getString(_settingsKey);
    // return saved == 'amoled' ? AppThemeMode.amoled : AppThemeMode.dark;
    return AppThemeMode.dark;
  }

  void setMode(AppThemeMode mode) {
    state = mode;
    // TODO(Phase 6 patch): persist করা হবে, e.g.:
    // ref.read(settingsRepositoryProvider).setString(_settingsKey, mode.name);
  }

  void toggle() {
    setMode(state == AppThemeMode.dark ? AppThemeMode.amoled : AppThemeMode.dark);
  }
}

final themeModeProvider =
    NotifierProvider<ThemeModeNotifier, AppThemeMode>(ThemeModeNotifier.new);