import 'package:flutter/material.dart';

import 'profile_section.dart';

/// ⚠️ Phase 6.5 Batch 6 (Batch B) — About section: About TeloPlay,
/// Privacy Policy, Licenses, Open Source Credits, Contact/Feedback।
///
/// এই ব্যাচে সব entries navigational placeholder (SnackBar দিয়ে
/// "coming soon") — actual content page (privacy policy text, license
/// list ইত্যাদি) এই স্কোপের বাইরে, production-এর আগে TODO checklist-এ
/// (roadmap-এর "Production-এর আগে TODO" section-এর সাথে সামঞ্জস্যপূর্ণ,
/// legal/content copy তখনই ঠিক করা হবে)। "Licenses" flutter-এর
/// built-in `showLicensePage()` ব্যবহার করছে যেটা আসলেই কার্যকর
/// (কোনো নতুন content লাগে না, Flutter নিজেই সব package license
/// track করে)।
class AboutSection extends StatelessWidget {
  const AboutSection({super.key});

  void _showComingSoon(BuildContext context, String feature) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('$feature coming soon')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProfileSection(
      title: 'About',
      children: [
        ProfileTile(
          icon: Icons.info_outline,
          label: 'About TeloPlay',
          onTap: () => showAboutDialog(
            context: context,
            applicationName: 'TeloPlay',
            applicationVersion: '1.0.0',
            applicationLegalese: 'A music platform with a persistent player.',
          ),
        ),
        ProfileTile(
          icon: Icons.privacy_tip_outlined,
          label: 'Privacy policy',
          onTap: () => _showComingSoon(context, 'Privacy policy'),
        ),
        ProfileTile(
          icon: Icons.description_outlined,
          label: 'Licenses',
          onTap: () => showLicensePage(
            context: context,
            applicationName: 'TeloPlay',
            applicationVersion: '1.0.0',
          ),
        ),
        ProfileTile(
          icon: Icons.code,
          label: 'Open source credits',
          onTap: () => _showComingSoon(context, 'Open source credits'),
        ),
        ProfileTile(
          icon: Icons.mail_outline,
          label: 'Contact / feedback',
          showDivider: false,
          onTap: () => _showComingSoon(context, 'Contact form'),
        ),
      ],
    );
  }
}