import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../providers/music_player_provider.dart' show musicPlayerRepositoryProvider;
import '../../widgets/home/continue_section.dart';
import 'home_providers.dart';
import 'widgets/content_rail.dart';
import 'widgets/featured_hero_card.dart';
import 'widgets/mobile_hero_carousel.dart';
import 'widgets/smart_welcome_header.dart';
import 'widgets/smart_welcome_header_mobile.dart';

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
bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;

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
            ref.invalidate(continueListeningProvider);
            ref.invalidate(continueSessionProvider);
            ref.invalidate(recentlyPlayedForHomeProvider);
            ref.invalidate(cachedSongsForHomeProvider);
          },
          child: ListView(
            children: [
              if (_isDesktop) ...[
                const SmartWelcomeHeader(),
                continueListening.when(
                  data: (info) => info == null ? const SizedBox.shrink() : FeaturedHeroCard(info: info),
                  loading: () => const SizedBox.shrink(),
                  error: (_, __) => const SizedBox.shrink(),
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
                error: (_, __) => const SizedBox.shrink(),
              ),

              recentlyPlayed.when(
                data: (list) => ContentRail(
                  title: 'Recently Played',
                  onSeeAll: () => context.push('/library/recent'),
                  items: list.map((e) => ContentRailItem(
                        id: e.songId,
                        title: e.title,
                        subtitle: e.author,
                        thumbnail: e.thumbnail,
                        onTap: () => context.push('/history'),
                      )).toList(),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              favorites.when(
                data: (list) => ContentRail(
                  title: 'Your Favorites',
                  onSeeAll: () => context.push('/library/favorites'),
                  items: list.map((e) => ContentRailItem(
                        id: e.songId,
                        title: e.title,
                        subtitle: e.author,
                        thumbnail: e.thumbnail,
                        onTap: () => context.push('/favorites'),
                      )).toList(),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              mostPlayed.when(
                data: (list) => ContentRail(
                  title: 'Most Played',
                  onSeeAll: () => context.push('/library/most-played'),
                  items: list.map((e) => ContentRailItem(
                        id: e.songId,
                        title: e.title,
                        subtitle: e.author,
                        thumbnail: e.thumbnail,
                        onTap: () => context.push('/library/most-played'),
                      )).toList(),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
              ),

              cachedSongs.when(
                data: (list) => ContentRail(
                  title: 'Offline Collection',
                  onSeeAll: () => context.push('/library/offline'),
                  items: list.map((e) => ContentRailItem(
                        id: e.songId,
                        title: e.title,
                        subtitle: e.author,
                        thumbnail: e.thumbnail,
                        onTap: () => context.push('/library'),
                      )).toList(),
                ),
                loading: () => const SizedBox.shrink(),
                error: (_, __) => const SizedBox.shrink(),
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
