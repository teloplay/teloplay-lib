import 'package:flutter/material.dart';

import '../../core/platform/platform_info.dart';
import 'desktop_shell.dart';
import 'mobile_shell.dart';

/// Window wider than this gets the Windows shell. Narrow (phone browser
/// or Android) gets the mobile shell. Same widgets, no web-only UI.
const double kDesktopShellMinWidth = 900;

/// ⚠️ Phase 6 — Shared design system, platform-adaptive layout।
///
/// এই widget-ই একমাত্র জায়গা যেখানে "কোন platform-এ কোন shell"
/// সিদ্ধান্ত নেওয়া হয়। Theme/color/animation/branding — এসব কোনোটাই
/// এখানে ভিন্ন হয় না (MaterialApp-এর `theme` সবসময় common
/// `AppTheme.themeFor(themeMode)`) — শুধু নিচের content কীভাবে সাজানো
/// হবে (navigation shape, panel count, density) সেটাই platform-ভেদে
/// আলাদা।
///
/// [mobileChild]/[desktopChild] rebuild এড়াতে caller নিজে
/// `const`/cached widget instance পাঠাতে পারে — এই wrapper নিজে কোনো
/// state রাখে না, শুধু platform অনুযায়ী একটা বেছে নেয় (rebuild-heavy
/// না, `Platform.isWindows` static/cheap check)।
///
/// Web (future Phase 7+ PWA) আপাতত desktop layout-এর দিকে fallback
/// করে — dedicated web shell তখনই আলাদা করা হবে যখন actual web target
/// scope-এ আসবে (এখন সেটা নিয়ে আগাম জটিলতা বাড়ানো ঠিক হবে না)।
class PlatformShell extends StatelessWidget {
  const PlatformShell({
    super.key,
    required this.mobileChild,
    required this.desktopChild,
  });

  final Widget mobileChild;
  final Widget desktopChild;

  /// Native OS only. Web is neither; it decides from window width.
  static bool get isDesktopPlatform =>
      PlatformInfo.isWindows || PlatformInfo.isLinux || PlatformInfo.isMacOS;

  static bool isDesktopLayout(double width) {
    if (PlatformInfo.isAndroid) return false;
    if (isDesktopPlatform) return true;
    return width >= kDesktopShellMinWidth;
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth.isFinite
            ? constraints.maxWidth
            : MediaQuery.sizeOf(context).width;
        return isDesktopLayout(width) ? desktopChild : mobileChild;
      },
    );
  }
}