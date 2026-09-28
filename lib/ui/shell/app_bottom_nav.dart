import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
import 'shell_destinations.dart';

/// Glass bottom navigation — mobile chrome.
///
/// Design-brief constraints this satisfies: 3-5 items, label always
/// visible, 48dp touch target, no default Material bar. The selected
/// item gets a tinted pill behind its icon (not a full-row highlight —
/// that reads as a button, which these aren't) and a slightly bolder label.
///
/// Frosted, not solid: the mini-player and content scroll underneath it,
/// so a flat fill would hide the album art. The blur is the point.
class AppBottomNav extends StatelessWidget {
  const AppBottomNav({super.key, required this.selectedIndex, required this.onSelected});

  final int selectedIndex;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return ClipRect(
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
        child: Container(
          height: AppSpacing.bottomNavHeight,
          decoration: BoxDecoration(
            color: aurora.glassFillStrong,
            border: Border(top: BorderSide(color: aurora.glassBorder, width: 1)),
          ),
          child: Row(
            children: [
              for (var i = 0; i < kShellDestinations.length; i++)
                Expanded(
                  child: _NavItem(
                    destination: kShellDestinations[i],
                    selected: selectedIndex == i,
                    onTap: () => onSelected(i),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavItem extends StatelessWidget {
  const _NavItem({required this.destination, required this.selected, required this.onTap});

  final ShellDestination destination;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final fg = selected ? aurora.primary : aurora.textSecondary;

    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      highlightColor: Colors.transparent,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.xs),
            decoration: BoxDecoration(
              color: selected ? aurora.primary.withOpacity(0.16) : Colors.transparent,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
            child: Icon(
              selected ? destination.selectedIcon : destination.icon,
              size: 22,
              color: fg,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            destination.shortLabel,
            style: AppTypography.overline.copyWith(
              color: fg,
              letterSpacing: 0,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }
}
