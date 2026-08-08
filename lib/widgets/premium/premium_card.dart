import 'package:flutter/material.dart';

import '../../core/theme/app_theme_extension.dart';

/// Phase 6.5 Premium Design System — the Home/Discovery card primitive.
///
/// Design audit finding: `GlassContainer` (blur + tint) was being used
/// everywhere, including Home/rails, which the roadmap itself flags as
/// wrong ("Home/Discovery — Avoid heavy glass, use Elevated Cards, Soft
/// Gradient, Subtle Shadow, Layered Depth"). This widget is that
/// alternative: a solid `surfaceRaised`/`surfaceElevated` background,
/// a neutral (colorless) elevation shadow so cards visually "float"
/// without needing an accent glow, and an optional hover/press scale
/// micro-interaction for desktop pointer input.
///
/// `GlassContainer` remains reserved for Player-context screens only
/// (full player card, mini-player, NowPlayingScreen) — this widget is
/// everything else: rail cards, hero cards, sidebar section cards,
/// context-panel tabs, etc.
class PremiumCard extends StatefulWidget {
  const PremiumCard({
    super.key,
    required this.child,
    this.onTap,
    this.borderRadius = const BorderRadius.all(Radius.circular(20)),
    this.padding,
    this.margin,
    this.width,
    this.height,
    this.elevated = false,
    this.gradient,
    this.enableHoverScale = true,
  });

  final Widget child;
  final VoidCallback? onTap;
  final BorderRadius borderRadius;
  final EdgeInsetsGeometry? padding;
  final EdgeInsetsGeometry? margin;
  final double? width;
  final double? height;

  /// Use `surfaceElevated` instead of `surfaceRaised` as the base fill
  /// — for cards that should read as "one level up" (e.g. an active/
  /// selected state, or a card nested inside another card).
  final bool elevated;

  /// Optional gradient background (e.g. hero cards use image + scrim,
  /// but smaller "Daily Mix"-style cards use a flat brand/curated
  /// gradient instead of a photo). Overrides the solid surface color
  /// when provided.
  final Gradient? gradient;

  /// Desktop hover / all-platform press feedback — subtle scale-up,
  /// matches the "premium hover states" requirement for rail cards and
  /// the desktop sidebar/context-panel tabs.
  final bool enableHoverScale;

  @override
  State<PremiumCard> createState() => _PremiumCardState();
}

class _PremiumCardState extends State<PremiumCard> {
  bool _hovered = false;
  bool _pressed = false;

  @override
  Widget build(BuildContext context) {
    final aurora = context.aurora;

    final scale = !widget.enableHoverScale
        ? 1.0
        : _pressed
            ? 0.98
            : _hovered
                ? 1.02
                : 1.0;

    Widget content = AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      width: widget.width,
      height: widget.height,
      padding: widget.padding,
      decoration: BoxDecoration(
        color: widget.gradient == null
            ? (widget.elevated ? aurora.surfaceElevated : aurora.surfaceRaised)
            : null,
        gradient: widget.gradient,
        borderRadius: widget.borderRadius,
        boxShadow: [
          BoxShadow(
            color: aurora.shadowColor.withOpacity(_hovered ? 0.32 : 0.22),
            blurRadius: _hovered ? 24 : 16,
            offset: const Offset(0, 8),
            spreadRadius: -4,
          ),
        ],
        border: Border.all(
          color: Colors.white.withOpacity(_hovered ? 0.08 : 0.04),
          width: 1,
        ),
      ),
      child: ClipRRect(
        borderRadius: widget.borderRadius,
        child: widget.child,
      ),
    );

    content = AnimatedScale(
      scale: scale,
      duration: const Duration(milliseconds: 150),
      curve: Curves.easeOut,
      child: content,
    );

    if (widget.margin != null) {
      content = Padding(padding: widget.margin!, child: content);
    }

    if (widget.onTap == null) return content;

    return MouseRegion(
      onEnter: (_) => setState(() => _hovered = true),
      onExit: (_) => setState(() => _hovered = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        onTap: widget.onTap,
        onTapDown: (_) => setState(() => _pressed = true),
        onTapUp: (_) => setState(() => _pressed = false),
        onTapCancel: () => setState(() => _pressed = false),
        child: content,
      ),
    );
  }
}