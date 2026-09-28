import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_extension.dart';
import '../../../core/theme/app_typography.dart';
import 'album_card.dart';

/// Horizontal shelf: section title, optional "See all", square artwork.
///
/// Renders nothing for an empty list, so callers can drop it straight
/// under an AsyncValue without an extra empty check. Cards stagger in
/// left-to-right; the delay is capped so a long rail doesn't visibly
/// wait on its tail.
class AlbumCarousel extends StatelessWidget {
  const AlbumCarousel({super.key, required this.title, required this.items, this.onSeeAll});

  final String title;
  final List<AlbumCardData> items;
  final VoidCallback? onSeeAll;

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final aurora = context.aurora;

    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
            child: Row(
              children: [
                Expanded(
                  child: Text(title, style: AppTypography.sectionTitle.copyWith(color: aurora.textPrimary)),
                ),
                if (onSeeAll != null)
                  TextButton(
                    onPressed: onSeeAll,
                    child: Text('See all', style: AppTypography.cardSubtitle.copyWith(color: aurora.primary)),
                  ),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          SizedBox(
            height: 214,
            child: ListView.separated(
              scrollDirection: Axis.horizontal,
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
              itemCount: items.length,
              separatorBuilder: (_, __) => const SizedBox(width: AppSpacing.md),
              itemBuilder: (context, index) {
                final delay = (40 * index).clamp(0, 240).ms;
                return AlbumCard(item: items[index])
                    .animate()
                    .fadeIn(delay: delay, duration: 280.ms)
                    .slideX(begin: 0.08, end: 0, delay: delay, duration: 280.ms, curve: Curves.easeOutCubic);
              },
            ),
          ),
        ],
      ),
    );
  }
}
