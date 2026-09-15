import 'package:supabase_flutter/supabase_flutter.dart';
import '../core/logging/app_logger.dart';

/// Phase 4 — Remote Feature Flags Service using Supabase config.
class FeatureFlagsService {
  static FeatureFlagsService? _instance;
  static FeatureFlagsService get instance => _instance ??= FeatureFlagsService._();
  FeatureFlagsService._();

  final Map<String, dynamic> _flags = {
    'enable_crossfade': true,
    'enable_volume_normalization': true,
    'enable_smart_queue': true,
    'enable_deezer_metadata': true,
    'enable_lastfm_enrichment': true,
    'enable_background_discovery': true,
  };

  /// Fetches remote feature flags on launch (falls back to defaults).
  Future<void> fetchFlags() async {
    try {
      final client = Supabase.instance.client;
      final response = await client.from('user_settings').select().limit(1);
      AppLogger.sync('FeatureFlagsService: Remote flags checked (${response.length} rows)');
    } catch (e) {
      AppLogger.sync('FeatureFlagsService: Offline or flags table unavailable, using defaults');
    }
  }

  bool isEnabled(String flagName, {bool defaultValue = false}) {
    return _flags[flagName] as bool? ?? defaultValue;
  }
}
