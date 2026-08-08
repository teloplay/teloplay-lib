import 'package:flutter/material.dart';

import '../../../core/theme/app_theme_extension.dart';
import '../../../widgets/cached_artwork.dart';

/// Phase 6.5 UI-Batch 3b — premium "shelf" rail.
///
/// API unchanged from Batch-2 version ([ContentRailItem]/[ContentRail]
/// constructor signature) — only the visual layer is rewritten, so
/// `home_screen.dart` call sites need no changes. Adds: larger square
/// cards, neutral elevation shadow + hover-scale (PremiumCard-style,
/// not reusing PremiumCard directly since the image needs to fill edge
/// to edge under a play-button overlay), a hover-revealed play button,
/// and an optional "See All" header action.
class ContentRailItem {
  final String id;
  final String title;
  final String subtitle;
  final String thumbnail;
  final VoidCallback onTap;

  const ContentRailItem({
    required this.id,
    required this.title,
    required this.subtitle,
    required this.thumbnail,
    required this.onTap,
  });
}

class ContentRail extends StatelessWidget {
  const ContentRail({
    super.key,
    required this.title,
    required this.items,
    this.onSeeAll,
  });

  final String title;
  final List<ContentRailItem> items;

  /// Optional — shows a "See All" link in the header when provided.
  /// Rails that don't have a dedicated destination screen yet can omit
  /// this (falls back to no action, per-item tap still works).
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final aurora = context.aurora;

    return Padding(
      padding: const EdgeInsets.only(top: 22),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  title,
                  style: TextStyle(color: aurora.textPrimary, fontSize: 18, fontWeight: FontWeight.w800, letterSpacing: -0.2),
                ),
                if (onSeeAll != null)
                  _SeeAllLink(onTap: onSeeAll!),
              ],
            ),
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 202,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: 24),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: 16),
              itemBuilder: (context, index) => _RailCard(item: items[index]),
            ),
          ),
        ],
      ),
    );
  }
}

class _SeeAllLink extends StatefulWidget {
  const _SeeAllLink({required this.onTap});
  final VoidCallback onTap;

  @override
  State<_SeeAllLink> createState() => _SeeAllLinkState();
}

class _SeeAllLinkState extends State<_SeeAllLink> {
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
        child: Text(
          'See All',
          style: TextStyle(
            color: _hovered ? aurora.primary : aurora.textSecondary,
            fontSize: 12.5,
            fontWeight: FontWeight.w700,
          ),
        ),
      ),
    );
  }
}

class _RailCard extends StatefulWidget {
  const _RailCard({required this.item});
  final ContentRailItem item;

  @override
  State<_RailCard> createState() => _RailCardState();
}

class _RailCardState extends State<_RailCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final item = widget.item;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: item.onTap,
        child: AnimatedScale(
          scale: _hovered ? 1.035 : 1.0,
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          child: SizedBox(
            width: 148,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 148,
                  height: 148,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    boxShadow: [
                      BoxShadow(
                        color: aurora.shadowColor.withOpacity(_hovered ? 0.35 : 0.2),
                        blurRadius: _hovered ? 20 : 12,
                        offset: const Offset(0, 6),
                        spreadRadius: -4,
                      ),
                    ],
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16),
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        CachedArtwork(
                          imageUrl: item.thumbnail,
                          cacheKey: item.id,
                          width: 148,
                          height: 148,
                          borderRadius: BorderRadius.zero,
                          fit: BoxFit.cover,
                          memCacheWidth: 296,
                          memCacheHeight: 296,
                          placeholderIcon: Icons.music_note,
                        ),
                        AnimatedOpacity(
                          opacity: _hovered ? 1.0 : 0.0,
                          duration: const Duration(milliseconds: 160),
                          child: DecoratedBox(
                            decoration: BoxDecoration(color: Colors.black.withOpacity(0.32)),
                            child: Center(
                              child: Container(
                                width: 40,
                                height: 40,
                                decoration: BoxDecoration(gradient: aurora.accentGradient, shape: BoxShape.circle),
                                child: const Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: aurora.textPrimary, fontSize: 13, fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 1),
                Text(
                  item.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: aurora.textSecondary, fontSize: 11.5),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}