import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/data/drift/database.dart';
import 'package:teloplay/data/repositories/library_repository.dart';
import 'package:teloplay/models/statistics_model.dart';

/// Batch 5 — P1-P repository boundary: with no signed-in user headless,
/// [LibraryRepository.getListeningMaturity] must fail SOFT to
/// [ListeningMaturity.empty] (never throw, never fabricate a score).
/// The positive-path math is pinned by listening_maturity_test; the
/// signed-in DB path needs a real session and stays manual QA.
void main() {
  group('getListeningMaturity fail-soft', () {
    test('logged-out call returns empty, does not throw', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      addTearDown(db.close);

      final repo = LibraryRepository(db);
      final result = await repo.getListeningMaturity();

      expect(result.hasEnoughData, isFalse);
      expect(result.score, 0);
      expect(result, same(ListeningMaturity.empty));
    });
  });
}
