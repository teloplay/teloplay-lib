import 'package:flutter/material.dart';

import 'app_colors.dart';

/// ⚠️ Phase 6.5 — Theme architecture (unchanged structure from Phase 6,
/// values updated for the Premium Design System v2 — see design audit).
/// ThemeExtension-based, centralized color tokens, runtime theme
/// switching, album-art accent compatibility.
///
/// Screens/widgets access this via:
/// ```dart
/// final aurora = context.aurora;
/// ```
///
/// New in v2: [surfaceElevated] (hover/active/modal level, was missing),
/// [shadowColor] (neutral elevation shadow — makes PremiumCard "float"
/// without a colored glow), [accentGradient] (the locked Violet→Magenta
/// signature gradient), [cardScrimGradient] (bottom-to-top dark overlay
/// for text-over-artwork readability on hero/rail cards).
///
/// `albumAccent` remains the only field that changes at runtime (album
/// art extraction) — everything else is fixed per theme variant
/// (Dark/AMOLED). Falls back to `primary` via [effectiveAccent] when no
/// album accent is available yet.
@immutable
class AuroraColors extends ThemeExtension<AuroraColors> {
  final Color background;
  final Color surface;
  final Color surfaceRaised;
  final Color surfaceElevated;
  final Color primary;
  final Color secondary;
  final Color textPrimary;
  final Color textSecondary;
  final Color textDisabled;
  final Color error;
  final Color success;
  final Color glassTint;
  final Color glassBorder;
  final Color shadowColor;
  final Gradient accentGradient;
  final Gradient cardScrimGradient;

  /// Album art থেকে extract + curated-map করা runtime accent। Player
  /// glow, progress bar, player background tint, mini-player accent —
  /// শুধু এই ৪ জায়গায় ব্যবহৃত হবে।
  final Color? albumAccent;

  const AuroraColors({
    required this.background,
    required this.surface,
    required this.surfaceRaised,
    required this.surfaceElevated,
    required this.primary,
    required this.secondary,
    required this.textPrimary,
    required this.textSecondary,
    required this.textDisabled,
    required this.error,
    required this.success,
    required this.glassTint,
    required this.glassBorder,
    required this.shadowColor,
    required this.accentGradient,
    required this.cardScrimGradient,
    this.albumAccent,
  });

  /// Album accent না থাকলে safe fallback (primary)।
  Color get effectiveAccent => albumAccent ?? primary;

  static const dark = AuroraColors(
    background: AppColors.darkBackground,
    surface: AppColors.darkSurface,
    surfaceRaised: AppColors.darkSurfaceRaised,
    surfaceElevated: AppColors.darkSurfaceElevated,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textDisabled: AppColors.textDisabled,
    error: AppColors.error,
    success: AppColors.success,
    glassTint: AppColors.glassTintDark,
    glassBorder: AppColors.glassBorderDark,
    shadowColor: AppColors.shadowColor,
    accentGradient: AppColors.accentGradient,
    cardScrimGradient: AppColors.cardScrimGradient,
  );

  static const amoled = AuroraColors(
    background: AppColors.amoledBackground,
    surface: AppColors.amoledSurface,
    surfaceRaised: AppColors.amoledSurfaceRaised,
    surfaceElevated: AppColors.amoledSurfaceElevated,
    primary: AppColors.primary,
    secondary: AppColors.secondary,
    textPrimary: AppColors.textPrimary,
    textSecondary: AppColors.textSecondary,
    textDisabled: AppColors.textDisabled,
    error: AppColors.error,
    success: AppColors.success,
    glassTint: AppColors.glassTintDark,
    glassBorder: AppColors.glassBorderDark,
    shadowColor: AppColors.shadowColor,
    accentGradient: AppColors.accentGradient,
    cardScrimGradient: AppColors.cardScrimGradient,
  );

  @override
  AuroraColors copyWith({
    Color? background,
    Color? surface,
    Color? surfaceRaised,
    Color? surfaceElevated,
    Color? primary,
    Color? secondary,
    Color? textPrimary,
    Color? textSecondary,
    Color? textDisabled,
    Color? error,
    Color? success,
    Color? glassTint,
    Color? glassBorder,
    Color? shadowColor,
    Gradient? accentGradient,
    Gradient? cardScrimGradient,
    Color? albumAccent,
    bool clearAlbumAccent = false,
  }) {
    return AuroraColors(
      background: background ?? this.background,
      surface: surface ?? this.surface,
      surfaceRaised: surfaceRaised ?? this.surfaceRaised,
      surfaceElevated: surfaceElevated ?? this.surfaceElevated,
      primary: primary ?? this.primary,
      secondary: secondary ?? this.secondary,
      textPrimary: textPrimary ?? this.textPrimary,
      textSecondary: textSecondary ?? this.textSecondary,
      textDisabled: textDisabled ?? this.textDisabled,
      error: error ?? this.error,
      success: success ?? this.success,
      glassTint: glassTint ?? this.glassTint,
      glassBorder: glassBorder ?? this.glassBorder,
      shadowColor: shadowColor ?? this.shadowColor,
      accentGradient: accentGradient ?? this.accentGradient,
      cardScrimGradient: cardScrimGradient ?? this.cardScrimGradient,
      albumAccent: clearAlbumAccent ? null : (albumAccent ?? this.albumAccent),
    );
  }

  @override
  AuroraColors lerp(ThemeExtension<AuroraColors>? other, double t) {
    if (other is! AuroraColors) return this;
    return AuroraColors(
      background: Color.lerp(background, other.background, t)!,
      surface: Color.lerp(surface, other.surface, t)!,
      surfaceRaised: Color.lerp(surfaceRaised, other.surfaceRaised, t)!,
      surfaceElevated: Color.lerp(surfaceElevated, other.surfaceElevated, t)!,
      primary: Color.lerp(primary, other.primary, t)!,
      secondary: Color.lerp(secondary, other.secondary, t)!,
      textPrimary: Color.lerp(textPrimary, other.textPrimary, t)!,
      textSecondary: Color.lerp(textSecondary, other.textSecondary, t)!,
      textDisabled: Color.lerp(textDisabled, other.textDisabled, t)!,
      error: Color.lerp(error, other.error, t)!,
      success: Color.lerp(success, other.success, t)!,
      glassTint: Color.lerp(glassTint, other.glassTint, t)!,
      glassBorder: Color.lerp(glassBorder, other.glassBorder, t)!,
      shadowColor: Color.lerp(shadowColor, other.shadowColor, t)!,
      // Gradients don't lerp meaningfully between two fixed brand
      // gradients (they're constant, not theme-variant) — just swap at
      // the midpoint rather than attempting Gradient.lerp, which would
      // produce a muddy in-between that doesn't correspond to any real
      // design state.
      accentGradient: t < 0.5 ? accentGradient : other.accentGradient,
      cardScrimGradient: t < 0.5 ? cardScrimGradient : other.cardScrimGradient,
      albumAccent: Color.lerp(
        albumAccent ?? primary,
        other.albumAccent ?? other.primary,
        t,
      ),
    );
  }
}

/// সুবিধার জন্য shorthand: `context.aurora.primary` ইত্যাদি।
extension AuroraColorsX on BuildContext {
  AuroraColors get aurora =>
      Theme.of(this).extension<AuroraColors>() ?? AuroraColors.dark;
}