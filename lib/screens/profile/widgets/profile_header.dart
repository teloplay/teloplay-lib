import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../../core/theme/app_theme_extension.dart';
import '../profile_providers.dart';

/// ⚠️ Phase 6.5 Batch 6 — Profile Screen top section: Avatar + Display
/// Name + Email/Login Method + Member Since.
///
/// User dashboard-feel বজায় রাখতে (design rule: "Do NOT make Profile
/// screen just a settings list"), এই widget বড়, generous spacing সহ
/// একটা "personal card" — Account section-এর ছোট list-tile items থেকে
/// deliberately আলাদা visual weight।
///
/// Avatar এখন initials-based (network image/upload এখনো নেই — future
/// scope, Supabase Storage integration লাগবে)। Login method Supabase
/// `User.appMetadata['provider']` থেকে derive করা হচ্ছে — google হলে
/// "Google", email/otp হলে "Email", anonymous হলে "Guest".
class ProfileHeader extends ConsumerWidget {
  const ProfileHeader({super.key});

  String _loginMethodLabel(User? user) {
    if (user == null) return 'Unknown';
    if (user.isAnonymous) return 'Guest';
    final provider = user.appMetadata['provider'] as String?;
    switch (provider) {
      case 'google':
        return 'Google';
      case 'email':
        return 'Email';
      default:
        return provider ?? 'Email';
    }
  }

  String _initials(User? user) {
    final email = user?.email;
    if (email != null && email.isNotEmpty) {
      return email.substring(0, 1).toUpperCase();
    }
    if (user?.isAnonymous ?? false) return 'G';
    return '?';
  }

  String _displayName(User? user) {
    if (user == null) return 'Unknown';
    if (user.isAnonymous) return 'Guest';
    final email = user.email;
    if (email != null && email.isNotEmpty) {
      return email.split('@').first;
    }
    return 'TeloPlay User';
  }

  String _memberSince(User? user) {
    final createdAt = user?.createdAt;
    if (createdAt == null) return '—';
    try {
      final date = DateTime.parse(createdAt);
      const months = [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ];
      return '${months[date.month - 1]} ${date.year}';
    } catch (_) {
      return '—';
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final authAsync = ref.watch(authStateProvider);
    final authService = ref.watch(authServiceProvider);

    // authStateProvider stream event না এলেও currentUser সরাসরি পড়া
    // যায় (AuthService.currentUser সবসময় sync-accessible) — প্রথম
    // frame-এ flicker এড়াতে fallback হিসেবে ব্যবহার করা হচ্ছে।
    final user = authAsync.maybeWhen(
      data: (state) => state.session?.user ?? authService.currentUser,
      orElse: () => authService.currentUser,
    );

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: aurora.surfaceRaised,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: aurora.glassBorder),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 72,
            height: 72,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [aurora.primary, aurora.secondary],
              ),
            ),
            alignment: Alignment.center,
            child: Text(
              _initials(user),
              style: const TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w700,
                color: Colors.white,
              ),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _displayName(user),
                  style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.3,
                    color: aurora.textPrimary,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 4),
                Text(
                  user?.isAnonymous ?? true
                      ? 'Guest account'
                      : (user?.email ?? '—'),
                  style: TextStyle(fontSize: 13, color: aurora.textSecondary),
                  overflow: TextOverflow.ellipsis,
                ),
                const SizedBox(height: 10),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    _Pill(
                      icon: Icons.login,
                      label: _loginMethodLabel(user),
                      aurora: aurora,
                    ),
                    _Pill(
                      icon: Icons.calendar_today_outlined,
                      label: 'Since ${_memberSince(user)}',
                      aurora: aurora,
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({required this.icon, required this.label, required this.aurora});

  final IconData icon;
  final String label;
  final AuroraColors aurora;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
      decoration: BoxDecoration(
        color: aurora.primary.withOpacity(0.12),
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: aurora.primary),
          const SizedBox(width: 5),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: aurora.primary,
            ),
          ),
        ],
      ),
    );
  }
}