import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_theme_extension.dart';
import '../../providers/music_player_provider.dart';
import '../queue/queue_list_panel.dart';

enum _ContextTab { queue, artist, album, lyrics }

/// Phase 6.5 Batch 5 — Right Context Panel for Desktop.
///
/// Locked scope (per developer decision): Queue tab fully functional
/// (reuses [QueueListPanel]); Artist/Album/Lyrics are "Coming Soon"
/// placeholders — no backend yet, this batch only locks the shell
/// structure so those tabs can be filled in later (Phase 7+) without
/// another DesktopShell refactor.
///
/// Collapsible via [isVisible] (owned by parent `DesktopShell` state) +
/// [onToggle] callback for the collapse button. Width animates via
/// `AnimatedContainer` in the parent — this widget itself just renders
/// its content; parent controls the 0/320 width toggle so the toggle
/// button can live in the shell's persistent chrome (e.g. next to the
/// bottom player bar's "Queue" button) rather than inside the panel
/// itself, which would disappear along with the panel when collapsed.
///
/// Tab row uses Expanded-wrapped icons (not spaceEvenly with natural
/// sizing) so it never overflows even when the panel is narrow —
/// each tab is forced to fit within its allotted 1/4 share of width.
///
/// Drag-resize intentionally NOT implemented (Phase 7+, per decision).
class DesktopContextPanel extends ConsumerStatefulWidget {
  const DesktopContextPanel({super.key});

  @override
  ConsumerState<DesktopContextPanel> createState() => _DesktopContextPanelState();
}

class _DesktopContextPanelState extends ConsumerState<DesktopContextPanel> {
  _ContextTab _tab = _ContextTab.queue;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final currentTrack = ref.watch(currentTrackProvider).value;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(10, 14, 10, 10),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: _TabIcon(
                  icon: Icons.queue_music,
                  tooltip: 'Queue',
                  selected: _tab == _ContextTab.queue,
                  onTap: () => setState(() => _tab = _ContextTab.queue),
                ),
              ),
              Expanded(
                child: _TabIcon(
                  icon: Icons.person_outline,
                  tooltip: 'Artist',
                  selected: _tab == _ContextTab.artist,
                  onTap: () => setState(() => _tab = _ContextTab.artist),
                ),
              ),
              Expanded(
                child: _TabIcon(
                  icon: Icons.album_outlined,
                  tooltip: 'Album',
                  selected: _tab == _ContextTab.album,
                  onTap: () => setState(() => _tab = _ContextTab.album),
                ),
              ),
              Expanded(
                child: _TabIcon(
                  icon: Icons.lyrics_outlined,
                  tooltip: 'Lyrics',
                  selected: _tab == _ContextTab.lyrics,
                  onTap: () => setState(() => _tab = _ContextTab.lyrics),
                ),
              ),
            ],
          ),
        ),
        Container(
          height: 1,
          margin: const EdgeInsets.symmetric(horizontal: 14),
          decoration: BoxDecoration(
            gradient: LinearGradient(
              colors: [Colors.transparent, aurora.glassBorder, Colors.transparent],
            ),
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(6, 10, 6, 6),
            child: switch (_tab) {
              _ContextTab.queue => const QueueListPanel(),
              _ContextTab.artist => _ComingSoon(
                  icon: Icons.person_outline,
                  label: 'Artist',
                  subtitle: currentTrack?.author,
                ),
              _ContextTab.album => const _ComingSoon(
                  icon: Icons.album_outlined,
                  label: 'Album',
                ),
              _ContextTab.lyrics => const _ComingSoon(
                  icon: Icons.lyrics_outlined,
                  label: 'Lyrics',
                ),
            },
          ),
        ),
      ],
    );
  }
}

class _TabIcon extends StatefulWidget {
  const _TabIcon({
    required this.icon,
    required this.tooltip,
    required this.selected,
    required this.onTap,
  });

  final IconData icon;
  final String tooltip;
  final bool selected;
  final VoidCallback onTap;

  @override
  State<_TabIcon> createState() => _TabIconState();
}

class _TabIconState extends State<_TabIcon> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: widget.onTap,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
            margin: const EdgeInsets.symmetric(horizontal: 2),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              gradient: widget.selected ? aurora.accentGradient : null,
              color: widget.selected ? null : (_hovered ? aurora.surfaceElevated : Colors.transparent),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(
              widget.icon,
              size: 18,
              color: widget.selected ? Colors.white : aurora.textSecondary,
            ),
          ),
        ),
      ),
    );
  }
}

class _ComingSoon extends StatelessWidget {
  const _ComingSoon({required this.icon, required this.label, this.subtitle});

  final IconData icon;
  final String label;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 32, color: aurora.textSecondary.withOpacity(0.5)),
          const SizedBox(height: 12),
          Text(
            label,
            style: TextStyle(color: aurora.textPrimary, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          if (subtitle != null) ...[
            const SizedBox(height: 4),
            Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: aurora.textSecondary, fontSize: 12),
            ),
          ],
          const SizedBox(height: 4),
          Text(
            'Coming Soon',
            style: TextStyle(color: aurora.textSecondary.withOpacity(0.7), fontSize: 11),
          ),
        ],
      ),
    );
  }
}