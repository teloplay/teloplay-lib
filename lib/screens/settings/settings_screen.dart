import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_theme.dart';
import '../../providers/theme_provider.dart';
import 'cache_settings_section.dart';

// ⚠️ Phase 3 Item E — প্রকৃত Settings screen। এতদিন
// `CacheSettingsSection` শুধু `/debug/cache-settings` debug route-এর
// মাধ্যমে দেখা যেত। এখন এই screen সেই জায়গা নিচ্ছে — user-facing entry point।
//
// ভবিষ্যতে এখানে আরও section যোগ হবে (Theme, Account, About ইত্যাদি)।
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.aurora;
    final themeMode = ref.watch(themeModeProvider);

    return Scaffold(
      backgroundColor: theme.background,
      appBar: AppBar(
        backgroundColor: theme.background,
        title: Text('Settings', style: TextStyle(color: theme.textPrimary)),
        iconTheme: IconThemeData(color: theme.textPrimary),
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Theme Toggle Section
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Text(
                'APPEARANCE',
                style: TextStyle(
                  color: theme.textSecondary,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 1,
                ),
              ),
            ),
            Container(
              color: theme.surface,
              child: Column(
                children: [
                  ListTile(
                    leading: Icon(Icons.dark_mode, color: theme.textSecondary),
                    title: Text('Theme', style: TextStyle(color: theme.textPrimary)),
                    trailing: Text(
                      themeMode == AppThemeMode.amoled ? 'AMOLED' : 'Dark',
                      style: TextStyle(color: theme.textSecondary),
                    ),
                    onTap: () {
                      ref.read(themeModeProvider.notifier).toggle();
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
            // Existing Cache Section
            const CacheSettingsSection(),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}