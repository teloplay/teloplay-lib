import 'package:flutter_dotenv/flutter_dotenv.dart';

/// .env ফাইল থেকে environment variables read করার জন্য single source।
/// অন্য কোথাও সরাসরি dotenv.env[...] ব্যবহার করা হবে না।
class EnvConfig {
  static String get supabaseUrl => dotenv.env['SUPABASE_URL'] ?? '';
  static String get supabaseAnonKey => dotenv.env['SUPABASE_ANON_KEY'] ?? '';
  static String get googleWebClientId => dotenv.env['GOOGLE_WEB_CLIENT_ID'] ?? '';

  // ⚠️ v11 — Metadata/Discovery/Sync Architecture. All three are official
  // public APIs used with real app registration — see roadmap Section J.
  static String get deezerAppId => dotenv.env['DEEZER_APP_ID'] ?? '';
  static String? get deezerSecret => dotenv.env['DEEZER_SECRET'];
  static String get lastFmApiKey => dotenv.env['LASTFM_API_KEY'] ?? '';

  /// MusicBrainz needs no key, just an identifying User-Agent — these
  /// three values compose the header MusicBrainzClient sends
  /// (`$appName/$appVersion ($contactEmail)` per their usage policy).
  static String get musicBrainzAppName =>
      dotenv.env['MUSICBRAINZ_APP_NAME'] ?? 'TeloPlay';
  static String get musicBrainzAppVersion =>
      dotenv.env['MUSICBRAINZ_APP_VERSION'] ?? '1.0.0';
  static String get musicBrainzContactEmail =>
      dotenv.env['MUSICBRAINZ_CONTACT_EMAIL'] ?? '';

  static Future<void> load() async {
    await dotenv.load(fileName: '.env');
  }
}