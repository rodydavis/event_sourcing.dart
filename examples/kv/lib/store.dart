import 'package:event_sourcing/event_sourcing.dart';
import 'package:sqlite3/common.dart';
import 'dart:async';
import 'events.dart';

class KeyValueStore with ViewStore<CommonDatabase> {
  @override
  late final EventStore eventStore = InMemoryEventStore(onEvent);
  final CommonDatabase db;

  KeyValueStore(this.db);

  @override
  FutureOr<void> init() async {
    await super.init();
    db.execute('''
      CREATE TABLE IF NOT EXISTS kv_store (
        key TEXT PRIMARY KEY,
        value
      );
    ''');
  }

  @override
  FutureOr<void> onReset() {
    db.execute('DELETE FROM kv_store;');
  }

  @override
  FutureOr<void> onEvent(Event event) async {
    return switch (event) {
      SetKeyValueEvent() => () async {
        final key = event.key;
        final value = event.value;
        db.execute(
          'INSERT INTO kv_store (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = excluded.value;',
          [key, value],
        );
      }(),
      DeleteKeyValueEvent() => () async {
        final key = event.key;
        db.execute('DELETE FROM kv_store WHERE key = ?;', [key]);
      }(),
      _ =>
        throw UnimplementedError('Unknown event type: [${event.runtimeType}'),
    };
  }

  Object? getValue(String key) {
    final result = db.select('SELECT value FROM kv_store WHERE key = ?;', [
      key,
    ]);
    if (result.isEmpty) return null;
    return result.first['value'];
  }
}
