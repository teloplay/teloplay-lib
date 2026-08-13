import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/env_config.dart';
import '../services/cache/metadata_cache_service.dart';
import '../services/discovery/discovery_queue.dart';
import '../services/metadata/lastfm_client.dart';
import '../services/metadata/musicbrainz_client.dart';
import 'search_provider.dart' show deezerClientProvider, metadataCacheServiceProvider;

/// Null when LASTFM_API_KEY isn't configured in .env — callers treat that
/// as "enrichment unavailable", not an error, since Last.fm is
/// background-only per roadmap Section A.
final lastFmClientProvider = Provider<LastFmClient?>((ref) {
  final apiKey = EnvConfig.lastFmApiKey;
  if (apiKey.isEmpty) return null;
  return LastFmClient(
    apiKey: apiKey,
    cache: ref.watch(metadataCacheServiceProvider),
  );
});

/// Null when MUSICBRAINZ_CONTACT_EMAIL isn't configured in .env —
/// callers treat that as "enrichment unavailable". MusicBrainz needs
/// no API key, just an identifying User-Agent header.
final musicBrainzClientProvider = Provider<MusicBrainzClient?>((ref) {
  final contactEmail = EnvConfig.musicBrainzContactEmail;
  if (contactEmail.isEmpty) return null;
  return MusicBrainzClient(
    appName: EnvConfig.musicBrainzAppName,
    appVersion: EnvConfig.musicBrainzAppVersion,
    contactEmail: contactEmail,
    cache: ref.watch(metadataCacheServiceProvider),
  );
});

/// DiscoveryQueue provider — background enrichment processor.
/// Nullable-safe: if any metadata client is missing, DiscoveryQueue
/// still works with whatever is available.
final discoveryQueueProvider = Provider<DiscoveryQueue>((ref) {
  return DiscoveryQueue(
    lastFm: ref.watch(lastFmClientProvider),
    musicBrainz: ref.watch(musicBrainzClientProvider),
    deezer: ref.watch(deezerClientProvider),
    cache: ref.watch(metadataCacheServiceProvider),
  );
});