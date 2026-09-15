import 'package:flutter/material.dart';

/// ⚠️ Phase 6.5 — "Midnight Aurora" Premium Identity (LOCKED, v3).
///
/// This is the ONLY file where raw color hex values are written.
/// Everything else reads through `context.aurora` (see
/// `app_theme_extension.dart`).
///
/// LOCKED BRAND IDENTITY (v3 — 2026-09-10 deep-shade revision):
///   Primary   = #7C3AED (deep Violet)
///   Secondary = #DB2777 (deep Magenta)
///   Core gradient = Violet → Magenta
///
/// v3 revision rationale: v2's brighter pair (#8B5CF6/#EC4899) was
/// replaced with a deeper, more muted shade after reviewing a locked
/// desktop mockup reference — the deeper tone reads as more premium
/// and less "toy-like" against the dark background. This is the SAME
/// palette already applied to the new login screen — this file brings
/// the rest of the app (Home, Now Playing, Library, etc.) in line with
/// it so there's no mismatch between screens.
///
/// No Spotify green. No cyan primary/secondary pair. Album-art extracted
/// colors may influence specific touchpoints (player glow, progress bar,
/// mini-player accent), but Violet→Magenta remains the permanent
/// fallback / structural identity — sidebar active-states, buttons,
/// hero badges, and gradients always resolve to this pair unless an
/// album accent is actively overriding a touchpoint-specific value.
class AppColors {
  AppColors._();

  // ── Dark (primary variant) — v3: root background deepened to match
  // login screen (#0A0B14, was #050810) ───────────────────────────────
  static const darkBackground = Color(0xFF0A0B14);
  static const darkSurface = Color(0xFF14151F);
  static const darkSurfaceRaised = Color(0xFF171D2E);
  static const darkSurfaceElevated = Color(0xFF1B1C29);

  // ── AMOLED (secondary variant — true black) ─────────────────────────
  static const amoledBackground = Color(0xFF000000);
  static const amoledSurface = Color(0xFF0A0A0A);
  static const amoledSurfaceRaised = Color(0xFF121212);
  static const amoledSurfaceElevated = Color(0xFF1A1A1A);

  // ── Sidebar / Right-Panel specific (desktop) — new in v3, matches
  // the locked desktop mockup (slightly deeper than root background) ──
  static const sidebarBackground = Color(0xFF0D0E18);

  // ── Brand (LOCKED v3 — deep Violet → deep Magenta) ──────────────────
  static const primary = Color(0xFF7C3AED); // Deep Violet
  static const secondary = Color(0xFFDB2777); // Deep Magenta

  /// The signature gradient — hero cards, primary buttons, active nav
  /// indicators, badges. Angled top-left → bottom-right per the
  /// mockup's diagonal energy (not a flat horizontal blend).
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [primary, secondary],
  );

  // ── Text ─────────────────────────────────────────────────────────────
  static const textPrimary = Color(0xFFFFFFFF);
  static const textSecondary = Color(0xFF9CA3AF);
  static const textTertiary = Color(0xFF6B7280);
  static const textDisabled = Color(0xFF4B5468);

  // ── Semantic ─────────────────────────────────────────────────────────
  static const error = Color(0xFFDB2777);
  static const success = Color(0xFF10B981);

  // ── Glass panel base (Player-context only — heavy glass is reserved
  // for Player screens, Home/Discovery uses PremiumCard instead) ──────
  static const glassTintDark = Color(0xFFFFFFFF);
  static const glassBorderDark = Color(0x1FFFFFFF);

  // ── Neutral elevation shadow (what makes PremiumCard "float" without
  // needing a colored glow) ────────────────────────────────────────────
  static const shadowColor = Color(0xFF000000);

  /// Bottom-to-top dark gradient overlaid on hero/rail card artwork so
  /// title text stays readable regardless of the underlying image.
  /// Updated to match v3's deeper background tone.
  static const cardScrimGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xE60A0B14), Color(0x000A0B14)],
  );

  /// ⚠️ Curated Aurora accent palette (v3 — retuned to sit well against
  /// the deeper primary/secondary pair). `ColorExtractor` maps
  /// extracted album-art dominant color to the nearest of these via
  /// HSL distance — raw dominant color is never used directly.
  static const List<Color> curatedAccents = [
    Color(0xFFFBBF24), // Amber
    Color(0xFF3B82F6), // Electric Blue
    Color(0xFF9333EA), // Violet (vivid, distinct from primary)
    Color(0xFFE11D48), // Crimson/Rose
    Color(0xFF10B981), // Emerald
    primary, // Midnight Aurora Primary — neutral/purple art fallback
    secondary, // Midnight Aurora Secondary — warm/pink art fallback
  ];
}
