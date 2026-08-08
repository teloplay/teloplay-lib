import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_extension.dart';
import 'profile_section.dart';

/// ⚠️ Phase 6.5 Batch 6 — Devices section।
///
/// ⚠️ Decision (developer-confirmed): Phase 5 (Device Management) এখনো
/// NOT STARTED, তাই এই section পুরোপুরি "Coming Soon" placeholder —
/// কোনো real device-list/session data নেই এখানে। Phase 5 শুরু হলে এই
/// widget-টাই patch করে real DeviceRepository-backed tiles বসানো হবে
/// (ProfileSection/ProfileTile shape অপরিবর্তিত থাকবে, শুধু data source
/// বদলাবে) — তাই আগেভাগে এই shell বানিয়ে রাখা ভবিষ্যতের patch-কে ছোট
/// রাখে (roadmap-এর "Future Addition" নীতির সমান্তরাল প্র্যাকটিস)।
class DevicesSection extends StatelessWidget {
  const DevicesSection({super.key});

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return ProfileSection(
      title: 'Devices',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
          child: Row(
            children: [
              Icon(Icons.devices_outlined, size: 22, color: aurora.textSecondary),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Device management coming soon',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: aurora.textPrimary,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      'View and manage devices linked to your account, and sign out remotely.',
                      style: TextStyle(fontSize: 12, color: aurora.textSecondary),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}