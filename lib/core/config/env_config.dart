import 'dart:convert';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_dotenv/flutter_dotenv.dart';


/// .env ফাইল থেকে environment variables read করার জন্য single source।
/// অন্য কোথাও সরাসরি dotenv.env[...] ব্যবহার করা হবে না।
///
/// Web/Pages নোট: `.env` gitignored — clean CI build-এ (Cloudflare Pages)
/// asset হিসেবে থাকে না। তখন সব getter '' ফেরত দিত আর Supabase call
/// same-origin relative URL-এ গিয়ে static host থেকে
/// `405 empty response` খেত। তাই `.env` missing/empty হলে committed
/// `assets/env.json` fallback হিসেবে পড়া হয় (anon key client
/// bundle-এ এমনিতেই public থাকে, তাই এটা commit করা safe)।
class EnvConfig {
  static Map<String, String> _fallback = const {};

  // CI/Pages build command theke: `--dart-define=SUPABASE_URL=...`
  // flutter_dotenv asset + env.json dutoi miss holeo eta thakbe.
  static const _define = {
    'SUPABASE_URL': String.fromEnvironment('SUPABASE_URL'),
    'SUPABASE_ANON_KEY': String.fromEnvironment('SUPABASE_ANON_KEY'),
    'GOOGLE_WEB_CLIENT_ID': String.fromEnvironment('GOOGLE_WEB_CLIENT_ID'),
    'TELOPLAY_STREAM_PROXY_URL':
        String.fromEnvironment('TELOPLAY_STREAM_PROXY_URL'),
    'LASTFM_API_KEY': String.fromEnvironment('LASTFM_API_KEY'),
  };

  static String _get(String key) {
    try {
      final v = dotenv.env[key];
      if (v != null && v.isNotEmpty) return v;
    } catch (_) {
      // dotenv init হয়নি (.env asset missing) — নিচের fallback দেখো।
    }
    final d = _define[key];
    if (d != null && d.isNotEmpty) return d;
    return _fallback[key] ?? '';
  }

  static String get supabaseUrl => _get('SUPABASE_URL');
  static String get supabaseAnonKey => _get('SUPABASE_ANON_KEY');
  static String get googleWebClientId =>
      _get('GOOGLE_WEB_CLIENT_ID');

  /// Optional free Cloudflare Worker that resolves Piped streams server-side
  /// and proxies audio with CORS. Required for reliable Flutter web playback.
  static String get streamProxyUrl =>
      _get('TELOPLAY_STREAM_PROXY_URL');

  // ⚠️ v11 — Metadata/Discovery/Sync Architecture. All three are official
  // public APIs used with real app registration — see roadmap Section J.
  static String get deezerAppId => _get('DEEZER_APP_ID');
  static String? get deezerSecret {
    final v = _get('DEEZER_SECRET');
    return v.isEmpty ? null : v;
  }

  static String get lastFmApiKey => _get('LASTFM_API_KEY');

  /// MusicBrainz needs no key, just an identifying User-Agent — these
  /// three values compose the header MusicBrainzClient sends
  /// (`$appName/$appVersion ($contactEmail)` per their usage policy).
  static String get musicBrainzAppName =>
      _get('MUSICBRAINZ_APP_NAME').isEmpty ? 'TeloPlay' : _get('MUSICBRAINZ_APP_NAME');
  static String get musicBrainzAppVersion =>
      _get('MUSICBRAINZ_APP_VERSION').isEmpty ? '1.0.0' : _get('MUSICBRAINZ_APP_VERSION');
  static String get musicBrainzContactEmail =>
      _get('MUSICBRAINZ_CONTACT_EMAIL');

  static Future<void> load() async {
    try {
      await dotenv.load(fileName: '.env');
      if (dotenv.env.isNotEmpty) return;
    } catch (_) {
      // .env asset নেই (CI/Pages build) — নিচে env.json fallback।
    }
    try {
      final raw = await rootBundle.loadString('assets/env.json');
      final json = jsonDecode(raw) as Map<String, dynamic>;
      _fallback = {
        for (final e in json.entries) e.key: e.value?.toString() ?? '',
      };
    } catch (_) {
      _fallback = const {};
    }
  }

  /// Supabase init-এর আগে check করো — '' URL নিয়ে initialize করে
  /// Pages origin-এ 405 খাওয়ার চেয়ে startup-এ clear error ভালো।
  static bool get isConfigured =>
      supabaseUrl.isNotEmpty && supabaseAnonKey.isNotEmpty;
}
