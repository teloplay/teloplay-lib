import 'package:flutter/material.dart';

/// TeloPlay Signature Identity — "Midnight Neon Aurora" (Matched directly with Master Mockup).
class AppColors {
  AppColors._();

  // ── Obsidian & Deep Midnight Surfaces ───────────────────────────────
  // ⚠️ Base moved #090810 → #0A0C10: the old value had a violet cast
  // strong enough that neutral artwork looked tinted. #0A0C10 is the
  // design-brief neutral near-black; the violet identity now comes from
  // [primary]/[accentGradient] only, which is how it should read.
  static const darkBackground = Color(0xFF0A0C10);
  static const darkSurface = Color(0xFF11141B);
  static const darkSurfaceRaised = Color(0xFF181C25);
  static const darkSurfaceElevated = Color(0xFF212633);

  // ── AMOLED (True Pitch Black) ───────────────────────────────────────
  static const amoledBackground = Color(0xFF000000);
  static const amoledSurface = Color(0xFF0A0C10);
  static const amoledSurfaceRaised = Color(0xFF14171E);
  static const amoledSurfaceElevated = Color(0xFF1E222B);

  // ── Left Sidebar & Top Chrome ───────────────────────────────────────
  static const sidebarBackground = Color(0xFF0D1016);


  // ── Brand Signature: Electric Violet & Vibrant Magenta ──────────────
  static const primary = Color(0xFF8B5CF6); // Electric Violet
  static const secondary = Color(0xFFEC4899); // Vibrant Pink / Magenta
  static const accentCyan = Color(0xFF06B6D4); // Neon Cyan for Stats/Indicators
  static const accentAmber = Color(0xFFF59E0B);

  /// The Signature TeloPlay Diagonal Gradient (Hero, Buttons, Badges)
  static const accentGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0xFF8B5CF6), Color(0xFFD946EF), Color(0xFFEC4899)],
  );

  /// Vibrant Glow Gradient for Player & Card highlights
  static const glowGradient = LinearGradient(
    begin: Alignment.topLeft,
    end: Alignment.bottomRight,
    colors: [Color(0x338B5CF6), Color(0x22EC4899)],
  );

  // ── Text & Typography Colors ─────────────────────────────────────────
  // ⚠️ Contrast repairs (WCAG AA = 4.5:1 for body text):
  //   textPrimary   #FFFFFF → #F2F1F7  — design brief explicitly says
  //     "NEVER use pure white for large body text (too harsh)". Pure
  //     white stays reserved for small/emphasis text only.
  //   textSecondary #A5A1B8 → #B4B1C4  — old value was ~7.5:1 on the old
  //     background but dropped under 4.5:1 once stacked withOpacity(0.6)
  //     in several screens. Raising the token fixes every call site at once.
  //   textTertiary  #6E6987 → #8B87A0  — was ~3.1:1 (fail).
  //   textDisabled  #4A465E → #5E5A72  — intentionally below AA (it's
  //     disabled state), but no longer invisible.
  static const textPrimary = Color(0xFFF2F1F7);
  static const textSecondary = Color(0xFFB4B1C4);
  static const textTertiary = Color(0xFF8B87A0);
  static const textDisabled = Color(0xFF5E5A72);

  /// Reserved for small/emphasis text where maximum punch is wanted
  /// (numerals in the player, active nav label). Never for body copy.
  static const textEmphasis = Color(0xFFFFFFFF);


  // ── Semantic Colors ──────────────────────────────────────────────────
  static const error = Color(0xFFF43F5E);
  static const success = Color(0xFF10B981);

  // ── Glass Panels & Borders ──────────────────────────────────────────
  static const glassTintDark = Color(0xFFFFFFFF);
  static const glassBorderDark = Color(0x1FFFFFFF);
  static const glassBorderGlow = Color(0x338B5CF6);

  /// Resolved glass panel fills. The old code did
  /// `glassTint.withOpacity(0.06)` inline in [GlassContainer], which on a
  /// #0A0C10 base is a 6%-white wash — indistinguishable from empty
  /// background. Frosted panels need ~10-14% to actually read as glass,
  /// and AMOLED (pure black base) needs slightly more to clear the same
  /// perceptual threshold.
  static const glassFillHigh = Color(0x1FFFFFFF); // dark theme, 12%
  static const glassFillHighStrong = Color(0x2EFFFFFF); // dark, 18%
  static const glassFillAmoled = Color(0x24FFFFFF); // amoled, 14%
  static const glassFillAmoledStrong = Color(0x33FFFFFF); // amoled, 20%

  // ── Elevation Shadows ───────────────────────────────────────────────
  static const shadowColor = Color(0xFF000000);

  /// Bottom-to-top scrim for artwork and hero cards. Colors must track
  /// [darkBackground] (#0A0C10) — they were hardcoded to the old #090810,
  /// which would leave a faint visible edge once the base changed.
  static const cardScrimGradient = LinearGradient(
    begin: Alignment.bottomCenter,
    end: Alignment.topCenter,
    colors: [Color(0xF00A0C10), Color(0x800A0C10), Color(0x000A0C10)], // Updated to match darkBackground
  );

  /// Curated dynamic accents for albums and waveform visualizations
  static const List<Color> curatedAccents = [
    Color(0xFF8B5CF6), // Violet
    Color(0xFFEC4899), // Magenta
    Color(0xFF06B6D4), // Cyan
    Color(0xFF3B82F6), // Electric Blue
    Color(0xFF10B981), // Emerald
    Color(0xFFF59E0B), // Amber
    Color(0xFFF43F5E), // Coral
  ];
}