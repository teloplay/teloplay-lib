import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../providers/onboarding_provider.dart';
import '../../screens/onboarding/getting_started_screen.dart';

/// Persistent onboarding badge in home app bar.
///
/// ⚠️ Fix (Phase 0 v11 stabilization): same missing-provider issue as
/// getting_started_screen.dart — `onboardingCompletionProvider`/
/// `onboardingDismissedProvider` are now real (providers/onboarding_provider.dart),
/// and the wrong theme import path is corrected.
class ChecklistBadge extends ConsumerWidget {
  const ChecklistBadge({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = context.aurora;
    final completionAsync = ref.watch(onboardingCompletionProvider);
    final dismissedAsync = ref.watch(onboardingDismissedProvider);

    return dismissedAsync.when(
      data: (dismissed) {
        if (dismissed) return const SizedBox.shrink();
        return completionAsync.when(
          data: (completed) {
            final count = completed.values.where((v) => v).length;
            if (count == OnboardingKeys.all.length) return const SizedBox.shrink();
            return _buildBadge(context, count, theme);
          },
          loading: () => const SizedBox.shrink(),
          error: (_, __) => const SizedBox.shrink(),
        );
      },
      loading: () => const SizedBox.shrink(),
      error: (_, __) => const SizedBox.shrink(),
    );
  }

  Widget _buildBadge(BuildContext context, int completed, AuroraColors theme) {
    final total = OnboardingKeys.all.length;
    return InkWell(
      onTap: () => _openOnboarding(context),
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
        decoration: BoxDecoration(
          color: theme.primary.withOpacity(0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: theme.primary.withOpacity(0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                value: completed / total,
                strokeWidth: 2,
                backgroundColor: theme.textDisabled,
                valueColor: AlwaysStoppedAnimation(theme.primary),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$completed/$total',
              style: TextStyle(
                color: theme.primary,
                fontSize: 12,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openOnboarding(BuildContext context) {
    showDialog(
      context: context,
      barrierDismissible: true,
      barrierColor: Colors.black.withOpacity(0.7),
      builder: (_) => const GettingStartedScreen(),
    );
  }
}
