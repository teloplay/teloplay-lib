import 'package:flutter/material.dart';

import '../../core/theme/app_theme_extension.dart';

/// Phase 6.5 Premium Design System — building blocks for the Batch 2
/// desktop sidebar redesign (grouped sections: HOME/SEARCH, YOUR SPACE,
/// COLLECTIONS, footer Settings/Profile — per the locked mockup).
///
/// Kept as standalone primitives (not baked into DesktopShell directly)
/// so both the sidebar and any future grouped-nav surface (e.g. a
/// mobile drawer, if ever added) can reuse them.

/// Small uppercase section label ("YOUR SPACE", "COLLECTIONS").
class SidebarSectionHeader extends StatelessWidget {
  const SidebarSectionHeader({super.key, required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: aurora.textDisabled,
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.1,
        ),
      ),
    );
  }
}

/// A single sidebar nav row — icon + label, hover background, and a
/// gradient active-indicator bar on the leading edge when [selected].
/// [compact] renders icon-only (for the sidebar's collapsed state).
class SidebarNavItem extends StatefulWidget {
  const SidebarNavItem({
    super.key,
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.selectedIcon,
    this.compact = false,
    this.trailing,
  });

  final IconData icon;
  final IconData? selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool compact;
  final Widget? trailing;

  @override
  State<SidebarNavItem> createState() => _SidebarNavItemState();
}

class _SidebarNavItemState extends State<SidebarNavItem> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final active = widget.selected;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: Curves.easeOut,
          margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
          padding: EdgeInsets.symmetric(
            horizontal: widget.compact ? 0 : 12,
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: active
                ? aurora.primary.withOpacity(0.14)
                : (_hovered ? Colors.white.withOpacity(0.04) : Colors.transparent),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            mainAxisAlignment:
                widget.compact ? MainAxisAlignment.center : MainAxisAlignment.start,
            children: [
              // Active indicator — small gradient bar, not present
              // when compact/collapsed (no room, and the background
              // tint + icon color already signal state).
              if (!widget.compact) ...[
                AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  width: 3,
                  height: active ? 18 : 0,
                  decoration: BoxDecoration(
                    gradient: aurora.accentGradient,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                SizedBox(width: active ? 9 : 12),
              ],
              Icon(
                active ? (widget.selectedIcon ?? widget.icon) : widget.icon,
                size: 20,
                color: active ? aurora.textPrimary : aurora.textSecondary,
              ),
              if (!widget.compact) ...[
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: active ? aurora.textPrimary : aurora.textSecondary,
                      fontSize: 13.5,
                      fontWeight: active ? FontWeight.w600 : FontWeight.w500,
                    ),
                  ),
                ),
                if (widget.trailing != null) widget.trailing!,
              ],
            ],
          ),
        ),
      ),
    );
  }
}