import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:palette_generator/palette_generator.dart';

import '../logging/app_logger.dart';
import 'app_colors.dart';

/// ⚠️ Phase 6 (Smart Player UI & Theme Polish) — Dynamic album-based accent।
///
/// Pipeline:
///   1. Album artwork (local file — CachedArtwork/CacheService দিয়ে আগেই
///      resolve হওয়া path) থেকে `PaletteGenerator` দিয়ে dominant color
///      extract।
///   2. **সরাসরি সেই dominant color ব্যবহার করা হয় না** — কিছু album
///      art থেকে dirty brown/mud green/washed yellow/gray এর মতো
///      unappealing রং বের হতে পারে। তাই extracted color-কে
///      `AppColors.curatedAccents` তালিকার সবচেয়ে কাছেরটাতে (HSL
///      distance দিয়ে) map করা হয় — curated value-ই আসলে UI-তে
///      ব্যবহৃত হয়।
///   3. Contrast validation — curated palette আগে থেকেই যাচাই করা
///      (lightness/saturation বাউন্ডারির মধ্যে), তাই সাধারণত extra
///      normalize লাগে না, কিন্তু defensive হিসেবে চূড়ান্ত রং-এর
///      lightness একটা ব্যবহারযোগ্য রেঞ্জে (০.৩৫–০.৭৫) clamp করা হয় —
///      দেখো `_ensureUsableLightness()`।
///
/// **Performance:** প্রতি track change-এ একবারই extract হয় (per-trackId
/// cache), rebuild-এ recompute হয় না। Low RAM mode-এ blur বন্ধ থাকে
/// (এই ক্লাসের দায়িত্ব না — `CachedArtwork`/player background widget
/// নিজে `PerformanceService.isLowRamMode` চেক করবে) কিন্তু color
/// extraction তখনও চলবে (হালকা, image resize করেই করা হয়)।
class ColorExtractor {
  ColorExtractor._();

  static final _cache = <String, Color>{};

  /// [trackId] দিয়ে cache key — stream/thumbnail URL বদলে গেলেও track
  /// একই থাকলে পুনরায় extract করার দরকার নেই।
  static Future<Color?> extractForTrack({
    required String trackId,
    required String localImagePath,
  }) async {
    final cached = _cache[trackId];
    if (cached != null) return cached;

    try {
      final imageProvider = FileImage(File(localImagePath));

      // ⚠️ পুরো resolution না, ছোট region-count দিয়ে PaletteGenerator
      // চালানো হচ্ছে — extraction দ্রুত রাখতে (per-track একবারই হলেও,
      // large artwork-এ unnecessary CPU/memory এড়ানো ভালো)।
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
      // ⚠️ Extraction ব্যর্থ হলে (corrupt file, decode error) exception
      // propagate করা হয় না — accent শুধু UI enhancement, ব্যর্থ হলে
      // caller গ্র্যাসফুলি `AuroraColors.primary`-তে fallback করবে
      // (দেখো AuroraColors.effectiveAccent)।
      AppLogger.error('Album color extraction failed for $trackId', e);
      return null;
    }
  }

  /// Track বদলে গেলে/logout ইত্যাদিতে cache বড় হতে থাকলে periodic
  /// cleanup — এই মুহূর্তে explicit call কোথাও লাগানো হয়নি (cache ছোট
  /// Color value-এর map, memory pressure নগণ্য), কিন্তু ভবিষ্যতে
  /// history বড় হলে ব্যবহারযোগ্য।
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

  /// Hue circular distance + saturation/lightness weighted — hue-কে
  /// বেশি priority দেওয়া হয়েছে কারণ মানুষ "কোন রং" সেটা hue দিয়েই
  /// প্রথমে বিচার করে, saturation/lightness এখানে tie-breaker।
  static double _hslDistance(HSLColor a, HSLColor b) {
    final hueDiff = (a.hue - b.hue).abs();
    final circularHueDiff = hueDiff > 180 ? 360 - hueDiff : hueDiff;
    final normalizedHueDiff = circularHueDiff / 180.0;

    final satDiff = (a.saturation - b.saturation).abs();
    final lightDiff = (a.lightness - b.lightness).abs();

    return (normalizedHueDiff * 0.7) + (satDiff * 0.15) + (lightDiff * 0.15);
  }

  /// চূড়ান্ত নিরাপত্তা — curated palette নিজেই ব্যবহারযোগ্য lightness
  /// রেঞ্জে বানানো, কিন্তু defensive clamp রাখা হলো যাতে ভবিষ্যতে কেউ
  /// `curatedAccents`-এ নতুন রং যোগ করলেও (যেটা হয়তো খুব হালকা/গাঢ়)
  /// glow/progress-bar-এ ব্যবহারযোগ্য থাকে (dark background-এর উপর
  /// দৃশ্যমান, কিন্তু চোখ ধাঁধানো উজ্জ্বল না)।
  static Color _ensureUsableLightness(Color color) {
    final hsl = HSLColor.fromColor(color);
    final clampedLightness = hsl.lightness.clamp(0.35, 0.75);
    if (clampedLightness == hsl.lightness) return color;
    return hsl.withLightness(clampedLightness).toColor();
  }
}