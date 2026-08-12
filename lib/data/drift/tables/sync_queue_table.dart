import 'package:drift/drift.dart';

/// Offline-first sync pattern-এর জন্য persistent queue।
/// App restart হলেও pending sync items হারাবে না।
class SyncQueueItems extends Table {
  TextColumn get id => text()(); // UUID

  /// Sync queue entry-টা কোন user-এর — cross-user leak প্রতিরোধে non-nullable।
  /// Migration-এ existing row গুলো current logged-in user দিয়ে backfill হয়।
  TextColumn get userId => text()();

  /// 'favorite' | 'playlist' | 'history' | 'settings' ইত্যাদি
  TextColumn get entityType => text()();

  TextColumn get entityId => text()();

  /// 'create' | 'update' | 'delete'
  TextColumn get action => text()();

  /// JSON payload
  TextColumn get payload => text()();

  DateTimeColumn get createdAt =>
      dateTime().withDefault(currentDateAndTime)();

  IntColumn get retryCount => integer().withDefault(const Constant(0))();

  /// 'pending' | 'syncing' | 'failed' | 'completed'
  TextColumn get status =>
      text().withDefault(const Constant('pending'))();

  TextColumn get lastError => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}