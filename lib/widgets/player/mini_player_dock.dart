import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
import '../../providers/album_accent_provider.dart';
import '../../providers/music_player_provider.dart';
import '../cached_artwork.dart';
import '../glass_container.dart';

/// One mini-player for both platforms.
///
/// The old shell had two: `FloatingMiniPlayer` (mobile, floating card)
/// and `DesktopBottomPlayerBar` (desktop, full width, 18KB). This is the
/// compact form both share — artwork, title/artist, progress hairline,
/// play/pause, next. Desktop adds the queue toggle and the volume is left
/// to the full player bar; this dock is the "always visible" surface.
///
/// Renders nothing when no track is loaded, so callers can place it
/// unconditionally.
class MiniPlayerDock extends ConsumerWidget {
  const MiniPlayerDock({
    super.key,
    required this.onExpand,
    this.onToggleQueue,
    this.queueOpen = false,
  });

  final VoidCallback onExpand;

  /// Desktop only — shows the queue toggle when provided.
  final VoidCallback? onToggleQueue;
  final bool queueOpen;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final track = ref.watch(currentTrackProvider).value;
    if (track == null) return const SizedBox.shrink();

    final aurora = context.aurora;
    final isPlaying = ref.watch(isPlayingProvider).value ?? false;
    final isBuffering = ref.watch(playbackBufferingProvider).value ?? false;
    final position = ref.watch(playbackPositionProvider).value ?? Duration.zero;
    final duration = ref.watch(playbackDurationProvider).value;
    final accent = ref.watch(albumAccentProvider).accentColor ?? aurora.primary;
    final repo = ref.watch(musicPlayerRepositoryProvider);

    final progress = (duration == null || duration.inMilliseconds == 0)
        ? 0.0
        : (position.inMilliseconds / duration.inMilliseconds).clamp(0.0, 1.0);

    return GestureDetector(
      onTap: onExpand,
      child: GlassContainer(
        height: AppSpacing.miniPlayerHeight,
        borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
        glowColor: accent,
        glowOpacity: 0.18,
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(
              children: [
                Hero(
                  tag: 'player-artwork-${track.videoId}',
                  child: CachedArtwork(
                    imageUrl: track.thumbnail,
                    cacheKey: track.videoId,
                    width: 46,
                    height: 46,
                    borderRadius: BorderRadius.circular(AppSpacing.radiusSm),
                    memCacheWidth: 92,
                    memCacheHeight: 92,
                    placeholderIcon: Icons.music_note_rounded,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        track.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardTitle.copyWith(color: aurora.textPrimary),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        track.author,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.cardSubtitle.copyWith(color: aurora.textSecondary),
                      ),
                    ],
                  ),
                ),
                IconButton(
                  icon: Icon(
                    isBuffering
                        ? Icons.hourglass_top_rounded
                        : (isPlaying ? Icons.pause_rounded : Icons.play_arrow_rounded),
                    color: accent,
                  ),
                  onPressed: repo.togglePause,
                ),
                IconButton(
                  icon: Icon(Icons.skip_next_rounded, color: aurora.textPrimary),
                  onPressed: repo.next,
                ),
                if (onToggleQueue != null)
                  IconButton(
                    icon: Icon(
                      Icons.queue_music_rounded,
                      color: queueOpen ? accent : aurora.textSecondary,
                    ),
                    onPressed: onToggleQueue,
                  ),
              ],
            ),
            const SizedBox(height: AppSpacing.xs),
            ClipRRect(
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 2,
                color: accent,
                backgroundColor: Colors.white.withOpacity(0.12),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
