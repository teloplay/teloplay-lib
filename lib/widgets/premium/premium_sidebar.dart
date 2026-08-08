import 'package:flutter/material.dart';

import '../../core/theme/app_theme_extension.dart';
import 'sidebar_nav_item.dart';

/// ⚠️ UI-Batch 2 — assembles the sidebar primitives (SidebarSectionHeader +
/// SidebarNavItem, built in UI-Batch 1) into the full locked sidebar
/// structure. Navigation is index-based (matches DesktopShell's existing
/// IndexedStack pattern — no ShellRoute/GoRouter migration this batch).
///
/// ✅ Verified against real sidebar_nav_item.dart: SidebarNavItem takes
/// `selected` (not isActive), `compact`, `selectedIcon`, `onTap`.
/// SidebarSectionHeader takes only `label` (no compact param).
///
/// Locked structure:
/// Home / Search
/// YOUR SPACE: Library, Favorites, Playlists, Offline (+Downloaded/Cached
///   sub-tabs handled inside LibraryScreen, not the sidebar), Recently Played
/// COLLECTIONS: Most Played
/// Footer: Settings, Profile
///
/// `onLibrarySectionSelected` lets Favorites/Playlists/Offline/Recently
/// Played/Most Played deep-link into LibraryScreen's internal section
/// state (via the /library/:section nested route) instead of becoming
/// separate top-level screens — per the locked Hybrid Library Deep-Link
/// decision.
class PremiumSidebar extends StatelessWidget {
  final int selectedIndex; // 0=Home 1=Search 2=Library 3=Profile (matches DesktopShell._bodies)
  final ValueChanged<int> onDestinationSelected;
  final String? activeLibrarySection; // null when not on Library tab
  final ValueChanged<String> onLibrarySectionSelected;
  final VoidCallback onSettingsTap;
  final bool collapsed;

  const PremiumSidebar({
    super.key,
    required this.selectedIndex,
    required this.onDestinationSelected,
    required this.activeLibrarySection,
    required this.onLibrarySectionSelected,
    required this.onSettingsTap,
    this.collapsed = false,
  });

  bool get _onLibraryTab => selectedIndex == 2;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return Container(
      width: collapsed ? 76 : 240,
      color: aurora.surface,
      child: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                children: [
                  SidebarNavItem(
                    icon: Icons.home_outlined,
                    selectedIcon: Icons.home,
                    label: 'Home',
                    selected: selectedIndex == 0,
                    compact: collapsed,
                    onTap: () => onDestinationSelected(0),
                  ),
                  SidebarNavItem(
                    icon: Icons.search_outlined,
                    selectedIcon: Icons.search,
                    label: 'Search',
                    selected: selectedIndex == 1,
                    compact: collapsed,
                    onTap: () => onDestinationSelected(1),
                  ),
                  const SizedBox(height: 8),
                  SidebarSectionHeader(label: 'YOUR SPACE'),
                  SidebarNavItem(
                    icon: Icons.library_music_outlined,
                    selectedIcon: Icons.library_music,
                    label: 'Library',
                    selected: _onLibraryTab && activeLibrarySection == null,
                    compact: collapsed,
                    onTap: () {
                      onDestinationSelected(2);
                      onLibrarySectionSelected('root');
                    },
                  ),
                  SidebarNavItem(
                    icon: Icons.favorite_border,
                    selectedIcon: Icons.favorite,
                    label: 'Favorites',
                    selected: _onLibraryTab && activeLibrarySection == 'favorites',
                    compact: collapsed,
                    onTap: () {
                      onDestinationSelected(2);
                      onLibrarySectionSelected('favorites');
                    },
                  ),
                  SidebarNavItem(
                    icon: Icons.playlist_play_outlined,
                    selectedIcon: Icons.playlist_play,
                    label: 'Playlists',
                    selected: _onLibraryTab && activeLibrarySection == 'playlists',
                    compact: collapsed,
                    onTap: () {
                      onDestinationSelected(2);
                      onLibrarySectionSelected('playlists');
                    },
                  ),
                  SidebarNavItem(
                    icon: Icons.download_outlined,
                    selectedIcon: Icons.download_done,
                    label: 'Offline',
                    selected: _onLibraryTab &&
                        (activeLibrarySection == 'offline' ||
                            activeLibrarySection == 'offline/downloaded' ||
                            activeLibrarySection == 'offline/cached'),
                    compact: collapsed,
                    onTap: () {
                      onDestinationSelected(2);
                      onLibrarySectionSelected('offline');
                    },
                  ),
                  SidebarNavItem(
                    icon: Icons.history,
                    selectedIcon: Icons.history,
                    label: 'Recently Played',
                    selected: _onLibraryTab && activeLibrarySection == 'recent',
                    compact: collapsed,
                    onTap: () {
                      onDestinationSelected(2);
                      onLibrarySectionSelected('recent');
                    },
                  ),
                  const SizedBox(height: 8),
                  SidebarSectionHeader(label: 'COLLECTIONS'),
                  SidebarNavItem(
                    icon: Icons.local_fire_department_outlined,
                    selectedIcon: Icons.local_fire_department,
                    label: 'Most Played',
                    selected: _onLibraryTab && activeLibrarySection == 'most-played',
                    compact: collapsed,
                    onTap: () {
                      onDestinationSelected(2);
                      onLibrarySectionSelected('most-played');
                    },
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: aurora.glassBorder),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                children: [
                  SidebarNavItem(
                    icon: Icons.settings_outlined,
                    selectedIcon: Icons.settings,
                    label: 'Settings',
                    selected: false,
                    compact: collapsed,
                    onTap: onSettingsTap,
                  ),
                  SidebarNavItem(
                    icon: Icons.person_outline,
                    selectedIcon: Icons.person,
                    label: 'Profile',
                    selected: selectedIndex == 3,
                    compact: collapsed,
                    onTap: () => onDestinationSelected(3),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}