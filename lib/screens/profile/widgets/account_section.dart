import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../profile_providers.dart';
import 'profile_section.dart';

/// Phase 6.5 Batch 6 — Account section: Account Information, Login
/// Method, Change Display Name, Sign Out.
///
/// "Change Display Name" now persists to Supabase user_metadata via
/// AuthService.updateDisplayName().
class AccountSection extends ConsumerWidget {
  const AccountSection({super.key});

  Future<void> _confirmSignOut(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text('You can sign back in anytime.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    if (!context.mounted) return;

    final authService = ref.read(authServiceProvider);
    await authService.signOut();

    // GoRouter-এর existing auth-based redirect Welcome screen-এ পাঠিয়ে
    // দেবে (roadmap Phase 0 — auth redirect logic আগে থেকেই আছে),
    // এখানে explicit navigation করা হচ্ছে না — router নিজে react করবে
    // authStateProvider বদলানোর সাথে সাথে।
  }

  Future<void> _showChangeNameDialog(BuildContext context, WidgetRef ref) async {
    final authService = ref.read(authServiceProvider);
    final currentName = authService.displayName ?? '';

    final controller = TextEditingController(text: currentName);

    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Change display name'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(
            hintText: 'Your name',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (value) => Navigator.of(dialogContext).pop(value.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text.trim()),
            child: const Text('Save'),
          ),
        ],
      ),
    );

    if (name == null || name.isEmpty || name == currentName) return;

    await authService.updateDisplayName(name);

    // Refresh auth state to show new name in UI
    ref.invalidate(authStateProvider);

    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Display name updated')),
      );
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authService = ref.watch(authServiceProvider);
    final user = authService.currentUser;
    final isGuest = authService.isGuest;
    final displayName = authService.displayName;

    return ProfileSection(
      title: 'Account',
      children: [
        ProfileTile(
          icon: Icons.info_outline,
          label: 'Account information',
          subtitle: isGuest
              ? 'Guest account'
              : (displayName != null && displayName.isNotEmpty
                  ? '$displayName (${user?.email ?? '—'})'
                  : (user?.email ?? '—')),
          onTap: () {},
        ),
        ProfileTile(
          icon: Icons.login,
          label: 'Login method',
          subtitle: isGuest
              ? 'Guest — sign in to save your data across devices'
              : (user?.appMetadata['provider'] as String? ?? 'Email'),
          onTap: isGuest ? () => context.push('/welcome') : null,
        ),
        ProfileTile(
          icon: Icons.edit_outlined,
          label: 'Change display name',
          onTap: () => _showChangeNameDialog(context, ref),
        ),
        ProfileTile(
          icon: Icons.logout,
          label: 'Sign out',
          isDestructive: true,
          showDivider: false,
          onTap: () => _confirmSignOut(context, ref),
        ),
      ],
    );
  }
}