import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/keyboard_shortcuts.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../providers/music_player_provider.dart';
import '../../widgets/player/desktop_bottom_player_bar.dart';
import '../../widgets/player/desktop_context_panel.dart';
import '../../widgets/playlist/add_to_playlist_sheet.dart';
import '../../widgets/premium/desktop_top_bar.dart';
import '../../widgets/premium/premium_sidebar.dart';
import 'platform_shell.dart';

/// Keeps pushed detail screens inside Spotify's 3-column pane on desktop/web:
/// [Left Sidebar] | [Middle Screen View] | [Right Context Panel/Queue] + [Bottom Player Bar].
///
/// On phones/mobile, the child is returned directly as a clean full-screen push.
class DesktopContentFrame extends ConsumerStatefulWidget {
  const DesktopContentFrame({
    super.key,
    required this.child,
    this.activeLibrarySection,
  });

  final Widget child;
  final String? activeLibrarySection;

  @override
  ConsumerState<DesktopContentFrame> createState() => _DesktopContentFrameState();
}

class _DesktopContentFrameState extends ConsumerState<DesktopContentFrame> {
  bool _isContextPanelVisible = true;

  double _sidebarWidth = 240;
  static const _sidebarMinWidth = 180.0;
  static const _sidebarMaxWidth = 340.0;

  double _contextPanelWidth = 320;
  static const _contextPanelMinWidth = 240.0;
  static const _contextPanelMaxWidth = 440.0;

  void _toggleContextPanel() {
    setState(() => _isContextPanelVisible = !_isContextPanelVisible);
  }

  void _onDestinationSelected(int index) {
    switch (index) {
      case 0:
        context.go('/home');
        break;
      case 1:
        context.go('/home');
        break;
      case 2:
        context.go('/library');
        break;
      case 3:
        context.go('/home');
        break;
    }
  }

  void _onLibrarySectionSelected(String section) {
    switch (section) {
      case 'favorites':
        context.go('/library/favorites');
        break;
      case 'playlists':
        context.go('/library/playlists');
        break;
      case 'offline':
      case 'offline/downloaded':
        context.go('/library/offline/downloaded');
        break;
      case 'offline/cached':
        context.go('/library/offline/cached');
        break;
      case 'recent':
        context.go('/library/recent');
        break;
      case 'most-played':
        context.go('/library/most');
        break;
      default:
        context.go('/library');
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!PlatformShell.isDesktopPlatform) return widget.child;

    final aurora = context.aurora;
    final repo = ref.watch(musicPlayerRepositoryProvider);

    // Determine active destination based on current URL path
    final currentLoc = GoRouterState.of(context).uri.path;
    int selectedIndex = 2; // Default to Library tab for library/sub-pages
    String? currentSection = widget.activeLibrarySection;

    if (currentLoc.startsWith('/home')) {
      selectedIndex = 0;
      currentSection = null;
    } else if (currentLoc.startsWith('/search')) {
      selectedIndex = 1;
      currentSection = null;
    } else if (currentLoc.startsWith('/profile')) {
      selectedIndex = 3;
      currentSection = null;
    } else if (currentLoc.contains('/favorites')) {
      currentSection = 'favorites';
    } else if (currentLoc.contains('/playlists')) {
      currentSection = 'playlists';
    } else if (currentLoc.contains('/offline') || currentLoc.contains('/downloaded')) {
      currentSection = 'offline';
    } else if (currentLoc.contains('/recent') || currentLoc.contains('/history')) {
      currentSection = 'recent';
    } else if (currentLoc.contains('/most')) {
      currentSection = 'most-played';
    }

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () {
          if (!isTextFieldFocused(context)) repo.togglePause();
        },
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () {
          if (!isTextFieldFocused(context)) repo.next();
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () {
          if (!isTextFieldFocused(context)) repo.previous();
        },
      },
      child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: aurora.background,
          body: Column(
            children: [
              DesktopTopBar(
                canGoBack: context.canPop(),
                canGoForward: false,
                onBack: () => context.canPop() ? context.pop() : context.go('/home'),
                onForward: () {},
                onSearchTap: () => context.go('/home'),
                onSettingsTap: () => context.push('/settings'),
                onProfileTap: () => context.go('/home'),
              ),
              Divider(height: 1, color: aurora.glassBorder),
              Expanded(
                child: Row(
                  children: [
                    SizedBox(
                      width: _sidebarWidth,
                      child: PremiumSidebar(
                        selectedIndex: selectedIndex,
                        onDestinationSelected: _onDestinationSelected,
                        activeLibrarySection: currentSection,
                        onLibrarySectionSelected: _onLibrarySectionSelected,
                        onSettingsTap: () => context.push('/settings'),
                      ),
                    ),
                    _ResizeHandle(
                      onDrag: (dx) {
                        setState(() {
                          _sidebarWidth =
                              (_sidebarWidth + dx).clamp(_sidebarMinWidth, _sidebarMaxWidth);
                        });
                      },
                    ),
                    Expanded(
                      child: Container(
                        color: aurora.background,
                        child: widget.child,
                      ),
                    ),
                    if (_isContextPanelVisible)
                      _ResizeHandle(
                        onDrag: (dx) {
                          setState(() {
                            _contextPanelWidth = (_contextPanelWidth - dx)
                                .clamp(_contextPanelMinWidth, _contextPanelMaxWidth);
                          });
                        },
                      ),
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      curve: Curves.easeInOut,
                      width: _isContextPanelVisible ? _contextPanelWidth : 0,
                      child: _isContextPanelVisible ? const DesktopContextPanel() : null,
                    ),
                  ],
                ),
              ),
              DesktopBottomPlayerBar(
                isQueuePanelVisible: _isContextPanelVisible,
                onToggleQueuePanel: _toggleContextPanel,
                onAddToPlaylist: (track) => AddToPlaylistSheet.show(context: context, track: track),
                onExpand: () => context.push('/player'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ResizeHandle extends StatefulWidget {
  const _ResizeHandle({required this.onDrag});
  final ValueChanged<double> onDrag;

  @override
  State<_ResizeHandle> createState() => _ResizeHandleState();
}

class _ResizeHandleState extends State<_ResizeHandle> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return MouseRegion(
      cursor: SystemMouseCursors.resizeColumn,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onHorizontalDragUpdate: (details) => widget.onDrag(details.delta.dx),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 120),
          width: 6,
          decoration: BoxDecoration(
            color: _hovered ? aurora.primary.withOpacity(0.85) : Colors.white.withOpacity(0.04),
          ),
        ),
      ),
    );
  }
}
