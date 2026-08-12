import 'package:flutter/material.dart';

import '../../core/theme/theme_extensions.dart';

/// Sort options for playlist tracks.
enum TrackSortOption {
  customOrder,
  titleAsc,
  titleDesc,
  artistAsc,
  artistDesc,
  albumAsc,
  albumDesc,
  recentlyAdded,
  durationAsc,
  durationDesc,
}

/// Bottom sheet for track sorting with optional view mode toggle.
class TrackSortBottomSheet extends StatelessWidget {
  final TrackSortOption currentSort;
  final ValueChanged<TrackSortOption> onSortChanged;
  final bool showViewMode;
  final bool isCompactView;
  final ValueChanged<bool>? onViewModeChanged;

  const TrackSortBottomSheet({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
    this.showViewMode = false,
    this.isCompactView = false,
    this.onViewModeChanged,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;

    return Container(
      decoration: BoxDecoration(
        color: theme.surfaceRaised,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: theme.textDisabled,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                'Sort by',
                style: TextStyle(
                  color: theme.textPrimary,
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              _SortOption(
                label: 'Custom order',
                isSelected: currentSort == TrackSortOption.customOrder,
                onTap: () => _select(context, TrackSortOption.customOrder),
                theme: theme,
              ),
              _SortOption(
                label: 'Title',
                isSelected: currentSort == TrackSortOption.titleAsc ||
                    currentSort == TrackSortOption.titleDesc,
                onTap: () => _select(context, TrackSortOption.titleAsc),
                theme: theme,
              ),
              _SortOption(
                label: 'Artist',
                isSelected: currentSort == TrackSortOption.artistAsc ||
                    currentSort == TrackSortOption.artistDesc,
                onTap: () => _select(context, TrackSortOption.artistAsc),
                theme: theme,
              ),
              _SortOption(
                label: 'Album',
                isSelected: currentSort == TrackSortOption.albumAsc ||
                    currentSort == TrackSortOption.albumDesc,
                onTap: () => _select(context, TrackSortOption.albumAsc),
                theme: theme,
              ),
              _SortOption(
                label: 'Recently added',
                isSelected: currentSort == TrackSortOption.recentlyAdded,
                onTap: () => _select(context, TrackSortOption.recentlyAdded),
                theme: theme,
              ),
              _SortOption(
                label: 'Duration',
                isSelected: currentSort == TrackSortOption.durationAsc ||
                    currentSort == TrackSortOption.durationDesc,
                onTap: () => _select(context, TrackSortOption.durationAsc),
                theme: theme,
              ),
              if (showViewMode) ...[
                const SizedBox(height: 16),
                Divider(color: theme.surface),
                const SizedBox(height: 16),
                Text(
                  'View as',
                  style: TextStyle(
                    color: theme.textPrimary,
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    _ViewModeButton(
                      icon: Icons.view_list,
                      label: 'List',
                      isSelected: !isCompactView,
                      onTap: () => onViewModeChanged?.call(false),
                      theme: theme,
                    ),
                    const SizedBox(width: 12),
                    _ViewModeButton(
                      icon: Icons.view_compact,
                      label: 'Compact',
                      isSelected: isCompactView,
                      onTap: () => onViewModeChanged?.call(true),
                      theme: theme,
                    ),
                  ],
                ),
              ],
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _select(BuildContext context, TrackSortOption sort) {
    Navigator.pop(context);
    onSortChanged(sort);
  }
}

class _SortOption extends StatelessWidget {
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final dynamic theme;

  const _SortOption({
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              isSelected ? Icons.radio_button_checked : Icons.radio_button_unchecked,
              color: isSelected ? theme.primary : theme.textDisabled,
              size: 20,
            ),
            const SizedBox(width: 12),
            Text(
              label,
              style: TextStyle(
                color: isSelected ? theme.textPrimary : theme.textSecondary,
                fontSize: 15,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ViewModeButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool isSelected;
  final VoidCallback onTap;
  final dynamic theme;

  const _ViewModeButton({
    required this.icon,
    required this.label,
    required this.isSelected,
    required this.onTap,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(vertical: 12),
          decoration: BoxDecoration(
            color: isSelected ? theme.primary.withOpacity(0.15) : theme.surface,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isSelected ? theme.primary : Colors.transparent,
            ),
          ),
          child: Column(
            children: [
              Icon(icon, color: isSelected ? theme.primary : theme.textSecondary),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: isSelected ? theme.primary : theme.textSecondary,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}