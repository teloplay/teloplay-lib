/// Native (`dart:io`) backing for [PlatformInfo]. Never imported directly —
/// always go through `platform_info.dart` so web builds never see `dart:io`.
import 'dart:io' show Platform, ProcessInfo;

/// Mirrors the exact `Platform.is*` semantics call sites used before P0-G1.
class PlatformInfo {
  PlatformInfo._();

  static bool get isWindows => Platform.isWindows;
  static bool get isAndroid => Platform.isAndroid;
  static bool get isLinux => Platform.isLinux;
  static bool get isMacOS => Platform.isMacOS;

  /// Desktop = Windows/Linux/macOS. Web callers keep their own `kIsWeb`
  /// branches (web intentionally reports false here).
  static bool get isDesktop => isWindows || isLinux || isMacOS;

  /// Resident set size in bytes (was `ProcessInfo.currentRss`).
  static int get currentRssBytes => ProcessInfo.currentRss;
}
