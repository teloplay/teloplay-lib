// lib/core/window/window_tray_manager.dart
//
// Windows-এ close(X) বাটন চাপলে অ্যাপ exit না হয়ে system tray-তে
// minimize হয়ে যায় (Spotify/Discord-style)। Tray icon-এ ডাবল-ক্লিক
// করলে window আবার restore হয়। Tray-তে right-click মেনুতে
// "Open TeloPlay" এবং "Exit" অপশন থাকবে — Exit করলেই শুধু প্রকৃত
// process বন্ধ হবে।
//
// ব্যবহার: main_windows.dart-এ bootstrapCommon()-এর পরে,
// runApp()-এর আগে/পরে যেকোনো জায়গায়:
//   await WindowTrayManager.instance.initialize();
//
// নির্ভরতা: system_tray, window_manager (দুটোই আগে থেকেই
// pubspec.yaml-এ আছে)।

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:system_tray/system_tray.dart';
import 'package:window_manager/window_manager.dart';

import '../logging/app_logger.dart';

class WindowTrayManager with WindowListener {
  WindowTrayManager._();
  static final WindowTrayManager instance = WindowTrayManager._();

  final SystemTray _systemTray = SystemTray();
  bool _initialized = false;

  /// window_manager + system_tray দুটোই init করে এবং close(X) বাটনের
  /// ডিফল্ট আচরণ override করে (exit না করে minimize-to-tray করার জন্য)।
  Future<void> initialize() async {
    if (_initialized || !Platform.isWindows) return;

    await windowManager.ensureInitialized();

    // ডিফল্ট close আচরণ বন্ধ — এখন থেকে onWindowClose() আমরাই হ্যান্ডেল করব
    await windowManager.setPreventClose(true);
    windowManager.addListener(this);

    // ⚠️ Fix — hidden রাখা হচ্ছে (normal না) কারণ DesktopTopBar একটা
    // পূর্ণাঙ্গ কাস্টম title bar (drag-move + min/max/close সহ)।
    // normal রাখলে Windows-এর নিজের native title bar-এর *উপরে* এই
    // কাস্টম bar আবার বসত (ডাবল title bar, screenshot-এ যা দেখা
    // যাচ্ছিল)। hidden style-এও window_manager নিজে থেকেই edge-drag
    // resize handle করে (এটাই এই প্যাকেজের ডকুমেন্টেড আচরণ) — আগে
    // resize কাজ করছিল না মূলত এই init দ্বিতীয়বার (main_windows.dart-এর
    // পুরনো নিজস্ব init-এর সাথে) race করছিল বলে, style-এর কারণে না।
    const windowOptions = WindowOptions(
      size: Size(1280, 800),
      minimumSize: Size(800, 600),
      center: true,
      backgroundColor: Colors.transparent,
      skipTaskbar: false,
      titleBarStyle: TitleBarStyle.hidden,
    );
    await windowManager.waitUntilReadyToShow(windowOptions, () async {
      await windowManager.show();
      await windowManager.focus();
    });

    await _initializeTray();

    _initialized = true;
    AppLogger.playback('WindowTrayManager initialized (close→tray active)');
  }

  Future<void> _initializeTray() async {
    // ⚠️ Fix — আগে 'assets/app_icon.ico' (Flutter asset-bundle relative
    // path) দেওয়া হতো, যেটা system_tray package silently ignore করত —
    // এটা native Win32 API দিয়ে icon load করে, Flutter asset bundle
    // পড়তে পারে না, তাই কোনো exception না দিয়েই tray icon না দেখিয়ে
    // চুপচাপ ব্যর্থ হতো (X→hide ঠিকই কাজ করত, শুধু visible tray icon
    // ছিল না)।
    //
    // Fix: real filesystem absolute path বানানো হচ্ছে —
    // Platform.resolvedExecutable (exe-এর অবস্থান) থেকে data/
    // flutter_assets/assets/app_icon.ico-তে resolve করে, যেটা
    // `flutter build windows`/`flutter run`-এর পর bundled Flutter
    // asset আসলে ঠিক যেখানে থাকে (both debug ও release build-এ একই
    // relative layout — Runner.exe-এর পাশে data/flutter_assets/)।
    final exeDir = p.dirname(Platform.resolvedExecutable);
    final iconPath = p.join(exeDir, 'data', 'flutter_assets', 'assets', 'app_icon.ico');

    if (!File(iconPath).existsSync()) {
      AppLogger.error(
        'SystemTray icon not found at resolved path: $iconPath',
        null,
      );
      return; // tray icon ছাড়াই বাকি অ্যাপ চলবে, crash না
    }

    try {
      await _systemTray.initSystemTray(
        title: 'TeloPlay',
        iconPath: iconPath,
      );

      final menu = Menu();
      await menu.buildFrom([
        MenuItemLabel(
          label: 'TeloPlay Open',
          onClicked: (_) => _showWindow(),
        ),
        MenuSeparator(),
        MenuItemLabel(
          label: 'Exit',
          onClicked: (_) => _exitApp(),
        ),
      ]);
      await _systemTray.setContextMenu(menu);

      // ডাবল-ক্লিক বা সিঙ্গল-ক্লিক — দুটোতেই window restore করা,
      // যাতে ব্যবহারকারীর জন্য সবচেয়ে স্বাভাবিক অভিজ্ঞতা হয়
      _systemTray.registerSystemTrayEventHandler((eventName) {
        if (eventName == kSystemTrayEventClick ||
            eventName == kSystemTrayEventDoubleClick) {
          _showWindow();
        } else if (eventName == kSystemTrayEventRightClick) {
          _systemTray.popUpContextMenu();
        }
      });
    } catch (e, st) {
      // tray init fail করলেও অ্যাপ যেন crash না করে —
      // worst case-এ close বাটন normal exit-এর মতো কাজ করবে
      AppLogger.error('SystemTray init failed', e, st);
    }
  }

  Future<void> _showWindow() async {
    await windowManager.show();
    await windowManager.focus();
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
  }

  Future<void> _exitApp() async {
    windowManager.removeListener(this);
    await _systemTray.destroy();
    await windowManager.setPreventClose(false);
    await windowManager.close();
    exit(0);
  }

  @override
  void onWindowClose() async {
    // close(X) বাটন চাপলে এখানে আসে (setPreventClose(true) থাকার কারণে
    // ডিফল্ট exit আচরণ বাতিল হয়ে গেছে) — window শুধু hide করা হচ্ছে,
    // exit না। taskbar থেকেও তাই সরে যাবে (Spotify-style), শুধু tray
    // icon-এই থেকে যাবে।
    await windowManager.hide();
  }
}