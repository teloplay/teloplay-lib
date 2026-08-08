import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;

import 'package:flutter/material.dart';

import 'desktop_shell.dart';
import 'mobile_shell.dart';

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

  static bool get isDesktopPlatform {
    if (kIsWeb) return true; // future web shell না আসা পর্যন্ত desktop-স্টাইল fallback
    return Platform.isWindows || Platform.isLinux || Platform.isMacOS;
  }

  @override
  Widget build(BuildContext context) {
    return isDesktopPlatform ? desktopChild : mobileChild;
  }
}