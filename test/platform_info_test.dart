import 'dart:io' show Platform;

import 'package:flutter_test/flutter_test.dart';
import 'package:teloplay/core/platform/platform_info.dart';

/// P0-G1: the abstraction must resolve identically to `dart:io` on VM
/// test platforms (Linux/Windows/macOS CI). Web resolution (all-false)
/// is covered by construction via conditional export.
void main() {
  group('PlatformInfo', () {
    test('matches dart:io on this platform', () {
      expect(PlatformInfo.isWindows, Platform.isWindows);
      expect(PlatformInfo.isAndroid, Platform.isAndroid);
      expect(PlatformInfo.isLinux, Platform.isLinux);
      expect(PlatformInfo.isMacOS, Platform.isMacOS);
    });

    test('isDesktop is the OR of desktop OS flags', () {
      expect(
        PlatformInfo.isDesktop,
        PlatformInfo.isWindows ||
            PlatformInfo.isLinux ||
            PlatformInfo.isMacOS,
      );
    });

    test('currentRssBytes is non-negative', () {
      expect(PlatformInfo.currentRssBytes, greaterThanOrEqualTo(0));
    });
  });
}
