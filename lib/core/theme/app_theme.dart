import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_theme_extension.dart';

/// ⚠️ Phase 6 — "Midnight Aurora" identity, runtime-switchable Dark/AMOLED।
/// Light theme ইচ্ছাকৃতভাবে এখনো নেই (পরের phase-এ)।
enum AppThemeMode { dark, amoled }

class AppTheme {
  AppTheme._();

  static ThemeData themeFor(AppThemeMode mode) {
    final aurora = switch (mode) {
      AppThemeMode.dark => AuroraColors.dark,
      AppThemeMode.amoled => AuroraColors.amoled,
    };

    final base = ThemeData.dark(useMaterial3: true);

    return base.copyWith(
      scaffoldBackgroundColor: aurora.background,
      primaryColor: aurora.primary,
      colorScheme: ColorScheme.dark(
        primary: aurora.primary,
        secondary: aurora.secondary,
        surface: aurora.surface,
        error: aurora.error,
      ),
      textTheme: base.textTheme.apply(
        bodyColor: aurora.textPrimary,
        displayColor: aurora.textPrimary,
      ),
      // ⚠️ Design brief: type scale-এ deliberate weight/spacing —
      // track title-এর জন্য bold+tight letterSpacing, caption/time-stamp-এর
      // জন্য utility-style tabular figures feel (FontFeature দিয়ে ঘনিষ্ঠ,
      // পুরোপুরি monospace না করে regular UI font-ই রাখা হচ্ছে —
      // cross-platform font availability নিয়ে ঝুঁকি না নিতে)।
      extensions: [aurora],
      splashFactory: InkRipple.splashFactory,
      dividerColor: aurora.glassBorder,
    );
  }

  static ThemeData get dark => themeFor(AppThemeMode.dark);
  static ThemeData get amoled => themeFor(AppThemeMode.amoled);

  // ── টাইপ স্কেল shorthand (title/body/caption-এর deliberate ব্যবহার) ──
  // ⚠️ এগুলো widget-এ সরাসরি ব্যবহার হবে, কোনো নতুন raw TextStyle না
  // বানিয়ে — track title বনাম caption-এর মধ্যে স্পষ্ট personality ফারাক।
  static const trackTitleStyle = TextStyle(
    fontSize: 20,
    fontWeight: FontWeight.w700,
    letterSpacing: -0.3,
    height: 1.2,
  );

  static const trackArtistStyle = TextStyle(
    fontSize: 14,
    fontWeight: FontWeight.w500,
    letterSpacing: 0.1,
  );

  static const timeStampStyle = TextStyle(
    fontSize: 12,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
    fontFeatures: [FontFeature.tabularFigures()],
  );

  static const sectionLabelStyle = TextStyle(
    fontSize: 11,
    fontWeight: FontWeight.w700,
    letterSpacing: 1.1,
  );
}