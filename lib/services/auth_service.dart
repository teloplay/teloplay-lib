import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/config/env_config.dart';

/// Auth-সংক্রান্ত সব Supabase call এখান থেকেই হবে।
/// Welcome screen / providers কখনো সরাসরি Supabase.instance ব্যবহার করবে না,
/// সবসময় এই service-এর মাধ্যমে — এতে ভবিষ্যতে Windows-এ Google Sign-In যোগ
/// করতে শুধু এই ফাইলের ভেতরের implementation বদলালেই হবে, বাকি কিছু
/// (Welcome screen, providers, router) বদলাতে হবে না।
class AuthService {
  final SupabaseClient _client = Supabase.instance.client;

  /// google_sign_in v7.x থেকে GoogleSignIn একটা singleton — নিজে থেকে
  /// constructor দিয়ে instance বানানো যায় না।
  final GoogleSignIn _googleSignIn = GoogleSignIn.instance;

  bool _googleSignInInitialized = false;

  /// v7.x-এ explicit initialize() call বাধ্যতামূলক, অন্য কোনো
  /// GoogleSignIn method কল করার আগে ঠিক একবার করতে হয়। এখানে
  /// lazily (প্রথমবার signInWithGoogle() কল হলে) করা হচ্ছে যাতে
  /// app startup-এ আলাদা করে await করতে না হয়।
  Future<void> _ensureGoogleSignInInitialized() async {
    if (_googleSignInInitialized) return;
    await _googleSignIn.initialize(
      serverClientId: EnvConfig.googleWebClientId,
    );
    _googleSignInInitialized = true;
  }

  /// বর্তমান session (null হলে কেউ login নেই)
  Session? get currentSession => _client.auth.currentSession;

  /// বর্তমান user (guest হলেও non-null, কারণ Anonymous Auth ব্যবহার হচ্ছে)
  User? get currentUser => _client.auth.currentUser;

  /// বর্তমান user guest (anonymous) কিনা
  bool get isGuest => currentUser?.isAnonymous ?? false;

  /// Auth state পরিবর্তনের stream — Riverpod provider এটা watch করবে
  Stream<AuthState> get authStateChanges => _client.auth.onAuthStateChange;

  /// Display name from user_metadata (nullable)
  String? get displayName {
    return currentUser?.userMetadata?['display_name'] as String?;
  }

  // ─────────────────────────────────────────────────────────
  // Guest Mode
  // ─────────────────────────────────────────────────────────

  Future<void> signInAsGuest() async {
    await _client.auth.signInAnonymously();
  }

  // ─────────────────────────────────────────────────────────
  // Email OTP
  // ─────────────────────────────────────────────────────────

  Future<void> sendOtp(String email) async {
    if (isGuest) {
      await _client.auth.updateUser(UserAttributes(email: email));
    } else {
      await _client.auth.signInWithOtp(
        email: email,
        shouldCreateUser: true,
      );
    }
  }

  Future<AuthResponse> verifyOtp({
    required String email,
    required String token,
  }) async {
    final wasGuest = isGuest;

    final response = await _client.auth.verifyOTP(
      email: email,
      token: token,
      type: wasGuest ? OtpType.emailChange : OtpType.email,
    );
    return response;
  }

  // ─────────────────────────────────────────────────────────
  // Google Sign-In (google_sign_in v7.x API)
  // ─────────────────────────────────────────────────────────

  /// Google দিয়ে sign in করে। বর্তমানে শুধু Android/iOS-এ কাজ করে।
  /// Windows-এ কল হলে UnsupportedError ছোড়ে।
  ///
  /// গুরুত্বপূর্ণ: guest (anonymous) অবস্থায় থেকে এটা কল হলে Supabase
  /// নিজে থেকেই same UID-তে Google identity link করে দেয় (email OTP
  /// flow-এর মতোই), যেহেতু "Allow manual linking" ON করা আছে।
  Future<void> signInWithGoogle() async {
    if (!(defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS)) {
      throw UnsupportedError(
        'Google Sign-In এই platform-এ এখনো সাপোর্টেড না। '
        'শুধু Android/iOS-এ কাজ করে।',
      );
    }

    await _ensureGoogleSignInInitialized();

    late final GoogleSignInAccount googleUser;
    try {
      // v7.x: signIn() এর বদলে authenticate(), cancel করলে exception ছোড়ে
      googleUser = await _googleSignIn.authenticate();
    } on GoogleSignInException catch (e) {
      if (e.code == GoogleSignInExceptionCode.canceled) {
        // User নিজে cancel করেছে, এটা error হিসেবে দেখানোর দরকার নেই
        return;
      }
      rethrow;
    }

    // v7.x: authentication এখন synchronous (Future না)
    final idToken = googleUser.authentication.idToken;

    if (idToken == null) {
      throw Exception('Google থেকে ID token পাওয়া যায়নি।');
    }

    await _client.auth.signInWithIdToken(
      provider: OAuthProvider.google,
      idToken: idToken,
    );
  }

  // ─────────────────────────────────────────────────────────
  // Display Name
  // ─────────────────────────────────────────────────────────

  Future<void> updateDisplayName(String name) async {
    await _client.auth.updateUser(
      UserAttributes(
        data: {'display_name': name.trim()},
      ),
    );
  }

  // ─────────────────────────────────────────────────────────
  // Sign out
  // ─────────────────────────────────────────────────────────

  Future<void> signOut() async {
    if ((defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS) &&
        _googleSignInInitialized) {
      await _googleSignIn.signOut();
    }
    await _client.auth.signOut();
  }
}