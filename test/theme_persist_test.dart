import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/core/theme/app_theme.dart';
import 'package:teloplay/data/drift/database.dart';
import 'package:teloplay/providers/database_provider.dart';
import 'package:teloplay/providers/theme_provider.dart';

/// P1-C: theme load/persist contract. Headless tests have no Supabase
/// session, so persistence degrades (false) while in-memory state stays
/// correct — guest-safe by construction, never throwing.
void main() {
  ProviderContainer container() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final c = ProviderContainer(
      overrides: [appDatabaseProvider.overrideWithValue(db)],
    );
    addTearDown(() {
      c.dispose();
      db.close();
    });
    return c;
  }

  group('ThemeModeNotifier', () {
    test('build defaults to dark', () {
      final c = container();
      expect(c.read(themeModeProvider), AppThemeMode.dark);
    });

    test('toggle flips state immediately', () async {
      final c = container();
      await c.read(themeModeProvider.notifier).toggle();
      expect(c.read(themeModeProvider), AppThemeMode.amoled);
      await c.read(themeModeProvider.notifier).toggle();
      expect(c.read(themeModeProvider), AppThemeMode.dark);
    });

    test('setMode updates state even when persistence degrades', () async {
      final c = container();
      // No Supabase session headless → repo swallows → verify-read fails.
      // State must still be correct; only the bool reports degradation.
      final ok = await c
          .read(themeModeProvider.notifier)
          .setMode(AppThemeMode.amoled);
      expect(c.read(themeModeProvider), AppThemeMode.amoled);
      expect(ok, isFalse);
    });
  });
}
