import 'package:flutter/material.dart';

/// Single source of truth for shell navigation.
///
/// Why this exists: `DesktopShell` and `MobileShell` previously each
/// declared their own `_destinations`/`_bodies` lists with the same four
/// tabs in the same order. Any tab addition meant editing two files and
/// hoping they stayed in sync. This is that list, once.
///
/// Adding a tab = one entry here. Both chrome variants pick it up.
class ShellDestination {
  const ShellDestination({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.route,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Canonical route for this tab. Used by the desktop sidebar (which
  /// navigates by URL so deep-links work) and by the mobile bar's
  /// long-press-to-copy-current-path affordance.
  final String route;

  /// Short label for the bottom nav bar — the full [label] can overflow
  /// a 4-up bar on a 320dp screen.
  String get shortLabel =>
      label.length <= 8 ? label : '${label.substring(0, 7)}\u2026';
}

/// The locked 4-tab shell structure (matches the design brief: 3–5 items,
/// label always visible).
///
/// `Library` intentionally points at `/library` (the hub) rather than a
/// sub-section — sub-sections are deep-links, not tabs.
const List<ShellDestination> kShellDestinations = [
  ShellDestination(
    icon: Icons.home_outlined,
    selectedIcon: Icons.home_rounded,
    label: 'Home',
    route: '/home',
  ),
  ShellDestination(
    icon: Icons.library_music_outlined,
    selectedIcon: Icons.library_music_rounded,
    label: 'Library',
    route: '/library',
  ),
  ShellDestination(
    icon: Icons.person_outline_rounded,
    selectedIcon: Icons.person_rounded,
    label: 'Profile',
    route: '/profile',
  ),
];

/// Sidebar-only destinations (desktop has room for a real library tree;
/// mobile reaches these through the Library tab's own bento grid).
/// Kept here so the sidebar and any future command-palette share them.
class ShellSidebarSection {
  const ShellSidebarSection({required this.label, required this.items});
  final String label;
  final List<ShellSidebarItem> items;
}

class ShellSidebarItem {
  const ShellSidebarItem({
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.section,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;

  /// Library sub-section key — matches `LibraryScreen.section` and the
  /// `/library/:section` route param.
  final String section;
}

const List<ShellSidebarSection> kShellSidebarSections = [
  ShellSidebarSection(
    label: 'YOUR SPACE',
    items: [
      ShellSidebarItem(
        icon: Icons.favorite_border_rounded,
        selectedIcon: Icons.favorite_rounded,
        label: 'Favorites',
        section: 'favorites',
      ),
      ShellSidebarItem(
        icon: Icons.queue_music_outlined,
        selectedIcon: Icons.queue_music_rounded,
        label: 'Playlists',
        section: 'playlists',
      ),
      ShellSidebarItem(
        icon: Icons.download_outlined,
        selectedIcon: Icons.download_done_rounded,
        label: 'Offline',
        section: 'offline',
      ),
      ShellSidebarItem(
        icon: Icons.history_rounded,
        selectedIcon: Icons.history_rounded,
        label: 'Recently Played',
        section: 'recent',
      ),
    ],
  ),
  ShellSidebarSection(
    label: 'COLLECTIONS',
    items: [
      ShellSidebarItem(
        icon: Icons.local_fire_department_outlined,
        selectedIcon: Icons.local_fire_department_rounded,
        label: 'Most Played',
        section: 'most-played',
      ),
      ShellSidebarItem(
        icon: Icons.insights_outlined,
        selectedIcon: Icons.insights_rounded,
        label: 'Statistics',
        section: 'statistics',
      ),
    ],
  ),
];
