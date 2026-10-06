/// Single platform-detection abstraction for the whole app (P0-G1).
///
/// WHY: `import 'dart:io'` fails web compilation at import time, so no
/// feature file may import it directly. This file re-exports the correct
/// implementation per platform via conditional export — callers use
/// `PlatformInfo.isWindows` etc. and never touch `dart:io` themselves.
///
/// Web behavior is preserved by keeping existing `kIsWeb` branches at call
/// sites; the web implementation below returns conservative `false`/0
/// values that those branches already expect.
export 'platform_info_io.dart' if (dart.library.html) 'platform_info_web.dart';
