import 'package:flutter/material.dart';

import '../core/theme/app_theme_extension.dart';

/// Elevation levels for the TeloPlay design system.
enum ElevationLevel {
  background,   // 0 - Root scaffold
  surface,      // 1 - Content areas
  raised,       // 2 - Cards, panels
  elevated,     // 3 - Hover/active/modal
  modal,        // 3 - Bottom sheets, dialogs
  overlay,      // 4 - Now Playing, toasts
}

/// Card widget with strict elevation system compliance.
class ElevatedCard extends StatelessWidget {
  final Widget child;
  final ElevationLevel elevation;
  final EdgeInsetsGeometry? padding;
  final BorderRadius? borderRadius;
  final VoidCallback? onTap;
  final bool isClickable;

  const ElevatedCard({
    super.key,
    required this.child,
    this.elevation = ElevationLevel.raised,
    this.padding,
    this.borderRadius,
    this.onTap,
    this.isClickable = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = context.aurora;
    final effectiveRadius = borderRadius ?? BorderRadius.circular(12);

    final bgColor = switch (elevation) {
      ElevationLevel.background => theme.background,
      ElevationLevel.surface => theme.surface,
      ElevationLevel.raised => theme.surfaceRaised,
      ElevationLevel.elevated => theme.surfaceElevated,
      ElevationLevel.modal => theme.surfaceElevated,
      ElevationLevel.overlay => theme.surfaceElevated,
    };

    final border = switch (elevation) {
      ElevationLevel.background => null,
      ElevationLevel.surface => Border.all(
          color: Colors.white.withOpacity(0.05),
        ),
      ElevationLevel.raised => Border.all(
          color: Colors.white.withOpacity(0.08),
        ),
      ElevationLevel.elevated => Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ElevationLevel.modal => Border.all(
          color: Colors.white.withOpacity(0.10),
        ),
      ElevationLevel.overlay => Border.all(
          color: Colors.white.withOpacity(0.12),
        ),
    };

    final shadow = switch (elevation) {
      ElevationLevel.background => <BoxShadow>[],
      ElevationLevel.surface => <BoxShadow>[],
      ElevationLevel.raised => [
          BoxShadow(
            color: Colors.black.withOpacity(0.2),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ElevationLevel.elevated => [
          BoxShadow(
            color: Colors.black.withOpacity(0.3),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ElevationLevel.modal => [
          BoxShadow(
            color: Colors.black.withOpacity(0.4),
            blurRadius: 16,
            offset: const Offset(0, 6),
          ),
        ],
      ElevationLevel.overlay => [
          BoxShadow(
            color: Colors.black.withOpacity(0.5),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
    };

    Widget card = Container(
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: effectiveRadius,
        border: border,
        boxShadow: shadow,
      ),
      child: ClipRRect(
        borderRadius: effectiveRadius,
        child: Padding(
          padding: padding ?? const EdgeInsets.all(16),
          child: child,
        ),
      ),
    );

    if (isClickable || onTap != null) {
      card = InkWell(
        onTap: onTap,
        borderRadius: effectiveRadius,
        child: AnimatedScale(
          scale: 1.0,
          duration: const Duration(milliseconds: 150),
          child: card,
        ),
      );
    }

    return card;
  }
}