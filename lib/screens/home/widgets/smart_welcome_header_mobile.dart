import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_extension.dart';

/// Phase 6.5 UI-Batch 4 — Mobile-only expanded welcome header।
/// Desktop-এর SmartWelcomeHeader (compact single-row) থেকে ইচ্ছাকৃতভাবে
/// আলাদা ফাইল — Mobile-এ vertical space বেশি available, তাই greeting
/// বড় typography + bell icon (notification placeholder, এখন শুধু UI,
/// কোনো backend/notification system নেই)।
class SmartWelcomeHeaderMobile extends StatelessWidget {
  const SmartWelcomeHeaderMobile({super.key, this.onBellTap});

  final VoidCallback? onBellTap;

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
          _BellButton(onTap: onBellTap),
        ],
      ),
    );
  }
}

class _BellButton extends StatelessWidget {
  const _BellButton({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: 42,
        height: 42,
        decoration: BoxDecoration(
          color: aurora.surfaceElevated,
          shape: BoxShape.circle,
          border: Border.all(color: Colors.white.withOpacity(0.06)),
        ),
        child: Icon(Icons.notifications_none_rounded, color: aurora.textPrimary, size: 20),
      ),
    );
  }
}