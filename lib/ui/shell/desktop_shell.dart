import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../core/playback/playback_engine.dart';
import '../../providers/music_player_provider.dart';
import '../../providers/playlist_provider.dart';
import '../../screens/home/home_screen.dart';
import '../../screens/search/search_screen.dart';
import '../../screens/library/library_screen.dart';
import '../../screens/profile/profile_screen.dart';
import '../../widgets/player/desktop_bottom_player_bar.dart';
import '../../widgets/player/desktop_context_panel.dart';
import '../../widgets/premium/premium_sidebar.dart';
import '../../widgets/premium/desktop_top_bar.dart';
import '../../widgets/playlist/add_to_playlist_sheet.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// ⚠️ Phase 6.5 Batch 5 — DesktopShell now uses the permanent desktop
/// player architecture: full-width [DesktopBottomPlayerBar] (replaces
/// the temporary `FloatingMiniPlayer` reuse from Batch 1.5) + a
/// collapsible right-side [DesktopContextPanel] (Queue/Artist/Album/
/// Lyrics tabs — only Queue is functional this batch, the rest are
/// locked-in placeholders per the roadmap's desktop identity goals).
///
/// `desktop_player_layout.dart` (the old multi-panel body swap) is no
/// longer referenced here — its queue section was extracted into
/// `widgets/queue/queue_list_panel.dart` and reused by
/// `DesktopContextPanel`. The file itself is left in place (per
/// WORKFLOW RULES — unused code isn't deleted without explicit
/// instruction) but is now dead code from this shell's perspective.
///
/// Keyboard shortcuts — unchanged from the previous batch (Space,
/// Ctrl+arrows for next/prev, Ctrl+Up/Down for volume, Ctrl+M for
/// mute, bare arrows for seek ±10s).
class DesktopShell extends ConsumerStatefulWidget {
  const DesktopShell({super.key, this.initialLibrarySection});

  /// Router Shell Bug fix — /library/:section deep-link থেকে chrome-wrap
  /// হয়ে এলে শুরুতেই এই section সিলেক্টেড থাকবে (Library tab + সঠিক
  /// sub-section, PremiumSidebar-এর হাইলাইটও ম্যাচ করবে)।
  final String? initialLibrarySection;

  @override
  ConsumerState<DesktopShell> createState() => _DesktopShellState();
}

class _DesktopShellState extends ConsumerState<DesktopShell> {
  late int _index = widget.initialLibrarySection != null ? 2 : 0;

  // ⚠️ Locked decision (this batch): collapsible via a simple toggle
  // button + AnimatedContainer width animation. No drag-resize
  // (explicitly Phase 7+).
  bool _isContextPanelVisible = true;

  // ⚠️ Resizable panels — drag-handle দিয়ে বদলানো যাবে। Min/max clamp
  // করা হয়েছে যাতে user দুর্ঘটনাক্রমে panel সম্পূর্ণ ভেঙে না ফেলে বা
  // অস্বাভাবিক চওড়া করে না ফেলে।
  double _sidebarWidth = 240;
  static const _sidebarMinWidth = 180.0;
  static const _sidebarMaxWidth = 340.0;

  double _contextPanelWidth = 320;
  static const _contextPanelMinWidth = 240.0;
  static const _contextPanelMaxWidth = 440.0;

  // ⚠️ UI-Batch 2 — tracks which Library sub-section is active for
  // PremiumSidebar's highlight state. 'root' or null = hub view.
  // Kept as shell-level state (not GoRouter) since we're staying on
  // IndexedStack navigation this batch — LibraryScreen is rebuilt with
  // a new `key` + `section` when this changes, forcing its
  // postFrameCallback deep-link logic to re-run.
  late String? _activeLibrarySection = widget.initialLibrarySection;

  // ⚠️ Real back/forward history stack — IndexedStack nav-এর জন্য
  // lightweight in-memory implementation (GoRouter migration ছাড়াই)।
  // প্রতিটা entry: (tabIndex, librarySection)
  late final List<_NavEntry> _history = [
    _NavEntry(widget.initialLibrarySection != null ? 2 : 0, widget.initialLibrarySection),
  ];
  int _historyPointer = 0;

  List<Widget> get _bodies => [
        const HomeScreen(),
        const SearchScreen(),
        LibraryScreen(key: ValueKey(_activeLibrarySection), section: _activeLibrarySection),
        const ProfileScreen(),
      ];

  void _onDestinationSelected(int index) {
    setState(() => _index = index);
    _pushHistory(_NavEntry(index, index == 2 ? _activeLibrarySection : null));
  }

  void _onLibrarySectionSelected(String section) {
    final resolved = section == 'root' ? null : section;
    setState(() => _activeLibrarySection = resolved);
    _pushHistory(_NavEntry(2, resolved));
  }

  // নতুন navigation হলে বর্তমান pointer-এর পরের সব entry truncate হয়
  // (browser back-এর-পর-নতুন-navigation-এর মতোই), তারপর নতুন entry push।
  void _pushHistory(_NavEntry entry) {
    if (_historyPointer < _history.length - 1) {
      _history.removeRange(_historyPointer + 1, _history.length);
    }
    if (_history.isNotEmpty && _history.last == entry) return; // no-op duplicate
    _history.add(entry);
    _historyPointer = _history.length - 1;
  }

  bool get _canGoBack => _historyPointer > 0;
  bool get _canGoForward => _historyPointer < _history.length - 1;

  void _goBack() {
    if (!_canGoBack) return;
    setState(() {
      _historyPointer--;
      _applyHistoryEntry(_history[_historyPointer]);
    });
  }

  void _goForward() {
    if (!_canGoForward) return;
    setState(() {
      _historyPointer++;
      _applyHistoryEntry(_history[_historyPointer]);
    });
  }

  void _applyHistoryEntry(_NavEntry entry) {
    _index = entry.tabIndex;
    _activeLibrarySection = entry.librarySection;
  }

  void _toggleContextPanel() {
    setState(() => _isContextPanelVisible = !_isContextPanelVisible);
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final repo = ref.read(musicPlayerRepositoryProvider);

    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.space): () => repo.togglePause(),
        const SingleActivator(LogicalKeyboardKey.arrowRight, control: true): () => repo.next(),
        const SingleActivator(LogicalKeyboardKey.arrowLeft, control: true): () => repo.previous(),
        const SingleActivator(LogicalKeyboardKey.arrowUp, control: true): () =>
            repo.setVolume((repo.currentVolume + 5).clamp(0.0, 100.0)),
        const SingleActivator(LogicalKeyboardKey.arrowDown, control: true): () =>
            repo.setVolume((repo.currentVolume - 5).clamp(0.0, 100.0)),
        const SingleActivator(LogicalKeyboardKey.keyM, control: true): () => repo.toggleMute(),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () {
          final pos = ref.read(playbackPositionProvider).value ?? Duration.zero;
          repo.seek(pos + const Duration(seconds: 10));
        },
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () {
          final pos = ref.read(playbackPositionProvider).value ?? Duration.zero;
          final target = pos - const Duration(seconds: 10);
          repo.seek(target.isNegative ? Duration.zero : target);
        },
        // ⚠️ New this batch — Ctrl+Q toggles the context panel, matching
        // the desktop-app convention (queue/side-panel toggle) used by
        // most reference players.
        const SingleActivator(LogicalKeyboardKey.keyQ, control: true): _toggleContextPanel,
        const SingleActivator(LogicalKeyboardKey.keyK, control: true): () => _onDestinationSelected(1),
      },
     child: Focus(
        autofocus: true,
        child: Scaffold(
          backgroundColor: aurora.background,
          body: Column(
            children: [
              // ⚠️ Fix — Spotify-style layout: TopBar এখন পুরো
              // window-width জুড়ে সবচেয়ে উপরের strip, sidebar-এরও উপরে
              // বিস্তৃত (আগে এটা content-column-এর ভেতরে ছিল, sidebar-এর
              // পাশাপাশি একই row-তে — যেটা visually sidebar আর content
              // দুই ভাগে top bar-কে ভেঙে দিচ্ছিল)। নিচে sidebar+content+
              // context-panel আলাদা Row হিসেবে থাকছে।
              DesktopTopBar(
                canGoBack: _canGoBack,
                canGoForward: _canGoForward,
                onBack: _goBack,
                onForward: _goForward,
                onSearchTap: () => _onDestinationSelected(1),
                onSettingsTap: () => context.push('/settings'),
                onProfileTap: () => _onDestinationSelected(3),
              ),
              Divider(height: 1, color: aurora.glassBorder),
              Expanded(
                child: Row(
                  children: [
                   SizedBox(
                      width: _sidebarWidth,
                      child: PremiumSidebar(
                        selectedIndex: _index,
                        onDestinationSelected: _onDestinationSelected,
                        activeLibrarySection: _activeLibrarySection,
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
                      child: IndexedStack(index: _index, children: _bodies),
                    ),
                    // ⚠️ Right Context Panel — collapsible via
                    // AnimatedContainer width (0 ↔ _contextPanelWidth).
                    // Content itself (DesktopContextPanel) doesn't own
                    // visibility — this shell does, so the toggle
                    // affordance can live in the bottom player bar's
                    // queue-icon button rather than disappearing along
                    // with the panel. Drag-resize now supported via
                    // _ResizeHandle on the panel's left edge.
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
                      child: _isContextPanelVisible
                          ? const DesktopContextPanel()
                          : null,
                    ),
                  ],
                ),
              ),
              // ⚠️ Phase 6.5 Batch 5 — permanent full-width desktop
              // player bar (replaces the Batch 1.5 temporary
              // FloatingMiniPlayer reuse). "Add to Playlist" still
              // presented as a bottom sheet for now (same pattern as
              // MusicPlayerScreen/NowPlayingScreen) — a desktop-native
              // popover is a future polish item, not blocking this
              // batch's architecture goal.
              DesktopBottomPlayerBar(
                isQueuePanelVisible: _isContextPanelVisible,
                onToggleQueuePanel: _toggleContextPanel,
                onAddToPlaylist: (track) => _showAddToPlaylistSheet(context, track),
                onExpand: () => context.push('/player'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ⚠️ Same bottom-sheet pattern as MusicPlayerScreen/NowPlayingScreen's
  // add-to-playlist flow. This is now the THIRD near-identical copy of
  // this sheet (MusicPlayerScreen, NowPlayingScreen, here) — flagged
  // explicitly as a Batch 6 cleanup candidate (extract into
  // widgets/playlist/add_to_playlist_sheet.dart) rather than inventing
  // an unverified shared function in this batch. Kept inline and
  // minimal here deliberately: DesktopShell's add-to-playlist entry
  // point is the same underlying PlaylistRepository calls, just needs
  // BuildContext + WidgetRef, both available on this ConsumerState.
  void _showAddToPlaylistSheet(BuildContext context, SearchResult track) {
    AddToPlaylistSheet.show(
      context: context,
      track: track,
    );
  }
}

// ⚠️ Real back/forward history — lightweight nav-state snapshot।
// GoRouter নয়, শুধু (tab index, library section) মনে রাখে IndexedStack
// navigation-এর জন্য।
/// Sidebar/Context-panel-এর edge-এ বসানো drag-handle — resize করার জায়গা
/// visually বোঝাতে সরু ফাঁকা gap (hover করলে accent-highlighted),
/// cursor resizeColumn দেখায়। [onDrag] প্রতিটা pointer-move delta.dx
/// দেয়, parent সেটা দিয়ে নিজের width state আপডেট করে (clamp সহ)।
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

class _NavEntry {
  final int tabIndex;
  final String? librarySection;
  const _NavEntry(this.tabIndex, this.librarySection);

  @override
  bool operator ==(Object other) =>
      other is _NavEntry && other.tabIndex == tabIndex && other.librarySection == librarySection;

  @override
  int get hashCode => Object.hash(tabIndex, librarySection);
}
