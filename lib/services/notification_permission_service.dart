// lib/services/notification_permission_service.dart
//
// Android 13 (API 33)+ এ notification দেখানোর জন্য শুধু
// AndroidManifest.xml-এ POST_NOTIFICATIONS ঘোষণা যথেষ্ট না — runtime-এ
// ব্যবহারকারীর explicit অনুমতি লাগে (camera/location permission-এর
// মতোই)। এই permission ছাড়া audio_service-এর background playback
// notification (lock screen controls সহ) Android 13+ ডিভাইসে না-ও
// দেখাতে পারে।
//
// Android 12 এবং তার নিচে এই permission-এর প্রয়োজনই নেই — সেক্ষেত্রে
// permission_handler নিজে থেকেই granted হিসেবে ধরে নেয় (no-op)।
// Windows/অন্য প্ল্যাটফর্মে এই permission concept-ই প্রযোজ্য না, তাই
// early-return করা হয়েছে।

import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:permission_handler/permission_handler.dart';

import '../core/logging/app_logger.dart';

class NotificationPermissionService {
  NotificationPermissionService._();

  /// অ্যাপ শুরুতে (Welcome screen-এ) একবার কল করা হবে।
  ///
  /// ব্যবহারকারী permission deny করলেও এই মেথড silently সেটা মেনে
  /// নেয় — app এর কোনো ফিচার ব্লক হবে না, শুধু background notification
  /// না-ও দেখা যেতে পারে। জোর করে বারবার চাওয়া হয় না (এটা bad UX)।
  static Future<void> requestIfNeeded() async {
    if (kIsWeb || !Platform.isAndroid) return;

    try {
      final status = await Permission.notification.status;

      // ইতিমধ্যে granted বা permanently denied হলে আর কিছু করার নেই —
      // permanently denied অবস্থায় আবার request করলে system dialog না
      // দেখিয়ে সরাসরি denied ফেরত দেয়, তাই সেটা এড়ানো হচ্ছে।
      if (status.isGranted || status.isPermanentlyDenied) {
        AppLogger.playback(
          'Notification permission ইতিমধ্যে resolved: $status',
        );
        return;
      }

      final result = await Permission.notification.request();
      AppLogger.playback('Notification permission request ফলাফল: $result');
    } catch (e, st) {
      // permission_handler নিজে থেকে fail করলেও (যেমন খুব পুরনো Android
      // বা কোনো plugin registration সমস্যা) অ্যাপ চলবে স্বাভাবিকভাবে —
      // শুধু notification নাও দেখা যেতে পারে।
      AppLogger.error('Notification permission request failed', e, st);
    }
  }
}