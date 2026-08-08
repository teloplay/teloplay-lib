import 'dart:convert';
import 'package:drift/drift.dart';
import '../drift/database.dart';

/// প্রতিটা repository write operation-এর পর এই helper দিয়ে
/// sync_queue_items টেবিলে একটা entry যোগ করবে (offline-first pattern)।
///
/// Phase 4-এ real sync logic implement হওয়ার আগ পর্যন্ত এই queue শুধু
/// জমা হতে থাকবে — কিন্তু structure এখনই ঠিক রাখা দরকার, যাতে পরে
/// migration লিখতে না হয়।
class SyncQueueHelper {
  final AppDatabase db;

  SyncQueueHelper(this.db);

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String action, // 'create' | 'update' | 'delete'
    required Map<String, dynamic> payload,
  }) async {
    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: _generateId(),
            entityType: entityType,
            entityId: entityId,
            action: action,
            payload: jsonEncode(payload),
          ),
        );
  }

  String _generateId() {
    // Phase 0-এ simple timestamp-based ID — পরে চাইলে uuid প্যাকেজে যাওয়া যাবে
    return DateTime.now().microsecondsSinceEpoch.toString();
  }
}