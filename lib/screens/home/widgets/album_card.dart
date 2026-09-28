import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_extension.dart';
import '../../../core/theme/app_typography.dart';
import '../../../widgets/cached_artwork.dart';

/// Plain value type shared by the carousel and the grid, so neither has
/// to know about RecentlyPlayedEntry vs FavoriteSong vs CachedSongEntry.
/// All three already carry songId/title/author/thumbnail.
class AlbumCardData {
  const AlbumCardData({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumbnail,
    required this.onTap,
  });

  final String id;
  final String title;
  final String subtitle;
  final String thumbnail;
  final VoidCallback onTap;
}

/// Square artwork card: hover scales it up and fades in a play button.
/// [width] is the card width; the grid computes it from the column count,
/// the carousel passes the fixed shelf size.
class AlbumCard extends StatefulWidget {
  const AlbumCard({super.key, required this.item, this.width = 156});

  final AlbumCardData item;
  final double width;

  @override
  State<AlbumCard> createState() => _AlbumCardState();
}

class _AlbumCardState extends State<AlbumCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final item = widget.item;

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: item.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.03 : 1,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: SizedBox(
            width: widget.width,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: widget.width,
                  height: widget.width,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    boxShadow: [
                      BoxShadow(
                        color: aurora.shadowColor.withOpacity(_hovered ? 0.4 : 0.22),
                        blurRadius: _hovered ? 22 : 14,
                        offset: const Offset(0, 8),
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppSpacing.radiusLg),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedArtwork(
                          imageUrl: item.thumbnail,
                          cacheKey: item.id,
                          width: widget.width,
                          height: widget.width,
                          borderRadius: BorderRadius.zero,
                          fit: BoxFit.cover,
                          memCacheWidth: (widget.width * 2).round(),
                          memCacheHeight: (widget.width * 2).round(),
                          placeholderIcon: Icons.music_note_rounded,
                        ),
                        AnimatedOpacity(
                          opacity: _hovered ? 1 : 0,
                          duration: const Duration(milliseconds: 160),
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.34)),
                            child: Center(
                              child: Container(
                                width: 44,
                                height: 44,
                                decoration: BoxDecoration(gradient: aurora.accentGradient, shape: BoxShape.circle),
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardTitle.copyWith(color: aurora.textPrimary),
                ),
                const SizedBox(height: 2),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.cardSubtitle.copyWith(color: aurora.textSecondary),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
