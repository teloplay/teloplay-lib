import 'package:flutter/material.dart';

import '../../core/theme/app_theme_extension.dart';
import 'widgets/about_section.dart';
import 'widgets/account_section.dart';
import 'widgets/devices_section.dart';
import 'widgets/diagnostics_section.dart';
import 'widgets/playback_experience_section.dart';
import 'widgets/profile_header.dart';
import 'widgets/quick_stats_grid.dart';
import 'widgets/storage_cache_section.dart';

/// Phase 6.5 Batch 6 — Profile Screen ("Personal Hub").
///
/// এই ব্যাচ (Batch A): Header + Quick Stats + Account + Devices
/// (placeholder)। Batch B: Playback & Experience + Storage & Cache +
/// Diagnostics + About — যোগ হবে confirm করার পরে, একই এই ফাইলে নতুন
/// section widget import করে column-এ বসিয়ে দিলেই যথেষ্ট (নিচের
/// _leftColumnSections/_rightColumnSections getters সেভাবেই composable
/// রাখা হয়েছে)।
///
/// Design rules (developer-specified):
///   - Mobile: vertical sections, large cards
///   - Desktop: two-column (left: Profile+Stats, right: Settings)
///   - "Do NOT make Profile screen just a settings list" — তাই Header +
///     QuickStatsGrid সবসময় top-এ prominent থাকে, dashboard-feel দেয়।
///
/// Platform detection এখানে simple width-breakpoint দিয়ে করা হচ্ছে
/// (ঠিক QuickStatsGrid-এর LayoutBuilder cross-axis-count breakpoint-এর
/// মতোই কনভেনশন) — DesktopShell/MobileShell আলাদা platform-check
/// (Platform.isWindows ইত্যাদি) ব্যবহার করে shell পর্যায়ে, কিন্তু এই
/// screen সরাসরি সেই platform-check import করেনি (screen content
/// platform-agnostic থাকা উচিত, ঠিক HomeScreen/SearchScreen-এর মতো —
/// শুধু width-responsive, platform-check না) — তাই এখানে width দিয়েই
/// সিদ্ধান্ত নেওয়া হচ্ছে। DesktopShell এমনিতেই একটা fixed-width
/// Expanded area-তে এই screen render করে, তাই এই breakpoint বাস্তবে
/// "DesktopShell-এর ভেতরে" মানেই সবসময় true হবে।
class ProfileScreen extends StatelessWidget {
  const ProfileScreen({super.key});

  static const double _desktopBreakpoint = 760;

  List<Widget> get _leftColumnSections => const [
        ProfileHeader(),
        SizedBox(height: 16),
        QuickStatsGrid(),
      ];

  List<Widget> get _rightColumnSections => const [
        AccountSection(),
        SizedBox(height: 20),
        DevicesSection(),
        SizedBox(height: 20),
        PlaybackExperienceSection(),
        SizedBox(height: 20),
        StorageCacheSection(),
        SizedBox(height: 20),
        DiagnosticsSection(),
        SizedBox(height: 20),
        AboutSection(),
      ];

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return Scaffold(
      backgroundColor: aurora.background,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isDesktop = constraints.maxWidth >= _desktopBreakpoint;

            if (isDesktop) {
              return _DesktopLayout(
                leftColumn: _leftColumnSections,
                rightColumn: _rightColumnSections,
              );
            }

            return _MobileLayout(
              sections: [
                ..._leftColumnSections,
                const SizedBox(height: 24),
                ..._rightColumnSections,
              ],
            );
          },
        ),
      ),
    );
  }
}

class _MobileLayout extends StatelessWidget {
  const _MobileLayout({required this.sections});

  final List<Widget> sections;

  @override
  Widget build(BuildContext context) {
    return ListView(
      // bottom padding — FloatingMiniPlayer overlap এড়াতে (mobile_shell.dart-এ
      // 8px bottom + player height, generous margin রাখা হলো)
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 100),
      children: sections,
    );
  }
}

class _DesktopLayout extends StatelessWidget {
  const _DesktopLayout({required this.leftColumn, required this.rightColumn});

  final List<Widget> leftColumn;
  final List<Widget> rightColumn;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 320,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: leftColumn,
            ),
          ),
          const SizedBox(width: 24),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: rightColumn,
            ),
          ),
        ],
      ),
    );
  }
}