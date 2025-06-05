import 'dart:async';

import 'package:sqlite3/common.dart';

import '../../event_sourcing.dart';

/// Supported storage types for the event data column in SQLite.
enum SqliteEventDataType {
  /// Store as plain text (default, compatible with all SQLite versions)
  text,

  /// Store as JSON text and use SQLite JSON1 functions
  json,

  /// Store as JSONB (binary, requires SQLite 3.45+ with JSONB extension)
  jsonb,
}

/// An implementation of [EventStore] that persists events to a SQLite database.
class SqliteEventStore extends EventStore {
  final CommonDatabase db;
  final SqliteEventDataType dataType;

  /// Creates a [SqliteEventStore] from a [CommonDatabase] instance.
  /// If [wal] is true, enables Write-Ahead Logging mode for better write performance.
  /// [dataType] controls how the event data is stored (text, json, or jsonb).
  SqliteEventStore(
    this.db,
    super.processEvent, {
    bool wal = false,
    this.dataType = SqliteEventDataType.text,
  }) {
    if (wal) {
      db.execute('PRAGMA journal_mode=WAL;');
    }
    final dataColType = dataType == SqliteEventDataType.jsonb ? 'BLOB' : 'TEXT';
    db.execute('''
      CREATE TABLE IF NOT EXISTS events (
        id TEXT PRIMARY KEY,
        type TEXT,
        data $dataColType,
        version TEXT DEFAULT '1.0.0'
      )
    ''');
  }

  @override
  Future<void> add(Event event) async {
    await super.add(event);
    db.execute(
      'INSERT OR REPLACE INTO events (id, type, data, version) VALUES (?, ?, ?, ?)',
      [event.id.toString(), event.type, event.dataToJson(), event.version],
    );
  }

  @override
  Future<void> addAll(Iterable<Event> events) async {
    await super.addAll(events);
    final stmt = db.prepare(
      'INSERT OR REPLACE INTO events (id, type, data, version) VALUES (?, ?, ?, ?)',
    );
    db.execute('BEGIN');
    try {
      for (final event in events) {
        stmt.execute([
          event.id.toString(),
          event.type,
          event.dataToJson(),
          event.version,
        ]);
      }
      db.execute('COMMIT');
    } catch (e) {
      db.execute('ROLLBACK');
      rethrow;
    } finally {
      stmt.dispose();
    }
  }

  /// Returns the correct select clause for the data column based on the dataType.
  String get _selectDataClause {
    return dataType == SqliteEventDataType.text ? "data" : "json(data) as data";
  }

  /// Private getter for event column names to avoid typos.
  String get _eventColumns => 'id, type, $_selectDataClause, version';

  @override
  Future<List<Event>> getAll() async {
    // TODO: should we get a correct global order by hlc?
    final result = db.select("SELECT $_eventColumns FROM events");
    return result.map(_eventFromRow).toList();
  }

  @override
  Future<Event?> getById(String id) async {
    final result = db.select("SELECT $_eventColumns FROM events WHERE id = ?", [
      id,
    ]);
    if (result.isEmpty) return null;
    final row = result.first;
    return _eventFromRow(row);
  }

  @override
  Future<void> deleteAll() async {
    await super.deleteAll();
    db.execute('DELETE FROM events');
  }

  /// Streams all events as they are added, updated, or deleted using the database's .updates stream.
  // @override
  // Stream<Event> onEvent() async* {
  //   // Emit all current events first
  //   // yield* Stream.fromIterable(await getAll());

  //   // Listen to all changes on the events table and emit the full list of events on each change
  //   await for (final event in db.updates) {
  //     if (event.tableName == 'events') {
  //       final rowId = event.rowId;
  //       final result = db.select(
  //         "SELECT $_eventColumns FROM events WHERE rowid = ?",
  //         [rowId],
  //       );
  //       if (result.isEmpty) continue;
  //       final row = result.first;
  //       yield _eventFromRow(row);
  //     }
  //   }
  // }

  @override
  Future<void> dispose() async {
    await super.dispose();
    db.dispose();
  }

  Event _eventFromRow(Row row) {
    return Event(
      id: Hlc.parse(row['id'] as String),
      type: row['type'] as String,
      data: Event.parseData(row['data']),
      version: row['version']?.toString() ?? '1.0.0',
    );
  }
}
