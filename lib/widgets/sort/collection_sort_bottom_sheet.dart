import 'package:flutter/material.dart';

import '../../core/theme/app_theme_extension.dart';

/// Sort options for library sidebar/collections.
enum CollectionSortOption {
  recents,
  recentlyAdded,
  alphabeticalAsc,
  alphabeticalDesc,
  creator,
}

/// Bottom sheet for collection sorting.
class CollectionSortBottomSheet extends StatelessWidget {
  final CollectionSortOption currentSort;
  final ValueChanged<CollectionSortOption> onSortChanged;

  const CollectionSortBottomSheet({
    super.key,
    required this.currentSort,
    required this.onSortChanged,
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
                label: 'Recents',
                isSelected: currentSort == CollectionSortOption.recents,
                onTap: () => _select(context, CollectionSortOption.recents),
                theme: theme,
              ),
              _SortOption(
                label: 'Recently added',
                isSelected: currentSort == CollectionSortOption.recentlyAdded,
                onTap: () => _select(context, CollectionSortOption.recentlyAdded),
                theme: theme,
              ),
              _SortOption(
                label: 'Alphabetical',
                isSelected: currentSort == CollectionSortOption.alphabeticalAsc ||
                    currentSort == CollectionSortOption.alphabeticalDesc,
                onTap: () => _select(context, CollectionSortOption.alphabeticalAsc),
                theme: theme,
              ),
              _SortOption(
                label: 'Creator',
                isSelected: currentSort == CollectionSortOption.creator,
                onTap: () => _select(context, CollectionSortOption.creator),
                theme: theme,
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
  }

  void _select(BuildContext context, CollectionSortOption sort) {
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