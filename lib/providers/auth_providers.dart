import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../services/auth_service.dart';

part 'auth_providers.g.dart';

@Riverpod(keepAlive: true)
AuthService authService(Ref ref) {
  return AuthService();
}

/// বর্তমান auth state (login/logout/token-refresh ইত্যাদি) — এটা watch করে
/// Welcome screen বনাম Home screen-এর মধ্যে navigate করা হবে।
@riverpod
Stream<AuthState> authStateChanges(Ref ref) {
  final authService = ref.watch(authServiceProvider);
  return authService.authStateChanges;
}

/// সুবিধার জন্য — বর্তমান user guest কিনা সরাসরি জানার provider
@riverpod
bool isGuestUser(Ref ref) {
  // authStateChanges watch করা হচ্ছে যাতে login/logout হলে এই value
  // automatically rebuild হয়
  ref.watch(authStateChangesProvider);
  return ref.watch(authServiceProvider).isGuest;
}