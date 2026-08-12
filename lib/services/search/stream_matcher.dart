import 'search_orchestrator.dart';

/// Phase 0: Simple title + duration matching.
/// Phase 6+ Future Addition: Weighted confidence scoring (preserved as comment).
class StreamMatcher {
  /// Find best Deezer match for a YouTube result.
  /// Returns null if no match within tolerance.
  static DeezerTrack? findBestMatch({
    required List<DeezerTrack> deezerTracks,
    required YoutubeResult youtubeResult,
  }) {
    if (deezerTracks.isEmpty) return null;

    DeezerTrack? bestMatch;
    double bestScore = 0;

    for (final dz in deezerTracks) {
      final score = _calculateScore(dz, youtubeResult);
      if (score > bestScore) {
        bestScore = score;
        bestMatch = dz;
      }
    }

    // Phase 0: Simple threshold — match if title AND duration align
    return bestScore >= 1.0 ? bestMatch : null;
  }

  /// Phase 0 scoring: binary match (1.0 = match, 0.0 = no match)
  static double _calculateScore(DeezerTrack dz, YoutubeResult yt) {
    final titleMatch = _normalize(dz.title) == _normalize(yt.title) ||
        _normalize(yt.title).contains(_normalize(dz.title));

    final durationMatch = dz.duration != null && yt.duration != null
        ? (dz.duration!.inSeconds - yt.duration!.inSeconds).abs() <= 15
        : true; // If either duration missing, skip duration check

    return (titleMatch && durationMatch) ? 1.0 : 0.0;
  }

  /// Normalize title by removing common suffixes and lowercasing.
  static String _normalize(String title) {
    return title
        .toLowerCase()
        .replaceAll(RegExp(r'\(official\s*(video|audio|music\s*video)?\)'), '')
        .replaceAll(RegExp(r'\[official\s*(video|audio|hd)?\]'), '')
        .replaceAll(RegExp(r'\(lyrics?\s*(video)?\)'), '')
        .replaceAll(RegExp(r'\[lyrics?\]'), '')
        .replaceAll(RegExp(r'\(hd\)|\[hd\]'), '')
        .replaceAll(RegExp(r'\(4k\)|\[4k\]'), '')
        .replaceAll(RegExp(r'\(8d\s*audio\)'), '')
        .replaceAll(RegExp(r'\(slowed\s*\+\s*reverb?\)'), '')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
  }

  /* ═══════════════════════════════════════════════════════════════
   * 🆕 FUTURE ADDITION — Phase 6+ Weighted Confidence Scoring
   * ═══════════════════════════════════════════════════════════════
   *
   * When Phase 6+ is reached, replace _calculateScore with:
   *
   * static double _calculateScoreWeighted(DeezerTrack dz, YoutubeResult yt) {
   *   // Title similarity — 40%
   *   final titleSim = _levenshteinSimilarity(_normalize(dz.title), _normalize(yt.title));
   *
   *   // Artist match — 30%
   *   final artistSim = _levenshteinSimilarity(
   *     _normalize(dz.artistName),
   *     _normalize(yt.channelName),
   *   );
   *
   *   // Duration match — 20%
   *   double durationScore = 0;
   *   if (dz.duration != null && yt.duration != null) {
   *     final diff = (dz.duration!.inSeconds - yt.duration!.inSeconds).abs();
   *     if (diff <= 10) durationScore = 1.0;
   *     else if (diff <= 30) durationScore = 0.5;
   *     else durationScore = 0;
   *   }
   *
   *   // Channel verification — 10%
   *   double channelScore = 0;
   *   if (yt.isOfficialChannel || yt.isVerifiedChannel) channelScore = 1.0;
   *
   *   final total = (titleSim * 0.40) + (artistSim * 0.30) +
   *                 (durationScore * 0.20) + (channelScore * 0.10);
   *   return total;
   * }
   *
   * Confidence Tiers:
   * - High (>0.7) → auto-play, seamless
   * - Medium (0.5–0.7) → play + "May be different version" badge
   * - Low (<0.5) → show both options separately, don't auto-merge
   *
   * Files to modify:
   * - stream_matcher.dart — Replace simple matching with weighted scoring
   * - search_orchestrator.dart — Add confidence tier handling
   * - search_screen.dart — Add "May be different version" badge UI
   * ═══════════════════════════════════════════════════════════════ */
}