import 'package:drift/drift.dart';

/// Persisted Continue Session snapshot (v11 — multi-song resume).
/// Single-row-in-practice table (one active session at a time), but kept
/// as a proper table (not Settings key) so the full queue snapshot can
/// live as a JSON blob without bloating SettingsEntries.
class ContinueSessions extends Table {
  TextColumn get id => text()(); // sessionId

  /// YouTube videoId of the song that was playing (Songs.id / SearchResult.videoId)
  TextColumn get currentSongId => text()();

  IntColumn get currentPositionMs => integer()();

  /// JSON-encoded List<SearchResult> (see searchResultToJson/FromJson)
  TextColumn get queueSnapshot => text()();

  IntColumn get currentIndex => integer()();

  /// e.g. "Daily Mix", a playlist name, etc.
  TextColumn get sourceRail => text()();

  DateTimeColumn get lastPlayedAt =>
      dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}
