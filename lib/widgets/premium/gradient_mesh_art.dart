import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_colors.dart';

/// Phase 6.5 Premium Design System — the new standard placeholder art
/// for any card that doesn't have real cover art yet (empty playlists,
/// Daily-Mix-style generated rails, etc). Replaces plain solid-color /
/// icon placeholders everywhere per developer decision this batch.
///
/// Deterministic: the same [seed] always produces the same blob
/// arrangement and color pair, so a given playlist/mix's placeholder
/// doesn't visually shift between rebuilds. Different seeds produce
/// visually distinct results (seed hashCode drives blob positions,
/// radii, and which curated-accent pair is used).
///
/// Visual approach: 2–3 soft, blurred, overlapping radial blobs in
/// brand-adjacent colors, layered over a dark base — approximates the
/// "wavy color blend" look from the mockup's Daily Mix cards without
/// needing an actual custom painter shader (BackdropFilter blur over
/// simple circles is cheap and looks equivalent at card sizes).
class GradientMeshArt extends StatelessWidget {
  const GradientMeshArt({
    super.key,
    required this.seed,
    this.borderRadius = const BorderRadius.all(Radius.circular(16)),
  });

  final String seed;
  final BorderRadius borderRadius;

  /// Picks 2 colors from the curated accent palette (+ the locked
  /// primary/secondary pair are already in that list) based on the
  /// seed's hash — deterministic per seed, varied across seeds.
  (Color, Color) _colorsForSeed(int hash) {
    final palette = AppColors.curatedAccents;
    final i1 = hash.abs() % palette.length;
    var i2 = (hash.abs() ~/ palette.length) % palette.length;
    if (i2 == i1) i2 = (i2 + 1) % palette.length;
    return (palette[i1], palette[i2]);
  }

  @override
  Widget build(BuildContext context) {
    final hash = seed.hashCode;
    final rng = Random(hash);
    final (colorA, colorB) = _colorsForSeed(hash);

    return ClipRRect(
      borderRadius: borderRadius,
      child: Container(
        color: AppColors.darkBackground,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final w = constraints.maxWidth.isFinite ? constraints.maxWidth : 200.0;
            final h = constraints.maxHeight.isFinite ? constraints.maxHeight : 200.0;

            return Stack(
              fit: StackFit.expand,
              children: [
                // Base dark gradient so the blobs have something to
                // sit on top of even before blur softens the edges.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                      colors: [
                        Color.lerp(AppColors.darkBackground, colorA, 0.18)!,
                        Color.lerp(AppColors.darkBackground, colorB, 0.14)!,
                      ],
                    ),
                  ),
                ),
                _Blob(
                  color: colorA,
                  center: Offset(w * (0.2 + rng.nextDouble() * 0.3), h * (0.15 + rng.nextDouble() * 0.3)),
                  radius: w * (0.55 + rng.nextDouble() * 0.25),
                ),
                _Blob(
                  color: colorB,
                  center: Offset(w * (0.55 + rng.nextDouble() * 0.3), h * (0.55 + rng.nextDouble() * 0.35)),
                  radius: w * (0.5 + rng.nextDouble() * 0.3),
                ),
                // Third, smaller accent blob using a blend of both
                // colors for extra depth without introducing a third
                // hue that could clash.
                _Blob(
                  color: Color.lerp(colorA, colorB, 0.5)!,
                  center: Offset(w * (0.4 + rng.nextDouble() * 0.2), h * (0.7 + rng.nextDouble() * 0.2)),
                  radius: w * (0.35 + rng.nextDouble() * 0.15),
                ),
                // Blur pass — merges the blobs into soft wavy color
                // fields instead of hard-edged circles.
                BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
                  child: const SizedBox.expand(),
                ),
                // Subtle bottom scrim so any overlaid text (rare —
                // most callers put title/subtitle below the art, not
                // on top of it) stays legible if ever used that way.
                DecoratedBox(
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.center,
                      colors: [Colors.black.withOpacity(0.25), Colors.transparent],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class _Blob extends StatelessWidget {
  const _Blob({required this.color, required this.center, required this.radius});

  final Color color;
  final Offset center;
  final double radius;

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: center.dx - radius,
      top: center.dy - radius,
      child: Container(
        width: radius * 2,
        height: radius * 2,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: color.withOpacity(0.85),
        ),
      ),
    );
  }
}