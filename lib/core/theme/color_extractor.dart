import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../logging/app_logger.dart';
import 'app_colors.dart';

/// ⚠️ Phase 6 (Smart Player UI & Theme Polish) — Dynamic album-based accent.
///
/// Pipeline:
///   1. Extract dominant color from album artwork (local file — path previously
///      resolved via CachedArtwork/CacheService) using `PaletteGenerator`.
///   2. **The raw dominant color is not used directly** — some album art
///      can produce unappealing colors such as dirty brown, mud green,
///      washed-out yellow, or dull gray. Hence, the extracted color is mapped
///      (via HSL distance) to the closest match in `AppColors.curatedAccents` —
///      it is this curated value that is actually applied in the UI.
///   3. Contrast validation — the curated palette is pre-validated (within
///      lightness/saturation boundaries), so extra normalization is generally
///      unnecessary. However, as a defensive measure, the final color's
///      lightness is clamped to a usable range (0.35–0.75) — see
///      `_ensureUsableLightness()`.
///
/// **Performance:** Extracted only once per track change (cached per trackId),
/// not recomputed on widget rebuilds. In Low RAM mode, blur is disabled
/// (handled externally — `CachedArtwork`/player background widget inspects
/// `PerformanceService.isLowRamMode`), but color extraction still runs
/// (lightweight, performed by resizing the image).
class ColorExtractor {
  ColorExtractor._();

  static final _cache = <String, Color>{};

  /// Cache key using [trackId] — no need to re-extract if the track remains
  /// the same, even if stream/thumbnail URLs change.
  static Future<Color?> extractForTrack({
    required String trackId,
    required String localImagePath,
  }) async {
    final cached = _cache[trackId];
    if (cached != null) return cached;

    // P1-I — capability-safe web fallback (NOT blind): `FileImage(File())`
    // cannot run on web, and the caller (`AlbumAccentNotifier`) treats null
    // as "keep previous accent" (copyWith `?? this`), identical to the
    // extraction-failure path below. No new framework, no behavior change
    // on Android/Windows.
    if (kIsWeb) return null;

    try {
      final imageProvider = FileImage(File(localImagePath));

      // ⚠️ PaletteGenerator runs with a reduced color count instead of full
      // resolution to keep extraction fast (even though it's once per track,
      // avoiding unnecessary CPU/memory overhead on large artwork is desirable).
      final palette = await PaletteGenerator.fromImageProvider(
        imageProvider,
        maximumColorCount: 12,
      );

      final dominant = palette.dominantColor?.color ??
          palette.vibrantColor?.color ??
          palette.mutedColor?.color;

      if (dominant == null) return null;

      final mapped = _mapToNearestCurated(dominant);
      final safe = _ensureUsableLightness(mapped);

      _cache[trackId] = safe;
      return safe;
    } catch (e) {
      // ⚠️ If extraction fails (corrupt file, decode error), exceptions are
      // not propagated — accent is purely a UI enhancement; on failure,
      // the caller gracefully falls back to `AuroraColors.primary`
      // (see AuroraColors.effectiveAccent).
      AppLogger.error('Album color extraction failed for $trackId', e);
      return null;
    }
  }

  /// Periodic cleanup when cache grows large on track changes/logout, etc. —
  /// currently not explicitly called anywhere (the cache is a small map of
  /// Color values, memory pressure is negligible), but available if history grows.
  static void clearCache() => _cache.clear();

  static Color _mapToNearestCurated(Color extracted) {
    final extractedHsl = HSLColor.fromColor(extracted);

    Color nearest = AppColors.curatedAccents.first;
    double bestDistance = double.infinity;

    for (final candidate in AppColors.curatedAccents) {
      final candidateHsl = HSLColor.fromColor(candidate);
      final distance = _hslDistance(extractedHsl, candidateHsl);
      if (distance < bestDistance) {
        bestDistance = distance;
        nearest = candidate;
      }
    }

    return nearest;
  }

  /// Hue circular distance + saturation/lightness weighted — higher priority
  /// is given to hue because human perception identifies color by hue first,
  /// while saturation and lightness act as tie-breakers.
  static double _hslDistance(HSLColor a, HSLColor b) {
    final hueDiff = (a.hue - b.hue).abs();
    final circularHueDiff = hueDiff > 180 ? 360 - hueDiff : hueDiff;
    final normalizedHueDiff = circularHueDiff / 180.0;

    final satDiff = (a.saturation - b.saturation).abs();
    final lightDiff = (a.lightness - b.lightness).abs();

    return (normalizedHueDiff * 0.7) + (satDiff * 0.15) + (lightDiff * 0.15);
  }

  /// Ultimate safety clamp — while the curated palette is designed within
  /// a usable lightness range, this defensive clamp ensures that even if a
  /// color added to `curatedAccents` is too light or too dark, it remains
  /// legible on glow and progress bars (visible against dark backgrounds
  /// without causing eye fatigue).
  static Color _ensureUsableLightness(Color color) {
    final hsl = HSLColor.fromColor(color);
    final clampedLightness = hsl.lightness.clamp(0.35, 0.75);
    if (clampedLightness == hsl.lightness) return color;
    return hsl.withLightness(clampedLightness).toColor();
  }
}