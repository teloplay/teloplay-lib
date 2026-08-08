import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../providers/music_player_provider.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../providers/album_accent_provider.dart';
import '../../services/performance_service.dart';
import '../cached_artwork.dart';

/// ⚠️ Phase 6 — শেয়ার্ড content widget (Mobile + Desktop shell দুটোই এটা
/// ব্যবহার করবে, দেখো architecture_decision নোট)। এই widget-ই একমাত্র
/// জায়গা যেখানে `CachedArtwork.onLocalPathResolved` কল হয় এবং
/// `albumAccentProvider.updateFromArtwork()` trigger হয় — track বদলালে
/// এখান থেকেই পুরো app-এর accent chain শুরু হয়।
///
/// Glow: `context.aurora.effectiveAccent` দিয়ে `BoxShadow`-ভিত্তিক soft
/// bleed, `GlassContainer`-এর মতো একই glow-language ব্যবহার করে (আলাদা
/// glow-style তৈরি করা হয়নি — visual consistency)। Low RAM mode-এ glow
/// blur radius কমানো হয়, সম্পূর্ণ বন্ধ করা হয় না (design brief: "Low RAM
/// mode: Disable blur, Keep color extraction only" — এখানে glow blur-ই
/// একমাত্র ব্যয়বহুল অংশ, সেটাই কমছে)।
///
/// ⚠️ Phase 6.5 Batch 5 — Hero tag added (`player-artwork-<trackId>`).
/// This is the fix for the mini→full morph mismatch found during this
/// batch: `FloatingMiniPlayer` and `DesktopBottomPlayerBar` both
/// already wrapped their artwork in a matching Hero, but this widget —
/// the actual full-size destination artwork shown in
/// NowPlayingScreen/MusicPlayerScreen — never had one. Without a tag
/// match on both source and destination, Hero produces no animation at
/// all; navigating to `/player` previously just cut instantly. Tag
/// format kept identical to the mini-player's: `'player-artwork-$trackId'`.
class PlayerArtwork extends ConsumerWidget {
  const PlayerArtwork({
    super.key,
    required this.trackId,
    required this.imageUrl,
    this.size = 250,
  });

  final String trackId;
  final String imageUrl;
  final double size;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final accent = aurora.effectiveAccent;
    final isLowRam = PerformanceService.instance.isLowRamMode;
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;

    return AnimatedScale(
      scale: isPlaying ? 1.0 : 0.96,
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      child: AnimatedContainer(
      // ⚠️ "Animated Album Artwork" (roadmap Phase 6 item) — glow রং
      // বদলানোর সময় soft crossfade, harsh জাম্প না।
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutCubic,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: accent.withOpacity(0.4),
            blurRadius: isLowRam ? 20 : 48,
            spreadRadius: isLowRam ? -4 : -6,
          ),
        ],
      ),
      child: Hero(
        tag: 'player-artwork-$trackId',
        child: CachedArtwork(
          imageUrl: imageUrl,
          cacheKey: trackId,
          width: size,
          height: size,
          borderRadius: BorderRadius.circular(12),
          memCacheWidth: (size * 2).round(),
          memCacheHeight: (size * 2).round(),
          placeholderIcon: Icons.music_note,
          onLocalPathResolved: (localPath) {
            ref
                .read(albumAccentProvider.notifier)
                .updateFromArtwork(trackId, localPath);
          },
        ),
      ),
      ),
    );
  }
}