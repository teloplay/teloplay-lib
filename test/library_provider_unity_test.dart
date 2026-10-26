import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/data/drift/database.dart';
import 'package:teloplay/providers/database_provider.dart';
import 'package:teloplay/providers/library_provider.dart';
import 'package:teloplay/providers/repository_providers.dart' as canonical;

/// P0-11: exactly ONE `libraryRepositoryProvider` definition must exist.
/// `library_provider.dart` re-exports the canonical definition from
/// `repository_providers.dart`. If anyone re-adds a second definition,
/// THIS FILE FAILS TO COMPILE (ambiguous import) — that is the guard.
/// Uses the existing `AppDatabase.forTesting` seam (no new architecture).
void main() {
  group('libraryRepositoryProvider unity', () {
    test('both import paths resolve the same instance', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final container = ProviderContainer(
        overrides: [appDatabaseProvider.overrideWithValue(db)],
      );
      addTearDown(container.dispose);

      final viaLibrary = container.read(libraryRepositoryProvider);
      final viaCanonical = container.read(
        canonical.libraryRepositoryProvider,
      );

      expect(identical(viaLibrary, viaCanonical), isTrue);
    });
  });
}
