import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../providers/auth_providers.dart';
import '../../services/notification_permission_service.dart';

class WelcomeScreen extends ConsumerStatefulWidget {
  const WelcomeScreen({super.key});

  @override
  ConsumerState<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends ConsumerState<WelcomeScreen> {
  bool _isGuestLoading = false;
  bool _isGoogleLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();

    // ⚠️ নতুন: অ্যাপ শুরুতেই (Welcome screen প্রথম দেখানোর সাথে সাথে)
    // notification permission একবার চাওয়া হচ্ছে (Android 13+)।
    // fire-and-forget — এটা UI ব্লক করবে না, screen normal দেখাবে,
    // এবং system permission dialog আলাদাভাবে ভেসে উঠবে প্রয়োজনে।
    WidgetsBinding.instance.addPostFrameCallback((_) {
      NotificationPermissionService.requestIfNeeded();
    });
  }

  /// google_sign_in প্যাকেজ এখন শুধু Android/iOS-এ কাজ করে। Windows/Linux/
  /// macOS-এ button disabled থাকবে "Coming Soon" হিসেবে, যতক্ষণ না
  /// AuthService-এ ওই platform-গুলোর জন্য আলাদা implementation বসে।
  bool get _isGoogleSignInSupportedOnThisPlatform =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  Future<void> _continueAsGuest() async {
    setState(() {
      _isGuestLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authServiceProvider).signInAsGuest();
    } catch (e) {
      setState(() {
        _errorMessage = 'Guest হিসেবে ঢুকতে সমস্যা হয়েছে। আবার চেষ্টা করো।';
      });
    } finally {
      if (mounted) {
        setState(() => _isGuestLoading = false);
      }
    }
  }

  Future<void> _continueWithGoogle() async {
    setState(() {
      _isGoogleLoading = true;
      _errorMessage = null;
    });

    try {
      await ref.read(authServiceProvider).signInWithGoogle();
    } catch (e) {
      setState(() {
        _errorMessage = 'Google দিয়ে sign in করতে সমস্যা হয়েছে। আবার চেষ্টা করো।';
      });
    } finally {
      if (mounted) {
        setState(() => _isGoogleLoading = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final googleSupported = _isGoogleSignInSupportedOnThisPlatform;

    return Scaffold(
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Icon(Icons.music_note_rounded, size: 72),
              const SizedBox(height: 16),
              Text(
                'TeloPlay',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
              ),
              const SizedBox(height: 48),

              if (_errorMessage != null) ...[
                Text(
                  _errorMessage!,
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
                const SizedBox(height: 16),
              ],

              // Continue with Email
              FilledButton.icon(
                onPressed: () => context.push('/auth/email'),
                icon: const Icon(Icons.email_outlined),
                label: const Text('Continue with Email'),
                style: FilledButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),

              // Continue with Google — শুধু Android/iOS-এ enabled
              OutlinedButton.icon(
                onPressed: (!googleSupported || _isGoogleLoading)
                    ? null
                    : _continueWithGoogle,
                icon: _isGoogleLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.g_mobiledata),
                label: Text(
                  googleSupported
                      ? 'Continue with Google'
                      : 'Continue with Google (Coming Soon)',
                ),
                style: OutlinedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                ),
              ),
              const SizedBox(height: 12),

              // Continue as Guest
              TextButton(
                onPressed: _isGuestLoading ? null : _continueAsGuest,
                child: _isGuestLoading
                    ? const SizedBox(
                        height: 18,
                        width: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Continue as Guest'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}