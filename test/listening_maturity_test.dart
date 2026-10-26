import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/models/statistics_model.dart';

/// P1-P — [computeListeningMaturity] is pure and deterministic: fixed
/// inputs must always yield fixed outputs, and thin samples must yield
/// [ListeningMaturity.empty] (never a fabricated score).
void main() {
  group('computeListeningMaturity', () {
    test('insufficient sample (< 5 lifetime plays) yields empty', () {
      final m = computeListeningMaturity(
        windowPlays: 4,
        windowSkips: 0,
        lifetimePlays: 4,
        distinctArtists: 4,
        favoritesCount: 4,
        currentStreak: 4,
      );
      expect(m.hasEnoughData, isFalse);
      expect(m.score, 0);
      expect(m, same(ListeningMaturity.empty));
    });

    test('zero lifetime plays yields empty', () {
      final m = computeListeningMaturity(
        windowPlays: 0,
        windowSkips: 0,
        lifetimePlays: 0,
        distinctArtists: 0,
        favoritesCount: 0,
        currentStreak: 0,
      );
      expect(m.hasEnoughData, isFalse);
    });

    test('ideal listener scores 100 with full components', () {
      final m = computeListeningMaturity(
        windowPlays: 50,
        windowSkips: 0,
        lifetimePlays: 50,
        distinctArtists: 10, // 1 per 5 plays -> full diversity
        favoritesCount: 5, // 1 per 10 plays -> full favorites
        currentStreak: 7, // full consistency
      );
      expect(m.hasEnoughData, isTrue);
      expect(m.completionPoints, 40);
      expect(m.diversityPoints, 25);
      expect(m.favoritesPoints, 20);
      expect(m.consistencyPoints, 15);
      expect(m.score, 100);
      expect(m.bandLabel, 'Deep Listener');
    });

    test('all-skipped window zeroes completion only', () {
      final m = computeListeningMaturity(
        windowPlays: 20,
        windowSkips: 20,
        lifetimePlays: 20,
        distinctArtists: 4,
        favoritesCount: 2,
        currentStreak: 7,
      );
      expect(m.completionPoints, 0);
      expect(m.consistencyPoints, 15);
      expect(m.score, lessThan(100));
    });

    test('single-artist looping caps diversity', () {
      final m = computeListeningMaturity(
        windowPlays: 50,
        windowSkips: 0,
        lifetimePlays: 50,
        distinctArtists: 1,
        favoritesCount: 0,
        currentStreak: 0,
      );
      // 1 artist per 50 plays -> ratio 0.1 -> ~2-3 pts, far from full.
      expect(m.diversityPoints, lessThan(10));
      expect(m.favoritesPoints, 0);
      expect(m.consistencyPoints, 0);
    });

    test('long streak caps consistency at 15', () {
      final m = computeListeningMaturity(
        windowPlays: 10,
        windowSkips: 0,
        lifetimePlays: 10,
        distinctArtists: 2,
        favoritesCount: 1,
        currentStreak: 365,
      );
      expect(m.consistencyPoints, 15);
      expect(m.score, lessThanOrEqualTo(100));
    });

    test('deterministic: same inputs, same outputs', () {
      ListeningMaturity run() => computeListeningMaturity(
            windowPlays: 17,
            windowSkips: 3,
            lifetimePlays: 42,
            distinctArtists: 6,
            favoritesCount: 2,
            currentStreak: 3,
          );
      final a = run();
      final b = run();
      expect(a.score, b.score);
      expect(a.completionPoints, b.completionPoints);
      expect(a.diversityPoints, b.diversityPoints);
      expect(a.favoritesPoints, b.favoritesPoints);
      expect(a.consistencyPoints, b.consistencyPoints);
      expect(a.bandLabel, b.bandLabel);
    });

    test('middle bands hit at their thresholds', () {
      ListeningMaturity mid({
        required int windowPlays,
        required int windowSkips,
        required int lifetimePlays,
        required int distinctArtists,
        required int favoritesCount,
        required int currentStreak,
      }) =>
          computeListeningMaturity(
            windowPlays: windowPlays,
            windowSkips: windowSkips,
            lifetimePlays: lifetimePlays,
            distinctArtists: distinctArtists,
            favoritesCount: favoritesCount,
            currentStreak: currentStreak,
          );

      // ~40 pts -> Finding Rhythm band (25-49).
      final rhythm = mid(
        windowPlays: 20,
        windowSkips: 10, // 0.5 completion -> 20 pts
        lifetimePlays: 20,
        distinctArtists: 2, // 2/(20/5)=0.5 -> ~12-13 pts
        favoritesCount: 1, // 1/(20/10)=0.5 -> 10 pts
        currentStreak: 0,
      );
      expect(rhythm.hasEnoughData, isTrue);
      expect(rhythm.score, inInclusiveRange(25, 49));
      expect(rhythm.bandLabel, 'Finding Rhythm');

      // ~65 pts -> Engaged Listener band (50-74).
      final engaged = mid(
        windowPlays: 30,
        windowSkips: 3, // 0.9 completion -> 36 pts
        lifetimePlays: 30,
        distinctArtists: 4, // 4/(30/5)=0.67 -> ~17 pts
        favoritesCount: 2, // 2/(30/10)=0.67 -> ~13 pts
        currentStreak: 0,
      );
      expect(engaged.score, inInclusiveRange(50, 74));
      expect(engaged.bandLabel, 'Engaged Listener');
    });

    test('band labels are neutral activity wording', () {
      // Narrow looping over 10 plays: completion 0 + diversity ~13.
      expect(
        computeListeningMaturity(
          windowPlays: 10,
          windowSkips: 10,
          lifetimePlays: 10,
          distinctArtists: 1,
          favoritesCount: 0,
          currentStreak: 0,
        ).bandLabel,
        'Getting Started',
      );
    });
  });
}
