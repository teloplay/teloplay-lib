import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/library/library_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../widgets/player/mini_player_dock.dart';
import 'app_bottom_nav.dart';
import 'app_sidebar.dart';

/// The breakpoint where the chrome flips from a bottom bar to a sidebar.
/// Matches the existing platform split: phones stay below it, desktop and
/// web (which `PlatformShell` already treats as desktop) sit above it.
/// 900dp is wide enough for a 248dp rail plus a usable content column.
const double kDesktopBreakpoint = 900;

/// Adaptive shell: bottom nav below [kDesktopBreakpoint], collapsible
/// sidebar above it, mini-player docked at the bottom on both.
///
/// Why width and not platform: a resized desktop window and a tablet in
/// landscape both deserve the same decision, and `LayoutBuilder` already
/// gives us the number. `PlatformShell.isDesktopPlatform` is only the
/// fallback for the very first frame, before a constraint exists.
class ResponsiveShell extends StatefulWidget {
  const ResponsiveShell({super.key, this.initialLibrarySection});

  /// Deep link into a Library sub-section (`/library/:section`).
  final String? initialLibrarySection;

  @override
  State<ResponsiveShell> createState() => _ResponsiveShellState();
}

class _ResponsiveShellState extends State<ResponsiveShell> {
  late int _index = widget.initialLibrarySection != null ? 2 : 0;
  late String? _librarySection = widget.initialLibrarySection;
  bool _sidebarCollapsed = false;

  // IndexedStack, not routing: tab state survives a switch. The four tabs
  // are cheap to keep alive and expensive to rebuild (home rails, search
  // results).
  late final _bodies = <Widget>[
    const HomeScreen(),
    const SearchScreen(),
    LibraryScreen(section: widget.initialLibrarySection),
    const ProfileScreen(),
  ];

  void _select(int index) {
    if (index == _index && index != 2) return;
    setState(() {
      _index = index;
      if (index != 2) _librarySection = null;
    });
  }

  void _openLibrarySection(String section) {
    setState(() {
      _index = 2;
      _librarySection = section;
    });
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Width only. A resized desktop window and a phone browser both
        // deserve the same answer, so the platform flag doesn't vote here.
        final desktop = constraints.maxWidth >= kDesktopBreakpoint;

        return Scaffold(
          backgroundColor: aurora.background,
          body: Row(
            children: [
              if (desktop)
                AppSidebar(
                  selectedIndex: _index,
                  collapsed: _sidebarCollapsed,
                  activeLibrarySection: _index == 2 ? _librarySection : null,
                  onDestinationSelected: _select,
                  onLibrarySectionSelected: _openLibrarySection,
                  onSettingsTap: () => context.push('/settings'),
                  onToggleCollapsed: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
                ),
              Expanded(
                child: Column(
                  children: [
                    Expanded(
                      child: IndexedStack(
                        index: _index,
                        children: [
                          _bodies[0],
                          _bodies[1],
                          // Rebuilt with a key so a section change re-runs
                          // LibraryScreen's deep-link callback.
                          LibraryScreen(key: ValueKey(_librarySection), section: _librarySection),
                          _bodies[3],
                        ],
                      ),
                    ),
                    Padding(
                      padding: EdgeInsets.fromLTRB(
                        AppSpacing.md,
                        0,
                        AppSpacing.md,
                        desktop ? AppSpacing.md : AppSpacing.sm,
                      ),
                      child: MiniPlayerDock(
                        onExpand: () => context.push('/player'),
                        onToggleQueue: desktop ? () => context.push('/player') : null,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          bottomNavigationBar: desktop
              ? null
              : AppBottomNav(selectedIndex: _index, onSelected: _select),
        );
      },
    );
  }
}
