import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme_extension.dart';
import '../../../widgets/onboarding/checklist_badge.dart';

/// Phase 6.5 UI-Batch 3a (v2 — compact) — single-row premium header.
///
/// Reduced from the earlier ~220px multi-row version to a single
/// ~80px row per developer feedback: the header was pushing real
/// music content too far down. Mood badge and larger backdrop tint
/// dropped — Hero card now owns the "feels premium" visual weight,
/// this header's only job is a quick greeting + fast navigation.
class SmartWelcomeHeader extends StatelessWidget {
  const SmartWelcomeHeader({super.key});

  String get _greeting {
    final hour = DateTime.now().hour;
    if (hour < 5) return 'Still Up?';
    if (hour < 12) return 'Good Morning';
    if (hour < 17) return 'Good Afternoon';
    if (hour < 21) return 'Good Evening';
    return 'Good Night';
  }

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 18, 24, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                ShaderMask(
                  shaderCallback: (bounds) => aurora.accentGradient.createShader(bounds),
                  child: Text(
                    _greeting,
                    style: const TextStyle(color: Colors.white, fontSize: 21, fontWeight: FontWeight.w800, letterSpacing: -0.3),
                  ),
                ),
                const SizedBox(height: 2),
                Text('Continue your music journey', style: TextStyle(color: aurora.textSecondary, fontSize: 12.5)),
              ],
            ),
          ),
          const SizedBox(width: 12),
          // ⚠️ v11 Onboarding (roadmap Section 13/Phase 0 item #13) —
          // renders nothing once dismissed or all 5 items complete.
          const ChecklistBadge(),
          const SizedBox(width: 8),
          const _QuickPillRow(),
        ],
      ),
    );
  }
}

class _QuickPillRow extends StatelessWidget {
  const _QuickPillRow();

  static const _items = [
    (icon: Icons.favorite_rounded, route: '/library/favorites', tooltip: 'Favorites'),
    (icon: Icons.history_rounded, route: '/library/recent', tooltip: 'Recently Played'),
    (icon: Icons.offline_pin_rounded, route: '/library/offline', tooltip: 'Offline'),
  ];

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: _items
          .map((item) => Padding(
                padding: const EdgeInsets.only(left: 8),
                child: _QuickPill(icon: item.icon, route: item.route, tooltip: item.tooltip),
              ))
          .toList(),
    );
  }
}

class _QuickPill extends StatefulWidget {
  const _QuickPill({required this.icon, required this.route, required this.tooltip});
  final IconData icon;
  final String route;
  final String tooltip;

  @override
  State<_QuickPill> createState() => _QuickPillState();
}

class _QuickPillState extends State<_QuickPill> {
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
          onTap: () => context.push(widget.route),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 38,
            height: 38,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              gradient: _hovered ? aurora.accentGradient : null,
              color: _hovered ? null : aurora.surfaceRaised,
              border: Border.all(color: _hovered ? Colors.transparent : aurora.glassBorder),
            ),
            child: Icon(widget.icon, size: 16, color: _hovered ? Colors.white : aurora.textSecondary),
          ),
        ),
      ),
    );
  }
}