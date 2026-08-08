import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../../core/logging/app_logger.dart';
import '../../data/drift/database.dart';

/// ⚠️ Phase 1 (Shuffle/Repeat/Speed/Sleep Timer) — সাধারণ key-value
/// settings repository, `SettingsEntries` টেবিলের উপরে পাতলা wrapper।
///
/// এটা এখনই শুধু কয়েকটা playback-preference key-এর জন্য ব্যবহার হচ্ছে,
/// কিন্তু generic থাকায় ভবিষ্যতে theme/language/quality ইত্যাদি অন্য
/// settings-ও একই টেবিল/repository দিয়ে চলবে — নতুন column/migration
/// লাগবে না।
class SettingsRepository {
  final AppDatabase _db;

  SettingsRepository(this._db);

  String get _userId {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      // Guest mode-ও Anonymous Auth ব্যবহার করে, তাই এখানে null হওয়ার
      // কথা না — হলে সেটা প্রকৃত bug (auth bootstrap মিস হয়েছে)।
      throw StateError(
        'SettingsRepository: currentUser null — Guest/Anonymous auth '
        'বুটস্ট্র্যাপ না হয়েই settings access করার চেষ্টা হয়েছে',
      );
    }
    return user.id;
  }

  Future<String?> getValue(String key) async {
    try {
      final row = await (_db.select(_db.settingsEntries)
            ..where((t) => t.userId.equals(_userId) & t.key.equals(key)))
          .getSingleOrNull();
      return row?.value;
    } catch (e) {
      AppLogger.error('SettingsRepository.getValue failed (key=$key)', e);
      return null;
    }
  }

  Future<void> setValue(String key, String value) async {
    try {
      await _db.into(_db.settingsEntries).insertOnConflictUpdate(
            SettingsEntriesCompanion.insert(
              userId: _userId,
              key: key,
              value: value,
              updatedAt: Value(DateTime.now()),
            ),
          );
    } catch (e) {
      AppLogger.error('SettingsRepository.setValue failed (key=$key)', e);
    }
  }

  /// একসাথে একাধিক key পড়া — app-startup-এ একবারে সব playback-preference
  /// load করার জন্য, প্রতিটার জন্য আলাদা query না চালিয়ে।
  Future<Map<String, String>> getValues(List<String> keys) async {
    if (keys.isEmpty) return {};
    try {
      final rows = await (_db.select(_db.settingsEntries)
            ..where((t) => t.userId.equals(_userId) & t.key.isIn(keys)))
          .get();
      return {for (final r in rows) r.key: r.value};
    } catch (e) {
      AppLogger.error('SettingsRepository.getValues failed', e);
      return {};
    }
  }
}