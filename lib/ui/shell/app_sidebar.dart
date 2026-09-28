import 'dart:ui';

import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';
import 'shell_destinations.dart';
import 'sidebar_nav_tile.dart';

/// Collapsible glass sidebar — desktop/web chrome.
///
/// Same locked structure as the old PremiumSidebar (Home/Search, then
/// YOUR SPACE, COLLECTIONS, then the Settings/Profile footer), but the
/// collapsed state animates instead of jumping and the rail is actually
/// frosted — content scrolling behind it blurs through.
///
/// Collapsed = 76dp icon rail. The 3dp accent bar on the selected row is
/// the only full-height element kept in both states; it's what keeps a
/// label-less rail readable.
class AppSidebar extends StatelessWidget {
  const AppSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.activeLibrarySection,
    required this.onLibrarySectionSelected,
    required this.onSettingsTap,
    this.collapsed = false,
    this.onToggleCollapsed,
  });

  final int selectedIndex;
  final ValueChanged<int> onDestinationSelected;

  /// null when on Library root overview tab.
  final String? activeLibrarySection;
  final ValueChanged<String> onLibrarySectionSelected;
  final VoidCallback onSettingsTap;
  final bool collapsed;
  final VoidCallback? onToggleCollapsed;

  bool get _onLibraryTab => selectedIndex == 2;

  /// 'offline', 'offline/downloaded' and 'offline/cached' all light up the
  /// single Offline rail entry.
  bool _sectionMatches(ShellSidebarItem item) {
    final active = activeLibrarySection;
    if (active == null) return false;
    if (item.section == 'offline') return active.startsWith('offline');
    return active == item.section;
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final width = collapsed ? AppSpacing.sidebarCollapsedWidth : AppSpacing.sidebarExpandedWidth;

    return AnimatedContainer(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOutCubic,
      width: width,
      decoration: BoxDecoration(
        color: aurora.surface.withOpacity(0.72),
        border: Border(right: BorderSide(color: aurora.glassBorder, width: 1)),
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 24, sigmaY: 24),
          child: SafeArea(
            child: Column(
              children: [
                _BrandMark(collapsed: collapsed, onToggle: onToggleCollapsed),
                Expanded(
                  child: ListView(
                    padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                    children: [
                      SidebarNavTile(
                        icon: Icons.home_outlined,
                        selectedIcon: Icons.home_rounded,
                        label: 'Home',
                        selected: selectedIndex == 0,
                        collapsed: collapsed,
                        onTap: () => onDestinationSelected(0),
                      ),
                      const SizedBox(height: AppSpacing.sm),
                      SidebarSectionHeader(label: 'YOUR SPACE', collapsed: collapsed),
                      SidebarNavTile(
                        icon: Icons.library_music_outlined,
                        selectedIcon: Icons.library_music_rounded,
                        label: 'Library Overview',
                        selected: _onLibraryTab && activeLibrarySection == null,
                        collapsed: collapsed,
                        onTap: () {
                          onDestinationSelected(2);
                          onLibrarySectionSelected('root');
                        },
                      ),
                      for (final item in kShellSidebarSections[0].items)
                        SidebarNavTile(
                          icon: item.icon,
                          selectedIcon: item.selectedIcon,
                          label: item.label,
                          selected: _onLibraryTab && _sectionMatches(item),
                          collapsed: collapsed,
                          onTap: () {
                            onDestinationSelected(2);
                            onLibrarySectionSelected(item.section);
                          },
                        ),
                      const SizedBox(height: AppSpacing.sm),
                      SidebarSectionHeader(
                        label: kShellSidebarSections[1].label,
                        collapsed: collapsed,
                      ),
                      for (final item in kShellSidebarSections[1].items)
                        SidebarNavTile(
                          icon: item.icon,
                          selectedIcon: item.selectedIcon,
                          label: item.label,
                          selected: _onLibraryTab && _sectionMatches(item),
                          collapsed: collapsed,
                          onTap: () {
                            onDestinationSelected(2);
                            onLibrarySectionSelected(item.section);
                          },
                        ),
                    ],
                  ),
                ),
                Divider(height: 1, color: aurora.glassBorder),
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
                  child: Column(
                    children: [
                      SidebarNavTile(
                        icon: Icons.person_outline_rounded,
                        selectedIcon: Icons.person_rounded,
                        label: 'Profile & Settings',
                        selected: selectedIndex == 3,
                        collapsed: collapsed,
                        onTap: () => onDestinationSelected(3),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Logo + wordmark + collapse toggle. The wordmark animates out of the
/// layout (not just fades) so the collapsed rail doesn't stay 248dp wide
/// internally and clip its own icons.
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.collapsed, this.onToggle});

  final bool collapsed;
  final VoidCallback? onToggle;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.md, AppSpacing.sm, AppSpacing.sm),
      child: Row(
        children: [
          Container(
            width: 34,
            height: 34,
            decoration: BoxDecoration(
              gradient: aurora.accentGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
              boxShadow: [
                BoxShadow(
                  color: aurora.primary.withOpacity(0.38),
                  blurRadius: 14,
                  spreadRadius: -2,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            child: const Icon(Icons.graphic_eq_rounded, color: Colors.white, size: 19),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 220),
            curve: Curves.easeOutCubic,
            child: collapsed
                ? const SizedBox.shrink()
                : Padding(
                    padding: const EdgeInsets.only(left: AppSpacing.sm),
                    child: Text(
                      'TeloPlay',
                      style: AppTypography.sectionTitle.copyWith(
                        color: aurora.textPrimary,
                        letterSpacing: -0.6,
                      ),
                    ),
                  ),
          ),
          const Spacer(),
          if (onToggle != null)
            SidebarIconButton(
              icon: collapsed
                  ? Icons.keyboard_double_arrow_right_rounded
                  : Icons.keyboard_double_arrow_left_rounded,
              tooltip: collapsed ? 'Expand sidebar' : 'Collapse sidebar',
              onTap: onToggle!,
            ),
        ],
      ),
    );
  }
}
