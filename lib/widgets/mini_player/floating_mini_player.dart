import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../providers/album_accent_provider.dart';
import '../../providers/music_player_provider.dart';
import '../cached_artwork.dart';
import '../glass_container.dart';

/// Persistent compact player bar. Android: sits above bottom nav.
/// Windows: corner-docked panel. Tap → expand (caller supplies via
/// [onExpand]); swipe up (mobile only) also expands.
///
/// Phase 6 Batch 5 — artwork wrapped in Hero with tag
/// 'player-artwork-<trackId>', matching PlayerArtwork's own Hero tag.
/// This makes the mini→full morph transition ready once
/// NowPlayingScreen (Phase 6.5) exists as the Hero destination route.
class FloatingMiniPlayer extends ConsumerWidget {
  const FloatingMiniPlayer({
    super.key,
    this.onExpand,
    this.height = 64,
  });

  final VoidCallback? onExpand;
  final double height;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final track = ref.watch(currentTrackProvider).value;
    if (track == null) return const SizedBox.shrink();

    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final isBuffering = ref.watch(playbackBufferingProvider).value ?? false;
    final accentState = ref.watch(albumAccentProvider);
    final accent = accentState.accentColor ?? aurora.primary;
    final repo = ref.watch(musicPlayerRepositoryProvider);

    return Dismissible(
      key: ValueKey('mini-player-${track.videoId}'),
      direction: DismissDirection.horizontal,
      background: _DismissBackground(alignment: Alignment.centerLeft),
      secondaryBackground: _DismissBackground(alignment: Alignment.centerRight),
      confirmDismiss: (_) async {
        // ⚠️ পুরোপুরি playback বন্ধ + queue clear — শুধু UI hide না।
        // Dismissible নিজে থেকেই widget সরিয়ে দেয় (confirmDismiss:true
        // রিটার্ন করলে), তারপর currentTrack null হয়ে গেলে rebuild-এ
        // এমনিতেই SizedBox.shrink() রিটার্ন হবে — Dismissible-এর কোনো
        // leftover slot থাকবে না।
        await ref.read(musicPlayerRepositoryProvider).stopAndClear();
        return true;
      },
      child: GestureDetector(
      onTap: onExpand,
      onVerticalDragEnd: (details) {
        if ((details.primaryVelocity ?? 0) < -250) onExpand?.call();
      },
      child: GlassContainer(
        height: height,
        borderRadius: BorderRadius.circular(14),
        glowColor: accent,
        glowOpacity: 0.18,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: Row(
          children: [
            Hero(
              tag: 'player-artwork-${track.videoId}',
              child: CachedArtwork(
                imageUrl: track.thumbnail,
                cacheKey: track.videoId,
                width: 44,
                height: 44,
                borderRadius: BorderRadius.circular(8),
                memCacheWidth: 88,
                memCacheHeight: 88,
                placeholderIcon: Icons.music_note,
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    track.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: aurora.textPrimary, fontSize: 13, fontWeight: FontWeight.w600),
                  ),
                  Text(
                    track.author,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: aurora.textSecondary, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: Icon(
                isBuffering ? Icons.hourglass_top : (isPlaying ? Icons.pause : Icons.play_arrow),
                color: accent,
              ),
              onPressed: repo.togglePause,
            ),
            IconButton(
              icon: Icon(Icons.skip_next, color: aurora.textPrimary),
              onPressed: repo.next,
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Dismissible-এর swipe-reveal ব্যাকগ্রাউন্ড — ছোট "X" hint, দুই দিকেই
/// একই লুক (horizontal direction, alignment শুধু বদলায়)।
class _DismissBackground extends StatelessWidget {
  const _DismissBackground({required this.alignment});
  final Alignment alignment;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.redAccent.withOpacity(0.18),
        borderRadius: BorderRadius.circular(14),
      ),
      alignment: alignment,
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: const Icon(Icons.close_rounded, color: Colors.redAccent, size: 20),
    );
  }
}