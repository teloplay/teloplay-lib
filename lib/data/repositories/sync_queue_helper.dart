import 'dart:convert';
import 'package:drift/drift.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../drift/database.dart';

/// প্রতিটা repository write operation-এর পর এই helper দিয়ে
/// sync_queue_items টেবিলে একটা entry যোগ করবে (offline-first pattern)।
///
/// Phase 4-এ real sync logic implement হওয়ার আগ পর্যন্ত এই queue শুধু
/// জমা হতে থাকবে — কিন্তু structure এখনই ঠিক রাখা দরকার, যাতে পরে
/// migration লিখতে না হয়।
///
/// ⚠️ v11 Fix-First #2 — SyncQueueItems.userId non-nullable। No
/// authenticated user (এমনকি guest/anonymous auth-ও) থাকলে entry তৈরি
/// হবে না — owner-less sync queue entry নিজেই cross-user leak risk।
class SyncQueueHelper {
  final AppDatabase db;

  SyncQueueHelper(this.db);

  Future<void> enqueue({
    required String entityType,
    required String entityId,
    required String action, // 'create' | 'update' | 'delete'
    required Map<String, dynamic> payload,
  }) async {
    final userId = Supabase.instance.client.auth.currentUser?.id;
    if (userId == null) {
      // Guest/anonymous auth-ও একটা currentUser id দেয় (app-এর convention,
      // দেখো cache_repository.dart/library_repository.dart)। null মানে
      // সত্যিই কোনো session নেই — এই অবস্থায় sync queue entry তৈরি করা
      // অর্থহীন (sync হওয়ার সময় কোনো user context থাকবে না)।
      return;
    }

    await db.into(db.syncQueueItems).insert(
          SyncQueueItemsCompanion.insert(
            id: _generateId(),
            userId: userId,
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