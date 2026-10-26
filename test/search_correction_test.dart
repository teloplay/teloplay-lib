import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/providers/search_provider.dart' show correctionCandidate;

/// P1-K: bounded typo correction. Pure function — no providers, no network.
/// Contract: first distinct server suggestion, else null. Caller runs at
/// most one follow-up search and never loops.
void main() {
  group('correctionCandidate', () {
    test('returns first suggestion distinct from query', () {
      expect(
        correctionCandidate('kesriya', ['kesariya', 'kesariya unplugged']),
        'kesariya',
      );
    });

    test('comparison is case-insensitive and trimmed', () {
      expect(correctionCandidate('  Kesariya ', ['kesariya']), isNull);
      expect(correctionCandidate('kesariya', ['  ', 'Kesariya (From Film)']),
          'Kesariya (From Film)');
    });

    test('null when query empty or no suggestions', () {
      expect(correctionCandidate('', ['kesariya']), isNull);
      expect(correctionCandidate('   ', ['kesariya']), isNull);
      expect(correctionCandidate('xyzqqq', []), isNull);
    });

    test('null when suggestions only repeat the query', () {
      expect(
        correctionCandidate('tun hi ho', ['Tun Hi Ho', 'tun hi ho ']),
        isNull,
      );
    });

    test('skips blank suggestions', () {
      expect(correctionCandidate('abc', ['', '  ', 'abcd']), 'abcd');
    });
  });
}
