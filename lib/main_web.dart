import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'main_common.dart';

/// Web uses the same app as Android and Windows. Window width picks
/// MobileShell or DesktopShell. No native audio plugins here.
void main() async {
  await bootstrapCommon();
  runApp(
    const ProviderScope(
      child: TeloPlayApp(),
    ),
  );
}




