import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';

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

  /// Web ও Desktop-এ OAuth Sign-in (Supabase Hosted OAuth Flow)
  Future<void> signInWithOAuthWeb(OAuthProvider provider) async {
    final redirectUrl = kIsWeb 
        ? Uri.base.origin 
        : 'io.supabase.teloplay://login-callback/';
    await _client.auth.signInWithOAuth(
      provider,
      redirectTo: redirectUrl,
      authScreenLaunchMode: LaunchMode.platformDefault,
    );
  }

  /// Google দিয়ে sign in করে।
  /// Android/iOS-এ native GoogleSignIn, Web-এ Supabase OAuth,
  /// Windows-এ local server দিয়ে browser-based OAuth flow।
  Future<void> signInWithGoogle() async {
    if (kIsWeb) {
      await signInWithOAuthWeb(OAuthProvider.google);
      return;
    }

    // Windows desktop: local server দিয়ে OAuth
    if (defaultTargetPlatform == TargetPlatform.windows) {
      await _signInWithGoogleDesktop();
      return;
    }

    // Android/iOS: native Google Sign-In
    if (!(defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS)) {
      throw UnsupportedError(
        'Google Sign-In এই platform-এ এখনো সাপোর্টেড না। '
        'শুধু Android/iOS/Web/Windows-এ কাজ করে।',
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

  /// Windows desktop এর জন্য Google Sign-In:
  /// 1. Local HTTP server start করে (localhost:8080)
  /// 2. Browser open করে Google OAuth URL-এ
  /// 3. Callback URL থেকে authorization code পায়
  /// 4. Supabase-এ session তৈরি করে
  Future<void> _signInWithGoogleDesktop() async {
    const redirectPort = 8080;
    const redirectUri = 'http://localhost:$redirectPort/auth/callback';

    // Local server start
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, redirectPort);

    try {
      // Supabase OAuth URL তৈরি
      final authResponse = await _client.auth.getOAuthSignInUrl(
        provider: OAuthProvider.google,
        redirectTo: redirectUri,
      );
      final authUrl = authResponse.url;

      // Browser open করে OAuth flow শুরু
      final uri = Uri.parse(authUrl);
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri, mode: LaunchMode.externalApplication);
      } else {
        throw Exception('Browser খুলতে পারেনি। URL: $authUrl');
      }

      // Callback শোনা শুরু (timeout: 5 minutes)
      final request = await server.first.timeout(
        const Duration(minutes: 5),
        onTimeout: () => throw TimeoutException('Sign-in timeout হয়ে গেছে'),
      );

      // Query parameters থেকে code/error নেওয়া
      final queryParams = request.uri.queryParameters;

      if (queryParams.containsKey('error')) {
        final error = queryParams['error'];
        final errorDescription = queryParams['error_description'] ?? error;
        throw Exception('OAuth error: $errorDescription');
      }

      final code = queryParams['code'];
      if (code == null) {
        throw Exception('Authorization code পাওয়া যায়নি');
      }

      // Success response পাঠানো browser-এ
      request.response
        ..statusCode = HttpStatus.ok
        ..headers.contentType = ContentType.html
        ..write('''
          <!DOCTYPE html>
          <html>
          <head>
            <title>Sign In Successful</title>
            <style>
              body {
                font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, sans-serif;
                display: flex;
                align-items: center;
                justify-content: center;
                height: 100vh;
                margin: 0;
                background: linear-gradient(135deg, #667eea 0%, #764ba2 100%);
              }
              .card {
                background: white;
                padding: 40px;
                border-radius: 16px;
                box-shadow: 0 10px 40px rgba(0,0,0,0.2);
                text-align: center;
                max-width: 400px;
              }
              .success-icon {
                width: 60px;
                height: 60px;
                background: #4CAF50;
                border-radius: 50%;
                display: inline-flex;
                align-items: center;
                justify-content: center;
                margin-bottom: 20px;
              }
              h1 { color: #333; margin: 0 0 10px; font-size: 24px; }
              p { color: #666; margin: 0; }
            </style>
          </head>
          <body>
            <div class="card">
              <div class="success-icon">
                <svg width="32" height="32" viewBox="0 0 24 24" fill="none" stroke="white" stroke-width="3">
                  <polyline points="20 6 9 17 4 12"></polyline>
                </svg>
              </div>
              <h1>✅ Sign In Successful!</h1>
              <p>You can now close this window and return to TeloPlay.</p>
            </div>
          </body>
          </html>
        ''');
      await request.response.close();

      // Supabase session তৈরি করা authorization code দিয়ে
      await _client.auth.exchangeCodeForSession(code);

    } finally {
      // Server বন্ধ করা
      await server.close();
    }
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