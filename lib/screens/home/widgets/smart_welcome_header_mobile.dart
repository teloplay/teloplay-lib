import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_extension.dart';

// Phase 6.5 UI-Batch 4 — Mobile-only expanded welcome header.
// Desktop-এর SmartWelcomeHeader (compact single-row) থেকে ইচ্ছাকৃতভাবে
// আলাদা ফাইল — Mobile-এ vertical space বেশি available, তাই greeting
// বড় typography।
class SmartWelcomeHeaderMobile extends StatelessWidget {
  const SmartWelcomeHeaderMobile({super.key});

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour >= 5 && hour < 12) return 'Good Morning';
    if (hour >= 12 && hour < 17) return 'Good Afternoon';
    if (hour >= 17 && hour < 21) return 'Good Evening';
    if (hour >= 21 || hour < 2) return 'Still Up?';
    return 'Good Night';
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _greeting(),
                  style: TextStyle(
                    color: aurora.textSecondary,
                    fontSize: 13,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  'Your Music',
                  style: TextStyle(
                    color: aurora.textPrimary,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
                ),
              ],
            ),
          ),
          // Gate 0 (D2/CS-04) — onboarding badge removed with its route;
          // notification bell removed (no notification system exists).
        ],
      ),
    );
  }
}