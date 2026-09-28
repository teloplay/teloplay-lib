import 'package:flutter/material.dart';

import '../../../core/theme/app_spacing.dart';
import '../../../core/theme/app_theme_extension.dart';
import '../../../core/theme/app_typography.dart';
import 'album_card.dart';

/// Responsive album grid. Column count follows the available width rather
/// than the platform, so a resized window reflows instead of overflowing:
///
///   < 480dp  → 2 columns
///   < 900dp  → 3
///   < 1280dp → 4
///   else     → 5
///
/// Renders nothing for an empty list, same contract as [AlbumCarousel].
class AlbumGrid extends StatelessWidget {
  const AlbumGrid({super.key, required this.title, required this.items});

  final String title;
  final List<AlbumCardData> items;

  static int columnsFor(double width) {
    if (width < 480) return 2;
    if (width < 900) return 3;
    if (width < 1280) return 4;
    return 5;
  }

  @override
  Widget build(BuildContext context) {
    if (items.isEmpty) return const SizedBox.shrink();
    final aurora = context.aurora;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: AppTypography.sectionTitle.copyWith(color: aurora.textPrimary)),
          const SizedBox(height: AppSpacing.md),
          LayoutBuilder(
            builder: (context, constraints) {
              final columns = columnsFor(constraints.maxWidth);
              final tileWidth = (constraints.maxWidth - AppSpacing.md * (columns - 1)) / columns;

              return Wrap(
                spacing: AppSpacing.md,
                runSpacing: AppSpacing.lg,
                children: [
                  for (final item in items) AlbumCard(item: item, width: tileWidth),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
