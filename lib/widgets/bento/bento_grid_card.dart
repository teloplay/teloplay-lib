import 'package:flutter/material.dart';

import '../../core/theme/app_theme_extension.dart';

/// Phase 6.5 UI-Batch 4 — Library bento-grid-এর একক card। Dynamic
/// curated-accent color + subtle gradient + icon — কোনো নতুন backend
/// logic নেই, শুধু presentation primitive। Library-এর ৬টা section
/// (Favorites/Playlists/Recently Played/Most Played/Offline/Cached)
/// সবাই এই একই card ব্যবহার করবে, শুধু icon/color/label/onTap আলাদা।
class BentoGridCard extends StatefulWidget {
  const BentoGridCard({
    required this.icon,
    required this.label,
    required this.accentColor,
    required this.onTap,
    this.subtitle,
    super.key,
  });

  final IconData icon;
  final String label;
  final String? subtitle;
  final Color accentColor;
  final VoidCallback onTap;

  @override
  State<BentoGridCard> createState() => _BentoGridCardState();
}

class _BentoGridCardState extends State<BentoGridCard> {
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    return GestureDetector(
      onTapDown: (_) => setState(() => _pressed = true),
      onTapCancel: () => setState(() => _pressed = false),
      onTapUp: (_) => setState(() => _pressed = false),
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _pressed ? 0.96 : 1.0,
        duration: const Duration(milliseconds: 120),
        child: Container(
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(18),
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                widget.accentColor.withOpacity(0.22),
                aurora.surfaceElevated,
              ],
            ),
            border: Border.all(color: Colors.white.withOpacity(0.06)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: widget.accentColor.withOpacity(0.9),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(widget.icon, color: Colors.white, size: 19),
              ),
              const SizedBox(height: 10),
              Text(
                widget.label,
                style: TextStyle(color: aurora.textPrimary, fontSize: 13.5, fontWeight: FontWeight.w700),
              ),
              if (widget.subtitle != null) ...[
                const SizedBox(height: 1),
                Text(
                  widget.subtitle!,
                  style: TextStyle(color: aurora.textSecondary, fontSize: 11),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}