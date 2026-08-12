import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/theme_extensions.dart';
import '../../data/repositories/settings_repository.dart';
import '../../screens/onboarding/getting_started_screen.dart';

/// Persistent onboarding badge in home app bar.
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
            if (count == 5) return const SizedBox.shrink();
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

  Widget _buildBadge(BuildContext context, int completed, dynamic theme) {
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
                value: completed / 5,
                strokeWidth: 2,
                backgroundColor: theme.textDisabled,
                valueColor: AlwaysStoppedAnimation(theme.primary),
              ),
            ),
            const SizedBox(width: 6),
            Text(
              '$completed/5',
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