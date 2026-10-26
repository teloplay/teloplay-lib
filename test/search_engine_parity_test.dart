// ⚠️ OpenTune-parity search verification (v11) — এই টেস্টটা **আসল**
// `innertube-cli.jar` daemon spawn করে Windows engine-এর নতুন
// `searchSections()` / `searchSuggestionsRich()` end-to-end চালায়, তারপর
// verify করে:
//
//   1. Section-wise multi-entity output আসে (Songs/Albums/Artists/...),
//      শুধু song-only flat list নয় — এটাই OpenTune-এর
//      `SearchSummaryPage` shape।
//   2. Metadata "clean"/refined — song-এ artist date ("Apr 10") বা
//      episode-description ঢুকে যায় না, আর non-music row (drama episode,
//      bayan, football highlight) বাদ পড়ে।
//   3. Live search দুইটা অংশই দেয় — `queries` (text) + `items` (preview),
//      অর্থাৎ OpenTune-এর `SearchSuggestions`।
//
// Network + JVM লাগে, তাই offline/CI-তে auto-skip।
//
// Run:  flutter test test/search_engine_parity_test.dart
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/core/playback/innertube_windows_playback_engine.dart';
import 'package:teloplay/core/playback/playback_engine.dart';

/// তারিখ-এর মতো দেখতে artist/subtitle ("Apr 10", "Jan 27, 2025") —
/// H/W probe-এ এই ভুলগুলোই summary-card path থেকে আসত। canonical filtered
/// row-এ এগুলো থাকা উচিত নয়।
final _looksLikeDate = RegExp(
  r'^(?:Jan|Feb|Mar|Apr|May|Jun|Jul|Aug|Sep|Oct|Nov|Dec)\s+\d{1,2}(?:,\s*\d{4})?$',
  caseSensitive: false,
);

bool _jarExists() =>
    File('${Directory.current.path}\\assets\\innertube-cli.jar').existsSync();

void main() {
  final skipReason = _jarExists()
      ? null
      : 'assets/innertube-cli.jar নেই — Windows daemon parity test skip';

  group('InnertubeWindowsPlaybackEngine — OpenTune parity', () {
    late InnertubeWindowsPlaybackEngine engine;

    setUp(() => engine = InnertubeWindowsPlaybackEngine());
    tearDown(() => engine.dispose());

    test('searchSections() gives typed, section-wise, cleaned output',
        () async {
      final sections = await engine.searchSections('safar', limitPerSection: 8);

      // ── Print the REAL output so it can be eyeballed ────────────────
      // ignore: avoid_print
      print('\n=== WINDOWS ENGINE searchSections("safar") ===');
      for (final s in sections) {
        // ignore: avoid_print
        print('  ${s.title} (${s.items.length})');
        for (final i in s.items.take(3)) {
          // ignore: avoid_print
          print('    - [${i.type}] ${i.title}  |  ${i.subtitle ?? "—"}'
              '${i.duration != null ? "  ${i.duration!.inMinutes}:${(i.duration!.inSeconds % 60).toString().padLeft(2, "0")}" : ""}');
        }
      }

      expect(sections, isNotEmpty, reason: 'daemon reachable থাকলে খালি হওয়া উচিত নয়');

      final byTitle = {for (final s in sections) s.title: s.items};
      final canonical =
          sections.where((s) => s.title != 'Top results').toList();

      expect(canonical, isNotEmpty, reason: 'canonical section থাকতেই হবে');

      // OpenTune-এর four entity types — সবগুলোই আসা উচিত।
      final types = canonical.expand((s) => s.items).map((i) => i.type).toSet();
      expect(types, contains('song'), reason: 'Songs section থাকা উচিত');
      expect(types.difference({'song', 'album', 'artist', 'playlist'}), isEmpty,
          reason: 'অজানা type থাকা যাবে না');

      // প্রতিটা item-এ usable id + thumbnail থাকতে হবে (UI navigate করতে পারে)।
      for (final item in canonical.expand((s) => s.items)) {
        expect(item.id, isNotEmpty, reason: '${item.title}: id খালি');
        expect(item.thumbnail, isNotEmpty, reason: '${item.title}: thumbnail নেই');
      }

      // ── "Top results" section present + canonical থেকে derived ──────
      expect(byTitle.containsKey('Top results'), isTrue);
      expect(byTitle['Top results']!.first.type, 'song',
          reason: 'Top results-এ song priority সবার আগে');

      // ── Refinement: song-এর subtitle কখনো bare date নয় ────────────
      for (final song in (byTitle['Songs'] ?? const <RichSearchItem>[])) {
        if (song.subtitle != null) {
          expect(_looksLikeDate.hasMatch(song.subtitle!), isFalse,
              reason: '"${song.title}" artist/subtitle = "${song.subtitle}" '
                  '(date — summary-card path-এর contamination)');
        }
      }

      // ── Refinement: non-music row বাদ পড়েছে ───────────────────────
      for (final item in canonical.expand((s) => s.items)) {
        expect(isNonMusicResult(item), isFalse,
            reason: 'non-music item বাদ পড়েনি: ${item.title}');
      }
    }, skip: skipReason, timeout: const Timeout(Duration(minutes: 3)));

    test('searchSuggestionsRich() gives queries + item previews', () async {
      final rich = await engine.searchSuggestionsRich('safar');

      // ignore: avoid_print
      print('\n=== WINDOWS ENGINE searchSuggestionsRich("safar") ===');
      // ignore: avoid_print
      print('  queries (${rich.queries.length}): \${rich.queries.take(5).toList()}');
      for (final i in rich.items) {
        // ignore: avoid_print
        print('    - [${i.type}] ${i.title}  |  ${i.subtitle ?? "—"}');
      }

      expect(rich.queries, isNotEmpty, reason: 'OpenTune-এর মতো text suggestion');
      expect(rich.items, isNotEmpty, reason: 'OpenTune-এর recommendedItems');
      expect(rich.items.every((i) => i.type == 'song'), isTrue);
      expect(rich.items.length, lessThanOrEqualTo(5));
    }, skip: skipReason, timeout: const Timeout(Duration(minutes: 3)));
  });
}
