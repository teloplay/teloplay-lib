import 'package:flutter/material.dart';

/// ⚠️ Phase 6.5 — "Midnight Aurora" Premium Identity (LOCKED, v2).
///
/// This is the ONLY file where raw color hex values are written.
/// Everything else reads through `context.aurora` (see
/// `app_theme_extension.dart`).
///
/// LOCKED BRAND IDENTITY (developer decision, Phase 6.5 UI redesign):
///   Primary   = #8B5CF6 (Violet)
///   Secondary = #EC4899 (Magenta)
///   Core gradient = Violet → Magenta
///
/// No Spotify green. No cyan primary/secondary pair. Album-art extracted
/// colors may influence specific touchpoints (player glow, progress bar,
/// mini-player accent), but Violet→Magenta remains the permanent
/// fallback / structural identity — sidebar active-states, buttons,
/// hero badges, and gradients always resolve to this pair unless an
/// album accent is actively overriding a touchpoint-specific value.
///
/// v2 revision rationale (design audit, this batch): the previous
/// surface hierarchy (#0B0F1A / #141B2D / #1B2338) had too little
/// contrast between adjacent levels — cards didn't visually "float."
/// This version goes deeper on background and spreads the surface
/// levels further apart, and adds a 4th elevation level
/// (surfaceElevated) for hover/active/modal states that didn't have
/// a home before.
class AppColors {
  AppColors._();

  // ── Dark (primary variant) — v2: deeper, more separation ───────────
  static const darkBackground = Color(0xFF050810);
  static const darkSurface = Color(0xFF0F1420);
  static const darkSurfaceRaised = Color(0xFF171D2E);
  static const darkSurfaceElevated = Color(0xFF1E2740);

  // ── AMOLED (secondary variant — true black) ─────────────────────────
  static const amoledBackground = Color(0xFF000000);
  static const amoledSurface = Color(0xFF0A0A0A);
  static const amoledSurfaceRaised = Color(0xFF121212);
  static const amoledSurfaceElevated = Color(0xFF1A1A1A);

  // ── Brand (LOCKED — Violet → Magenta) ───────────────────────────────
  static const primary = Color(0xFF8B5CF6); // Violet
  static const secondary = Color(0xFFEC4899); // Magenta

  /// The signature gradient — hero cards, primary buttons, active nav
  /// indicators, badges. Angled top-left → bottom-right per the
  /// mockup's diagonal energy (not a flat horizontal blend).
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  // ── Text ─────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFF7F7FA);
  static const textSecondary = Color(0xFF9098AC);
  static const textDisabled = Color(0xFF4B5468);

  // ── Semantic ─────────────────────────────────────────────────────────
  static const error = Color(0xFFF43F5E);
  static const success = Color(0xFF34D399);

  // ── Glass panel base (Player-context only — see design audit note:
  // heavy glass is now reserved for Player screens, Home/Discovery
  // uses PremiumCard instead) ──────────────────────────────────────────
  static const glassTintDark = Color(0xFFFFFFFF);
  static const glassBorderDark = Color(0x1FFFFFFF);

  // ── Neutral elevation shadow (new — was missing entirely before;
  // this is what makes PremiumCard "float" without needing a colored
  // glow) ──────────────────────────────────────────────────────────────
  static const shadowColor = Color(0xFF000000);

  /// Bottom-to-top dark gradient overlaid on hero/rail card artwork so
  /// title text stays readable regardless of the underlying image.
  static const cardScrimGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xE6050810), Color(0x00050810)],
  );

  /// ⚠️ Curated Aurora accent palette (v2 — more vivid/saturated than
  /// v1's "safe" Material-adjacent tones). `ColorExtractor` maps
  /// extracted album-art dominant color to the nearest of these via
  /// HSL distance — raw dominant color is never used directly.
  static const List<Color> curatedAccents = [
    Color(0xFFFBBF24), // Amber (brighter)
    Color(0xFF3B82F6), // Electric Blue
    Color(0xFFA855F7), // Violet (vivid)
    Color(0xFFF43F5E), // Crimson/Rose
    Color(0xFF34D399), // Emerald
    primary, // Midnight Aurora Primary — neutral/purple art fallback
    secondary, // Midnight Aurora Secondary — warm/pink art fallback
  ];
}