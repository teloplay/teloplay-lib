import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../data/drift/database.dart';

/// AppDatabase-এর singleton instance।
/// পুরো app-এ এই provider দিয়েই database access হবে —
/// কোথাও সরাসরি `AppDatabase()` কল করা হবে না।
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  final db = AppDatabase();

  // App বন্ধ হলে বা provider dispose হলে database connection বন্ধ করে দেওয়া
  ref.onDispose(() {
    db.close();
  });

  return db;
});