/// Web backing for [PlatformInfo]. `dart:io` does not exist on web, so every
/// getter returns a conservative constant. Call sites keep their `kIsWeb`
/// branches, which take precedence — these values only matter where a
/// `Platform.is*` check previously ran unguarded (none remain after P0-G1).
class PlatformInfo {
  PlatformInfo._();

  static bool get isWindows => false;
  static bool get isAndroid => false;
  static bool get isLinux => false;
  static bool get isMacOS => false;

  static bool get isDesktop => false;

  /// No RSS API on web; callers early-return on `kIsWeb` before reading this.
  static int get currentRssBytes => 0;
}
