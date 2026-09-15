import 'dart:io' show Platform;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme_extension.dart';

bool get _isDesktop => Platform.isWindows || Platform.isLinux || Platform.isMacOS;

class QuickAccessSection extends StatelessWidget {
  const QuickAccessSection({super.key});

  static const _items = [
    (icon: Icons.favorite_rounded, label: 'Favorites', route: '/library/favorites', color: Color(0xFFEC4899)),
    (icon: Icons.playlist_play_rounded, label: 'Playlists', route: '/library/playlists', color: Color(0xFF8B5CF6)),
    (icon: Icons.history_rounded, label: 'Recently Played', route: '/library/recent', color: Color(0xFF3B82F6)),
    (icon: Icons.local_fire_department_rounded, label: 'Most Played', route: '/library/most', color: Color(0xFFF59E0B)),
    (icon: Icons.download_done_rounded, label: 'Downloaded', route: '/library/offline/downloaded', color: Color(0xFF10B981)),
    (icon: Icons.cloud_done_rounded, label: 'Cached Songs', route: '/library/offline/cached', color: Color(0xFF6366F1)),
  ];

  @override
  Widget build(BuildContext context) {
    final columns = _isDesktop ? 3 : 2;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
      child: LayoutBuilder(
        builder: (context, constraints) {
          final itemWidth = (constraints.maxWidth - ((columns - 1) * 12)) / columns;
          return Wrap(
            spacing: 12,
            runSpacing: 10,
            children: _items.map((item) {
              return SizedBox(
                width: itemWidth,
                child: _QuickAccessCard(
                  icon: item.icon,
                  label: item.label,
                  accentColor: item.color,
                  onTap: () => context.push(item.route),
                ),
              );
            }).toList(),
          );
        },
      ),
    );
  }
}

class _QuickAccessCard extends StatefulWidget {
  final IconData icon;
  final String label;
  final Color accentColor;
  final VoidCallback onTap;

  const _QuickAccessCard({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
  });

  @override
  State<_QuickAccessCard> createState() => _QuickAccessCardState();
}

class _QuickAccessCardState extends State<_QuickAccessCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: _hovered ? aurora.surfaceElevated : aurora.surfaceRaised,
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: _hovered ? widget.accentColor.withOpacity(0.4) : aurora.glassBorder,
              width: 1,
            ),
            boxShadow: _hovered
                ? [
                    BoxShadow(
                      color: widget.accentColor.withOpacity(0.2),
                      blurRadius: 12,
                      offset: const Offset(0, 4),
                    )
                  ]
                : null,
          ),
          child: Row(
            children: [
              Container(
                width: 32,
                height: 32,
                decoration: BoxDecoration(
                  color: widget.accentColor.withOpacity(0.15),
                  shape: BoxShape.circle,
                ),
                child: Icon(widget.icon, size: 18, color: widget.accentColor),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: aurora.textPrimary,
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
