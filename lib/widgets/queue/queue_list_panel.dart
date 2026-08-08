import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../providers/music_player_provider.dart';
import '../cached_artwork.dart';

/// Phase 6.5 UI-Batch 3 (Context Panel polish) — visual-only rewrite.
/// Same data source / behavior as the Batch-5 version (pure display +
/// tap-to-play, no drag reorder/multi-select/search — still Phase 7+).
/// Replaces default Material [ListTile] rows with custom hover-aware
/// rows matching the locked design system (gradient active-indicator
/// bar, hover background, playing-now equalizer glyph).
class QueueListPanel extends ConsumerWidget {
  const QueueListPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final aurora = context.aurora;
    final repo = ref.watch(musicPlayerRepositoryProvider);
    final currentTrack = ref.watch(currentTrackProvider).value;
    final queue = ref.watch(queueProvider).value ?? const [];

    if (queue.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.queue_music_rounded, size: 28, color: aurora.textSecondary.withOpacity(0.4)),
            const SizedBox(height: 8),
            Text('Queue empty', style: TextStyle(color: aurora.textSecondary, fontSize: 12.5)),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.symmetric(vertical: 4),
      itemCount: queue.length,
      itemBuilder: (context, index) {
        final t = queue[index];
        final isCurrent = currentTrack != null && t.videoId == currentTrack.videoId;
        return _QueueRow(
          title: t.title,
          author: t.author,
          thumbnail: t.thumbnail,
          videoId: t.videoId,
          isCurrent: isCurrent,
          onTap: () => repo.playFromQueue(index),
        );
      },
    );
  }
}

class _QueueRow extends StatefulWidget {
  const _QueueRow({
    required this.title,
    required this.author,
    required this.thumbnail,
    required this.videoId,
    required this.isCurrent,
    required this.onTap,
  });

  final String title;
  final String author;
  final String thumbnail;
  final String videoId;
  final bool isCurrent;
  final VoidCallback onTap;

  @override
  State<_QueueRow> createState() => _QueueRowState();
}

class _QueueRowState extends State<_QueueRow> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 130),
          margin: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 7),
          decoration: BoxDecoration(
            color: widget.isCurrent
                ? aurora.primary.withOpacity(0.12)
                : _hovered
                    ? aurora.surfaceElevated
                    : Colors.transparent,
            borderRadius: BorderRadius.circular(10),
          ),
          child: Row(
            children: [
              // Active-track gradient indicator bar (locked pattern,
              // matches SidebarNavItem's active indicator).
              SizedBox(
                width: 3,
                height: 34,
                child: widget.isCurrent
                    ? DecoratedBox(
                        decoration: BoxDecoration(gradient: aurora.accentGradient, borderRadius: BorderRadius.circular(2)),
                      )
                    : null,
              ),
              const SizedBox(width: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(6),
                child: CachedArtwork(
                  imageUrl: widget.thumbnail,
                  cacheKey: widget.videoId,
                  width: 36,
                  height: 36,
                  borderRadius: BorderRadius.zero,
                  memCacheWidth: 72,
                  memCacheHeight: 72,
                  placeholderIcon: Icons.music_note,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: widget.isCurrent ? aurora.primary : aurora.textPrimary,
                        fontSize: 12.5,
                        fontWeight: widget.isCurrent ? FontWeight.w700 : FontWeight.w600,
                      ),
                    ),
                    Text(
                      widget.author,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(color: aurora.textSecondary, fontSize: 11),
                    ),
                  ],
                ),
              ),
              if (widget.isCurrent) ...[
                const SizedBox(width: 6),
                _PlayingGlyph(color: aurora.primary),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Small animated "now playing" indicator — three bars pulsing at
/// staggered rates, replacing the plain selected-row highlight with a
/// clearer at-a-glance signal (common pattern in premium players).
class _PlayingGlyph extends StatefulWidget {
  const _PlayingGlyph({required this.color});
  final Color color;

  @override
  State<_PlayingGlyph> createState() => _PlayingGlyphState();
}

class _PlayingGlyphState extends State<_PlayingGlyph> with SingleTickerProviderStateMixin {
  late final AnimationController _controller =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 14,
      height: 14,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, _) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: List.generate(3, (i) {
              final phase = (_controller.value + (i * 0.33)) % 1.0;
              final h = 4 + (phase * 10);
              return Container(
                width: 2.5,
                height: h,
                decoration: BoxDecoration(color: widget.color, borderRadius: BorderRadius.circular(1)),
              );
            }),
          );
        },
      ),
    );
  }
}