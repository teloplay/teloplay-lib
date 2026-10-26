import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/core/theme/app_theme.dart';
import 'package:teloplay/data/drift/database.dart';
import 'package:teloplay/data/repositories/settings_repository.dart';
import 'package:teloplay/providers/database_provider.dart';
import 'package:teloplay/providers/music_player_provider.dart'
    show settingsRepositoryProvider;
import 'package:teloplay/providers/theme_provider.dart';

/// Batch 5 — theme LOAD paths (P1-C). The existing theme_persist_test pins
/// defaults/toggle/degraded-write; this file pins the background restore:
/// a saved `amoled` value flips state after build, anything else stays
/// dark, and a working store reports persist success.
///
/// Headless has no Supabase session, so the real [SettingsRepository]
/// degrades — the override below is a test-only in-memory fake (same
/// hand-fake spirit as the lyrics engine fake), not a production seam.
class _MemorySettings extends SettingsRepository {
  final Map<String, String> store;
  _MemorySettings(super.db, this.store);

  @override
  Future<String?> getValue(String key) async => store[key];

  @override
  Future<void> setValue(String key, String value) async {
    store[key] = value;
  }
}

void main() {
  ProviderContainer containerWith(Map<String, String> seed) {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final c = ProviderContainer(
      overrides: [
        appDatabaseProvider.overrideWithValue(db),
        settingsRepositoryProvider
            .overrideWithValue(_MemorySettings(db, Map.of(seed))),
      ],
    );
    addTearDown(() {
      c.dispose();
      db.close();
    });
    return c;
  }

  group('ThemeModeNotifier load', () {
    test('saved amoled restores after build', () async {
      final c = containerWith({'app_theme_mode': 'amoled'});
      // build() returns dark synchronously; _loadSaved flips async.
      expect(c.read(themeModeProvider), AppThemeMode.dark);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(themeModeProvider), AppThemeMode.amoled);
    });

    test('unknown saved value stays dark', () async {
      final c = containerWith({'app_theme_mode': 'light'});
      expect(c.read(themeModeProvider), AppThemeMode.dark);
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(themeModeProvider), AppThemeMode.dark);
    });

    test('missing saved value stays dark', () async {
      final c = containerWith({});
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect(c.read(themeModeProvider), AppThemeMode.dark);
    });

    test('working store reports persist success', () async {
      final c = containerWith({});
      final ok =
          await c.read(themeModeProvider.notifier).setMode(AppThemeMode.amoled);
      expect(ok, isTrue);
      expect(c.read(themeModeProvider), AppThemeMode.amoled);
    });
  });
}
