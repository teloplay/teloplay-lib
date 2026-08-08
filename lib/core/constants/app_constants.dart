/// পুরো app জুড়ে ব্যবহৃত constant value গুলো এখানেই — magic string/number
/// ছড়িয়ে-ছিটিয়ে না রেখে single source of truth রাখার জন্য।
class AppConstants {
  AppConstants._();

  // ── Route paths (GoRouter-এ ব্যবহৃত, hardcoded string এড়াতে) ──
  static const String routeWelcome = '/welcome';
  static const String routeAuthEmail = '/auth/email';
  static const String routeAuthOtp = '/auth/otp';
  static const String routeHome = '/home';

  // ── Playback defaults (Phase 1-এ ব্যবহৃত হবে) ──
  static const int preloadNextSongCount = 2; // পরের কয়টা গান আগে থেকে buffer করা হবে
  static const Duration seekStepDuration = Duration(seconds: 10);

  // ── Sync (Phase 4-এ ব্যবহৃত হবে) ──
  static const Duration playbackPositionSyncInterval = Duration(seconds: 25);

  // ── UI defaults ──
  static const double defaultBorderRadius = 12.0;
  static const Duration defaultAnimationDuration = Duration(milliseconds: 250);
}