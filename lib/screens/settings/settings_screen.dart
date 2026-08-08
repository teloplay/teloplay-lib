import 'package:flutter/material.dart';

import 'cache_settings_section.dart';

// ⚠️ Phase 3 Item E — প্রকৃত Settings screen। এতদিন
// `CacheSettingsSection` শুধু `/debug/cache-settings` debug route-এর
// মাধ্যমে দেখা যেত (`CacheSettingsDebugScreen` wrapper দিয়ে)। এখন এই
// screen সেই জায়গা নিচ্ছে — user-facing entry point, `music_player_screen.dart`-এর
// storage icon থেকে navigate হবে।
//
// Debug route (`/debug/cache-settings`) ইচ্ছাকৃতভাবে router-এ রাখা হয়েছে
// (dev-only quick access-এর জন্য) — এই screen সেটাকে replace করছে না,
// বরং একটা প্রপার top-level entry point যোগ করছে।
//
// ভবিষ্যতে এখানে আরও section যোগ হবে (Theme, Account, About ইত্যাদি,
// Phase 6/5 অনুযায়ী) — এখন শুধু Storage & Cache section।
class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF121212),
      appBar: AppBar(
        backgroundColor: const Color(0xFF121212),
        title: const Text('Settings'),
      ),
      body: const SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            CacheSettingsSection(),
            SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}