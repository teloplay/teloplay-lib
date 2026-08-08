import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../../core/theme/app_theme_extension.dart';
import '../profile_settings_providers.dart';
import 'profile_section.dart';

/// ⚠️ Phase 6.5 Batch 6 (Batch B) — Playback & Experience section:
/// Theme Mode (Dark/AMOLED — Light এখনো নেই, roadmap Phase 6 সিদ্ধান্ত
/// অনুযায়ী), Dynamic Album Colors, Reduce Motion, Battery Saver UI
/// Mode, + Crossfade/Audio Quality future placeholders (disabled,
/// "Coming soon" — roadmap Phase 7+ আইটেম, এখনই কার্যকর করা হয়নি)।
class PlaybackExperienceSection extends ConsumerWidget {
  const PlaybackExperienceSection({super.key});

  void _showThemePicker(BuildContext context, WidgetRef ref, AppThemeMode current) {
    final aurora = context.aurora;
    showModalBottomSheet(
      context: context,
      backgroundColor: aurora.surfaceRaised,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 12),
              Text(
                'Theme mode',
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.w700,
                  color: aurora.textPrimary,
                ),
              ),
              const SizedBox(height: 8),
              RadioListTile<AppThemeMode>(
                title: Text('Dark', style: TextStyle(color: aurora.textPrimary)),
                subtitle: Text(
                  'Balanced dark theme',
                  style: TextStyle(color: aurora.textSecondary, fontSize: 12),
                ),
                value: AppThemeMode.dark,
                groupValue: current,
                activeColor: aurora.primary,
                onChanged: (mode) {
                  if (mode != null) ref.read(themeModeProvider.notifier).setMode(mode);
                  Navigator.of(sheetContext).pop();
                },
              ),
              RadioListTile<AppThemeMode>(
                title: Text('AMOLED', style: TextStyle(color: aurora.textPrimary)),
                subtitle: Text(
                  'True black — saves battery on OLED screens',
                  style: TextStyle(color: aurora.textSecondary, fontSize: 12),
                ),
                value: AppThemeMode.amoled,
                groupValue: current,
                activeColor: aurora.primary,
                onChanged: (mode) {
                  if (mode != null) ref.read(themeModeProvider.notifier).setMode(mode);
                  Navigator.of(sheetContext).pop();
                },
              ),
              const SizedBox(height: 12),
            ],
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;

    final themeModeAsync = ref.watch(themeModeProvider);
    final dynamicColorsAsync = ref.watch(dynamicColorsProvider);
    final reduceMotionAsync = ref.watch(reduceMotionProvider);
    final batterySaverAsync = ref.watch(batterySaverUiProvider);

    final themeMode = themeModeAsync.value ?? AppThemeMode.dark;

    return ProfileSection(
      title: 'Playback & experience',
      children: [
        ProfileTile(
          icon: Icons.palette_outlined,
          label: 'Theme mode',
          subtitle: themeMode == AppThemeMode.amoled ? 'AMOLED' : 'Dark',
          onTap: () => _showThemePicker(context, ref, themeMode),
        ),
        ProfileToggleTile(
          icon: Icons.auto_awesome_outlined,
          label: 'Dynamic album colors',
          subtitle: 'Player accent adapts to album artwork',
          value: dynamicColorsAsync.value ?? true,
          onChanged: (v) => ref.read(dynamicColorsProvider.notifier).setValue(v),
        ),
        ProfileToggleTile(
          icon: Icons.motion_photos_off_outlined,
          label: 'Reduce motion',
          subtitle: 'Minimize animations and transitions',
          value: reduceMotionAsync.value ?? false,
          onChanged: (v) => ref.read(reduceMotionProvider.notifier).setValue(v),
        ),
        ProfileToggleTile(
          icon: Icons.battery_saver_outlined,
          label: 'Battery saver UI mode',
          subtitle: 'Reduce visual effects to save battery',
          value: batterySaverAsync.value ?? false,
          onChanged: (v) => ref.read(batterySaverUiProvider.notifier).setValue(v),
        ),
        ProfileTile(
          icon: Icons.merge_type_outlined,
          label: 'Crossfade',
          subtitle: 'Coming soon',
          trailing: Icon(Icons.lock_outline, size: 16, color: aurora.textSecondary),
        ),
        ProfileTile(
          icon: Icons.high_quality_outlined,
          label: 'Audio quality',
          subtitle: 'Coming soon',
          showDivider: false,
          trailing: Icon(Icons.lock_outline, size: 16, color: aurora.textSecondary),
        ),
      ],
    );
  }
}
