import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

/// TeloPlay type system — Plus Jakarta Sans.
///
/// Why this file exists: `google_fonts` was already a dependency but no
/// widget ever set a `fontFamily`, so every screen rendered in the OS
/// default (Segoe UI on Windows, Roboto on Android). Typography is ~80%
/// of what "premium" actually means — a real typeface with a deliberate
/// scale does more than any gradient.
///
/// Two-layer design:
///   1. [textTheme] — wired into `ThemeData.textTheme`, so all the
///      implicit `Theme.of(context).textTheme.*` call sites across the
///      app upgrade for free.
///   2. Named styles below — for the hand-rolled `TextStyle(...)` call
///      sites that need an explicit hierarchy (track title vs caption).
///
/// Sizes follow the TeloPlay design brief scale (11/12/14/16/20/24/32).
/// Headlines get negative letter-spacing (tight = confident); overlines
/// get positive spacing + uppercase (utility labels).
class AppTypography {
  AppTypography._();

  /// The one font family. Kept as a named constant so a future swap
  /// (or a self-hosted fallback for offline builds) is a one-line change.
  static const String fontFamily = 'Plus Jakarta Sans';

  /// Base TextTheme. Every style gets the family; colors are applied by
  /// `AppTheme` via `.apply(bodyColor:..., displayColor:...)` so this
  /// stays color-agnostic and AMOLED/Dark share it.
  static TextTheme get textTheme => GoogleFonts.plusJakartaSansTextTheme(
        const TextTheme(
          // Display / Headline — hero titles, big numerals.
          displayLarge: TextStyle(fontSize: 32, fontWeight: FontWeight.w700, letterSpacing: -0.8, height: 1.15),
          displayMedium: TextStyle(fontSize: 28, fontWeight: FontWeight.w700, letterSpacing: -0.6, height: 1.18),
          displaySmall: TextStyle(fontSize: 24, fontWeight: FontWeight.w700, letterSpacing: -0.5, height: 1.2),

          // Title — section headers, card titles, app bar.
          headlineMedium: TextStyle(fontSize: 22, fontWeight: FontWeight.w700, letterSpacing: -0.4, height: 1.25),
          headlineSmall: TextStyle(fontSize: 20, fontWeight: FontWeight.w700, letterSpacing: -0.3, height: 1.25),
          titleLarge: TextStyle(fontSize: 18, fontWeight: FontWeight.w700, letterSpacing: -0.2, height: 1.3),
          titleMedium: TextStyle(fontSize: 16, fontWeight: FontWeight.w600, letterSpacing: -0.1, height: 1.35),
          titleSmall: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0, height: 1.4),

          // Body — 1.5 line-height for readability, per design brief.
          bodyLarge: TextStyle(fontSize: 16, fontWeight: FontWeight.w400, height: 1.5),
          bodyMedium: TextStyle(fontSize: 14, fontWeight: FontWeight.w400, height: 1.5),
          bodySmall: TextStyle(fontSize: 12, fontWeight: FontWeight.w400, height: 1.45),

          // Label — buttons, chips, nav labels.
          labelLarge: TextStyle(fontSize: 14, fontWeight: FontWeight.w600, letterSpacing: 0.1, height: 1.3),
          labelMedium: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0.2, height: 1.3),
          labelSmall: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, letterSpacing: 0.3, height: 1.3),
        ),
      );

  // ── Named styles for explicit call sites ─────────────────────────
  // These exist so screens stop inventing `fontSize: 13, w700` inline.

  /// Now-playing / hero track title. Tight, confident.
  static TextStyle get trackTitle => GoogleFonts.plusJakartaSans(
        fontSize: 20,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.3,
        height: 1.2,
      );

  /// Artist / album line under a track title.
  static TextStyle get trackArtist => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w500,
        letterSpacing: 0.1,
      );

  /// Rail/grid card title (smaller than the player's).
  static TextStyle get cardTitle => GoogleFonts.plusJakartaSans(
        fontSize: 14,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        height: 1.3,
      );

  /// Rail/grid card subtitle.
  static TextStyle get cardSubtitle => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w500,
        letterSpacing: 0,
        height: 1.35,
      );

  /// Section header inside a screen ("Recently played").
  static TextStyle get sectionTitle => GoogleFonts.plusJakartaSans(
        fontSize: 18,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.2,
        height: 1.3,
      );

  /// Uppercase utility label ("YOUR SPACE", "CONTINUE LISTENING").
  static TextStyle get overline => GoogleFonts.plusJakartaSans(
        fontSize: 11,
        fontWeight: FontWeight.w700,
        letterSpacing: 1.1,
        height: 1.3,
      );

  /// Time stamps / counters — tabular figures so digits don't jitter
  /// while the progress bar ticks.
  static TextStyle get timeStamp => GoogleFonts.plusJakartaSans(
        fontSize: 12,
        fontWeight: FontWeight.w600,
        letterSpacing: 0.2,
        fontFeatures: const [FontFeature.tabularFigures()],
      );

  /// Primary button label.
  static TextStyle get button => GoogleFonts.plusJakartaSans(
        fontSize: 15,
        fontWeight: FontWeight.w700,
        letterSpacing: 0.1,
      );
}
