import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../providers/music_player_provider.dart' show musicPlayerRepositoryProvider;
import '../../widgets/home/continue_section.dart';
import '../../widgets/inline_load_error.dart';
import '../../widgets/track_menu.dart';
import 'home_providers.dart';
import 'widgets/content_rail.dart';
import 'widgets/featured_hero_card.dart';
import 'widgets/mobile_hero_carousel.dart';
import 'widgets/smart_welcome_header.dart';
import 'widgets/smart_welcome_header_mobile.dart';

import '../../core/playback/playback_engine.dart';
import '../../ui/shell/platform_shell.dart';
import 'widgets/quick_access_section.dart';

/// Phase 6.5 UI-Batch 4 — HomeScreen এখন platform-branch করে: Desktop
/// অপরিবর্তিত (compact header + single FeaturedHeroCard), Mobile নতুন
/// (expanded header + swipeable 3-card carousel)। সব rail (Recently
/// Played/Favorites/Most Played/Offline) দুই platform-এই শেয়ার্ড —
/// শুধু header + hero অংশ আলাদা।
///
/// ⚠️ v11 Fix (Continue Session, roadmap Section H): the multi-song
/// [ContinueSection] card is inserted right after the existing hero
/// (FeaturedHeroCard/carousel) whenever the resumable session has more
/// than one remaining song — the single-song hero already covers
/// "what to resume", this card adds the "+N more songs in queue / From:
/// [rail]" detail the old hero didn't carry. When there's nothing to
/// resume, or the session is exactly one song (nothing extra to say
/// beyond what the hero already shows), this section renders nothing.
class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final isDesktop =
        PlatformShell.isDesktopLayout(MediaQuery.sizeOf(context).width);

    final continueListening = ref.watch(continueListeningProvider);
    final continueSession = ref.watch(continueSessionProvider);
    final recentlyPlayed = ref.watch(recentlyPlayedForHomeProvider);
    final favorites = ref.watch(favoritesForHomeProvider);
    final mostPlayed = ref.watch(mostPlayedForHomeProvider);
    final cachedSongs = ref.watch(cachedSongsForHomeProvider);
    final topFavorite = ref.watch(topFavoriteForHomeProvider);

    return Scaffold(
      backgroundColor: aurora.background,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () async {
            // Batch B — refresh every Home source. Canonical mapping:
            // continueListening derives from continueSession, topFavorite
            // shares favorites' watchFavorites stream — but each is an
            // independent provider instance, so all seven are invalidated
            // explicitly (no silent stale rail after pull-to-refresh).
            ref.invalidate(continueSessionProvider);
            ref.invalidate(continueListeningProvider);
            ref.invalidate(recentlyPlayedForHomeProvider);
            ref.invalidate(favoritesForHomeProvider);
            ref.invalidate(topFavoriteForHomeProvider);
            ref.invalidate(mostPlayedForHomeProvider);
            ref.invalidate(cachedSongsForHomeProvider);
          },
          child: ListView(
            children: [
              if (isDesktop) ...[
                const SmartWelcomeHeader(),
                continueListening.when(
                  data: (info) => info == null ? const SizedBox.shrink() : FeaturedHeroCard(info: info),
                  loading: () => const SizedBox.shrink(),
                  // P1-A — hero data failing is not "nothing to show".
                  error: (_, __) => InlineLoadError(
                    message: "Couldn't load your picks",
                    onRetry: () => ref.invalidate(continueListeningProvider),
                  ),
                ),
              ] else ...[
                const SmartWelcomeHeaderMobile(),
                _buildMobileHeroCarousel(context, continueListening, topFavorite, mostPlayed),
              ],

              // ⚠️ v11 Continue Session — only shown when there's more
              // than one remaining song (see class doc-comment above).
              continueSession.when(
                data: (session) {
                  if (session == null || session.remainingSongs <= 0) {
                    return const SizedBox.shrink();
                  }
                  return ContinueSection(
                    session: session,
                    onResume: () => _resumeSession(context, ref),
                    onDismiss: () => _dismissSession(ref, session.currentSong.videoId),
                  );
                },
                loading: () => const SizedBox.shrink(),
                // P1-A — a failed session fetch is not "no session".
                error: (_, __) => InlineLoadError(
                  message: "Couldn't load your session",
                  onRetry: () => ref.invalidate(continueSessionProvider),
                ),
              ),

              // Desktop-e sidebar already provides direct shortcuts to these sections.
              // Mobile-e easy thumb-tap shortcut thakbe.
              if (!isDesktop) const QuickAccessSection(),

              recentlyPlayed.when(
                data: (list) => ContentRail(
                  title: 'Recently Played',
                  onSeeAll: () => context.push('/library/recent'),
                  // Batch B — explicit empty guidance instead of silent
                  // disappearance; Browse reuses the downloaded-CTA
                  // pattern (go search tab).
                  emptyMessage: 'Songs you play will show up here.',
                  onEmptyBrowse: () => context.go('/home?tab=search'),
                  items: list.map((e) => ContentRailItem(
                        id: e.songId,
                        title: e.title,
                        subtitle: e.author,
                        thumbnail: e.thumbnail,
                        onTap: () => _playTrack(ref, e.songId, e.title, e.author, e.thumbnail),
                        // P1-L — same track object as tap path.
                        onLongPress: () => _showTrackMenu(
                            context, ref, e.songId, e.title, e.author, e.thumbnail),
                      )).toList(),
                ),
                // Batch B — explicit loading skeleton (shrink hid loading
                // indistinguishably from empty).
                loading: () =>
                    const RailLoadingPlaceholder(title: 'Recently Played'),
                // P1-A
                error: (_, __) => InlineLoadError(
                  message: "Couldn't load recently played",
                  onRetry: () => ref.invalidate(recentlyPlayedForHomeProvider),
                ),
              ),

              favorites.when(
                data: (list) => ContentRail(
                  title: 'Your Favorites',
                  onSeeAll: () => context.push('/library/favorites'),
                  emptyMessage: 'Songs you like will appear here.',
                  onEmptyBrowse: () => context.go('/home?tab=search'),
                  items: list.map((e) => ContentRailItem(
                        id: e.songId,
                        title: e.title,
                        subtitle: e.author,
                        thumbnail: e.thumbnail,
                        onTap: () => _playTrack(ref, e.songId, e.title, e.author, e.thumbnail),
                        // P1-L — same track object as tap path.
                        onLongPress: () => _showTrackMenu(
                            context, ref, e.songId, e.title, e.author, e.thumbnail),
                      )).toList(),
                ),
                loading: () =>
                    const RailLoadingPlaceholder(title: 'Your Favorites'),
                // P1-A
                error: (_, __) => InlineLoadError(
                  message: "Couldn't load favorites",
                  onRetry: () => ref.invalidate(favoritesForHomeProvider),
                ),
              ),

              mostPlayed.when(
                data: (list) => ContentRail(
                  title: 'Most Played',
                  onSeeAll: () => context.push('/library/most'),
                  emptyMessage:
                      'Keep listening — your top tracks will build up here.',
                  onEmptyBrowse: () => context.go('/home?tab=search'),
                  items: list.map((e) => ContentRailItem(
                        id: e.songId,
                        title: e.title,
                        subtitle: e.author,
                        thumbnail: e.thumbnail,
                        onTap: () => _playTrack(ref, e.songId, e.title, e.author, e.thumbnail),
                        // P1-L — same track object as tap path.
                        onLongPress: () => _showTrackMenu(
                            context, ref, e.songId, e.title, e.author, e.thumbnail),
                      )).toList(),
                ),
                loading: () =>
                    const RailLoadingPlaceholder(title: 'Most Played'),
                // P1-A
                error: (_, __) => InlineLoadError(
                  message: "Couldn't load most played",
                  onRetry: () => ref.invalidate(mostPlayedForHomeProvider),
                ),
              ),

              cachedSongs.when(
                data: (list) => ContentRail(
                  title: 'Offline Collection',
                  // A5 — canonical offline destination (bare
                  // '/library/offline' is not a route; it fell into the
                  // '/library/:section' catch-all hub instead).
                  onSeeAll: () =>
                      context.push('/library/offline/downloaded'),
                  emptyMessage:
                      'Songs you download will appear here for offline listening.',
                  onEmptyBrowse: () => context.go('/home?tab=search'),
                  items: list.map((e) => ContentRailItem(
                        id: e.songId,
                        title: e.title,
                        subtitle: e.author,
                        thumbnail: e.thumbnail,
                        onTap: () => _playTrack(ref, e.songId, e.title, e.author, e.thumbnail),
                        // P1-L — same track object as tap path.
                        onLongPress: () => _showTrackMenu(
                            context, ref, e.songId, e.title, e.author, e.thumbnail),
                      )).toList(),
                ),
                loading: () =>
                    const RailLoadingPlaceholder(title: 'Offline Collection'),
                // P1-A
                error: (_, __) => InlineLoadError(
                  message: "Couldn't load offline songs",
                  onRetry: () => ref.invalidate(cachedSongsForHomeProvider),
                ),
              ),

              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _resumeSession(BuildContext context, WidgetRef ref) async {
    final session = ref.read(continueSessionProvider).value;
    if (session == null) return;

    final manager = ref.read(continueSessionManagerProvider);
    final musicRepo = ref.read(musicPlayerRepositoryProvider);
    await manager.restoreSession(session, musicRepo);

    if (context.mounted) context.push('/player');
  }

  Future<void> _dismissSession(WidgetRef ref, String songId) async {
    final manager = ref.read(continueSessionManagerProvider);
    await manager.dismiss(songId);
    ref.invalidate(continueSessionProvider);
  }

  void _playTrack(WidgetRef ref, String songId, String title, String author, String thumbnail) {
    ref.read(musicPlayerRepositoryProvider).playVideoId(
          songId,
          trackInfo: SearchResult(
            videoId: songId,
            title: title,
            author: author,
            thumbnail: thumbnail,
          ),
        );
  }

  /// P1-L — rail long-press menu. Same track object as [_playTrack] so
  /// queue/favorite actions operate on identical data.
  void _showTrackMenu(
    BuildContext context,
    WidgetRef ref,
    String songId,
    String title,
    String author,
    String thumbnail,
  ) {
    showTrackMenu(
      context: context,
      ref: ref,
      track: SearchResult(
        videoId: songId,
        title: title,
        author: author,
        thumbnail: thumbnail,
      ),
    );
  }

  /// ৩টা সম্ভাব্য card থেকে যেগুলোর data আছে শুধু সেগুলোই বসানো হয় —
  /// data না থাকলে card বাদ, সব বাদ পড়লে carousel-ই hide (empty list)।
  Widget _buildMobileHeroCarousel(
    BuildContext context,
    AsyncValue<ContinueListeningInfo?> continueListening,
    AsyncValue<dynamic> topFavorite,
    AsyncValue<List<dynamic>> mostPlayed,
  ) {
    final items = <HeroCarouselItem>[];

    final cl = continueListening.value;
    if (cl != null) {
      items.add(HeroCarouselItem(
        id: cl.songId,
        label: 'CONTINUE LISTENING',
        title: cl.title,
        subtitle: cl.author,
        thumbnail: cl.thumbnail,
        onTap: () => context.push('/player'),
        onAction: () => context.push('/player'),
      ));
    }

    final fav = topFavorite.value;
    if (fav != null) {
      items.add(HeroCarouselItem(
        id: fav.songId,
        label: 'TOP FAVORITE',
        title: fav.title,
        subtitle: fav.author,
        thumbnail: fav.thumbnail,
        onTap: () => context.push('/library/favorites'),
        onAction: () => context.push('/library/favorites'),
        actionIcon: Icons.favorite_rounded,
      ));
    }

    final mp = mostPlayed.value;
    if (mp != null && mp.isNotEmpty) {
      final top = mp.first;
      items.add(HeroCarouselItem(
        id: top.songId,
        label: 'MOST PLAYED',
        title: top.title,
        subtitle: top.author,
        thumbnail: top.thumbnail,
        onTap: () => context.push('/library/most-played'),
        onAction: () => context.push('/library/most-played'),
        actionIcon: Icons.local_fire_department_rounded,
      ));
    }

    if (items.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4, bottom: 8),
      child: MobileHeroCarousel(items: items),
    );
  }
}
