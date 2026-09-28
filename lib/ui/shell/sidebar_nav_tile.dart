import 'package:flutter/material.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/theme/app_theme_extension.dart';
import '../../core/theme/app_typography.dart';

/// One sidebar row. Three states, all animated:
/// idle (textSecondary, no fill), hovered (faint white wash), selected
/// (accent tint + a 3dp accent rail on the leading edge).
///
/// Collapsed: icon only, centred, label dropped from the tree (not just
/// opacity-0, or it would keep its layout width and the 76dp rail would
/// clip itself). A Tooltip carries the label in that state.
class SidebarNavTile extends StatefulWidget {
  const SidebarNavTile({
    super.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.collapsed = false,
  });

  final IconData icon;
  final IconData selectedIcon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool collapsed;

  @override
  State<SidebarNavTile> createState() => _SidebarNavTileState();
}

class _SidebarNavTileState extends State<SidebarNavTile> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;
    final active = widget.selected;
    final fg = active
        ? aurora.primary
        : (_hovered ? aurora.textPrimary : aurora.textSecondary);

    final tile = AnimatedContainer(
      duration: const Duration(milliseconds: 160),
      curve: Curves.easeOut,
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: 2),
      height: AppSpacing.listRowHeight - 8,
      decoration: BoxDecoration(
        color: active
            ? aurora.primary.withOpacity(0.14)
            : (_hovered ? Colors.white.withOpacity(0.055) : Colors.transparent),
        borderRadius: BorderRadius.circular(AppSpacing.radiusMd),
      ),
      child: Row(
        children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: active ? 3 : 0,
            height: 22,
            decoration: BoxDecoration(
              gradient: aurora.accentGradient,
              borderRadius: BorderRadius.circular(AppSpacing.radiusPill),
            ),
          ),
          SizedBox(width: widget.collapsed ? 0 : AppSpacing.md),
          Expanded(
            child: Row(
              mainAxisAlignment: widget.collapsed
                  ? MainAxisAlignment.center
                  : MainAxisAlignment.start,
              children: [
                Icon(active ? widget.selectedIcon : widget.icon, size: 21, color: fg),
                if (!widget.collapsed)
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.md),
                      child: Text(
                        widget.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: AppTypography.button.copyWith(
                          color: fg,
                          fontSize: 14,
                          fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          if (!widget.collapsed) const SizedBox(width: AppSpacing.sm),
        ],
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: widget.collapsed
            ? Tooltip(
                message: widget.label,
                waitDuration: const Duration(milliseconds: 400),
                child: tile,
              )
            : tile,
      ),
    );
  }
}

/// Uppercase group label ("YOUR SPACE"). Collapses to a hairline rule
/// instead of vanishing, so the grouping is still legible in the icon rail.
class SidebarSectionHeader extends StatelessWidget {
  const SidebarSectionHeader({super.key, required this.label, this.collapsed = false});

  final String label;
  final bool collapsed;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    if (collapsed) {
      return Padding(
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
        child: Divider(height: 1, color: aurora.glassBorder),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.md, AppSpacing.lg, AppSpacing.sm),
      child: Text(label, style: AppTypography.overline.copyWith(color: aurora.textTertiary)),
    );
  }
}

/// Collapse toggle in the sidebar header. Local on purpose — a general
/// icon button belongs in widgets/, this one only serves the rail.
class SidebarIconButton extends StatefulWidget {
  const SidebarIconButton({super.key, required this.icon, required this.onTap, this.tooltip});

  final IconData icon;
  final VoidCallback onTap;
  final String? tooltip;

  @override
  State<SidebarIconButton> createState() => _SidebarIconButtonState();
}

class _SidebarIconButtonState extends State<SidebarIconButton> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    final button = AnimatedContainer(
      duration: const Duration(milliseconds: 140),
      width: 30,
      height: 30,
      decoration: BoxDecoration(
        color: _hovered ? Colors.white.withOpacity(0.09) : Colors.transparent,
        shape: BoxShape.circle,
      ),
      child: Icon(
        widget.icon,
        size: 17,
        color: _hovered ? aurora.textPrimary : aurora.textTertiary,
      ),
    );

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: widget.tooltip == null ? button : Tooltip(message: widget.tooltip!, child: button),
      ),
    );
  }
}
