/// TeloPlay 8px grid — the single source of truth for spacing.
///
/// Why this exists: before this file every screen hardcoded its own
/// paddings (16/20/22/24 mixed in the same viewport), which reads as
/// "unpolished" far more than any color choice does. Rhythm is the
/// cheapest premium signal there is — one scale, used everywhere.
///
/// Usage:
/// ```dart
/// Padding(padding: EdgeInsets.all(AppSpacing.md), ...)
/// const SizedBox(height: AppSpacing.lg)
/// ```
class AppSpacing {
  AppSpacing._();

  /// 4 — hairline gaps (icon↔label, badge insets).
  static const double xs = 4;

  /// 8 — base unit. Tight inner gaps.
  static const double sm = 8;

  /// 16 — card padding, screen edge padding on mobile.
  static const double md = 16;

  /// 24 — section gap, screen edge padding on desktop.
  static const double lg = 24;

  /// 32 — between major page blocks.
  static const double xl = 32;

  /// 48 — hero/empty-state breathing room.
  static const double xxl = 48;

  // ── Layout constants (named so breakpoints aren't magic numbers) ──

  /// Minimum touch target — every tappable row/button must clear this.
  static const double minTouchTarget = 48;

  /// Standard list row height.
  static const double listRowHeight = 56;

  /// Mini-player dock height (both platforms — one dock, one height).
  static const double miniPlayerHeight = 72;

  /// Bottom nav bar height (excluding safe-area inset).
  static const double bottomNavHeight = 68;

  /// Collapsed/expanded sidebar widths.
  static const double sidebarCollapsedWidth = 76;
  static const double sidebarExpandedWidth = 248;

  /// Standard radius scale. Never go below 4 (design-system rule).
  static const double radiusSm = 8;
  static const double radiusMd = 12;
  static const double radiusLg = 16;
  static const double radiusXl = 24;
  static const double radiusPill = 999;
}
