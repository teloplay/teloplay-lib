import 'package:flutter/material.dart';

import 'app_spacing.dart';
import 'app_theme_extension.dart';
import 'app_typography.dart';

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
        onSurface: aurora.textPrimary,
        onBackground: aurora.textPrimary,
        onPrimary: Colors.black,
        outline: aurora.glassBorder,
      ),
      // ⚠️ Plus Jakarta Sans wired here so every implicit
      // `Theme.of(context).textTheme.*` call site upgrades at once.
      // The old theme left this as the OS default, which was the single
      // biggest reason the app read as "unpolished".
      textTheme: AppTypography.textTheme.apply(
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
      // ── Component themes: kill the "default Flutter widget" look ──
      // These are the widgets that most often leak straight out of
      // Material. Setting them centrally means screens don't have to
      // remember to style each one individually.
      appBarTheme: AppBarTheme(
        backgroundColor: aurora.background,
        foregroundColor: aurora.textPrimary,
        elevation: 0,
        centerTitle: false,
        scrolledUnderElevation: 0,
        titleTextStyle: AppTypography.sectionTitle.copyWith(color: aurora.textPrimary),
        iconTheme: IconThemeData(color: aurora.textPrimary),
      ),
      cardTheme: CardThemeData(
        color: aurora.surfaceRaised,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        clipBehavior: Clip.antiAlias,
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: aurora.primary,
          foregroundColor: Colors.white,
          elevation: 0,
          minimumSize: const Size(48, 48),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusPill)),
          textStyle: AppTypography.button,
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: aurora.surfaceRaised,
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: aurora.glassBorder),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: aurora.glassBorder),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: aurora.primary, width: 1.4),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
          borderSide: BorderSide(color: aurora.error),
        ),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: aurora.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppSpacing.radiusXl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: aurora.surfaceElevated,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusLg)),
        titleTextStyle: AppTypography.sectionTitle.copyWith(color: aurora.textPrimary),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: aurora.textPrimary,
        unselectedLabelColor: aurora.textSecondary,
        indicatorColor: aurora.primary,
        dividerColor: Colors.transparent,
        labelStyle: AppTypography.button,
        unselectedLabelStyle: AppTypography.button.copyWith(fontWeight: FontWeight.w500),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: aurora.surfaceRaised,
        side: BorderSide(color: aurora.glassBorder),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusPill)),
        labelStyle: AppTypography.cardSubtitle.copyWith(color: aurora.textPrimary),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      ),
      dividerTheme: DividerThemeData(color: aurora.glassBorder, thickness: 1, space: 1),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: aurora.primary,
        linearTrackColor: aurora.surfaceElevated,
      ),
      listTileTheme: ListTileThemeData(
        iconColor: aurora.textSecondary,
        textColor: aurora.textPrimary,
        minVerticalPadding: 8,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppSpacing.radiusMd)),
      ),
      iconTheme: IconThemeData(color: aurora.textPrimary, size: 22),
    );
  }

  static ThemeData get dark => themeFor(AppThemeMode.dark);
  static ThemeData get amoled => themeFor(AppThemeMode.amoled);

  // ── টাইপ স্কেল shorthand (title/body/caption-এর deliberate ব্যবহার) ──
  // ⚠️ Kept as thin aliases over [AppTypography] so the existing call
  // sites (`AppTheme.trackTitleStyle` etc.) keep compiling unchanged,
  // while the actual definitions live in one place. New code should
  // import app_typography.dart directly.
  //
  // Not `const` — GoogleFonts.* is a runtime lookup, so these can't be
  // compile-time constants. All existing usages are inside build()
  // methods, so static getters are a drop-in replacement.
  static TextStyle get trackTitleStyle => AppTypography.trackTitle;
  static TextStyle get trackArtistStyle => AppTypography.trackArtist;
  static TextStyle get timeStampStyle => AppTypography.timeStamp;
  static TextStyle get sectionLabelStyle => AppTypography.overline;
}