import 'dart:io';
import 'package:sqlite3/common.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:test/test.dart';
import 'package:event_sourcing/event_sourcing.dart';

void main() {
  group('SqliteEventStore', () {
    late File tempFile;
    late SqliteEventStore store;
    late CommonDatabase db;

    setUp(() {
      tempFile = File('test_event_store.sqlite');
      if (tempFile.existsSync()) tempFile.deleteSync();
      db = sqlite3.open(tempFile.path);
      store = SqliteEventStore(db, (_) {}, (e) => e);
    });

    tearDown(() async {
      await store.dispose();
      if (tempFile.existsSync()) tempFile.deleteSync();
      db.dispose();
    });

    test('add and getAll persists to db', () async {
      final event = Event(
        id: Hlc.now('node1'),
        type: 'created',
        data: {'foo': 'bar'},
        version: '2.0.0',
      );
      await store.add(event);
      final allEvents = await store.getAll();
      expect(allEvents.length, 1);
      expect(allEvents.first.id, event.id);
      expect(allEvents.first.data['foo'], 'bar');
      expect(allEvents.first.version, '2.0.0');
    });

    test('addAll and getById', () async {
      final events = [
        Event(id: Hlc.now('node1'), type: 'a', data: {}),
        Event(id: Hlc.now('node1'), type: 'b', data: {}),
      ];
      await store.addAll(events);
      final event = await store.getById(events[1].id.toString());
      expect(event, isNotNull);
      expect(event!.type, 'b');
    });

    test('deleteAll clears db', () async {
      await store.add(Event(id: Hlc.now('node1'), type: 'a', data: {}));
      await store.deleteAll();
      final allEvents = await store.getAll();
      expect(allEvents, isEmpty);
    });

    test('watchAll emits events as they are added', () async {
      final events = [
        Event(id: Hlc.now('node1'), type: 'a', data: {}),
        Event(id: Hlc.now('node1'), type: 'b', data: {}),
      ];
      final emitted = <Event>[];
      final sub = store.onEvent().listen(emitted.add);
      await store.addAll(events);
      await Future.delayed(Duration(milliseconds: 100));
      expect(emitted.length, 2);
      expect(
        emitted.map((e) => e.id),
        containsAll([events[0].id, events[1].id]),
      );
      await sub.cancel();
    });

    test('data with nested JSON encodes and decodes correctly', () async {
      final nestedData = {
        'foo': 'bar',
        'nested': {
          'list': [1, 2, 3],
          'map': {'a': 1, 'b': 2},
        },
      };
      final event = Event(
        id: Hlc.now('node1'),
        type: 'json_test',
        data: nestedData,
      );
      await store.add(event);
      final allEvents = await store.getAll();
      expect(allEvents.length, 1);
      expect(allEvents.first.id, event.id);
      expect(allEvents.first.data, nestedData);
    });

    test('event version is updated and retrieved correctly', () async {
      final id = Hlc.now('node1');
      final eventV1 = Event(
        id: id,
        type: 'schema',
        data: {'foo': 'bar'},
        version: '1.0.0',
      );
      final eventV2 = Event(
        id: id,
        type: 'schema',
        data: {'foo': 'baz'},
        version: '2.0.0',
      );
      await store.add(eventV1);
      await store.add(eventV2);
      final allEvents = await store.getAll();
      expect(allEvents.last.version, '2.0.0');
      expect(allEvents.last.data['foo'], 'baz');
    });

    test('events persist after dispose and reload', () async {
      // Create and add events
      final event1 = Event(
        id: Hlc.now('node1'),
        type: 'persist1',
        data: {'foo': 'bar'},
      );
      final event2 = Event(
        id: Hlc.now('node1'),
        type: 'persist2',
        data: {'baz': 123},
      );
      await store.add(event1);
      await store.add(event2);
      // Dispose the store (but not the db file)
      await store.dispose();
      // Reopen the store with the same db file
      final reopenedStore = SqliteEventStore(db, (_) {}, (e) => e);
      final allEvents = await reopenedStore.getAll();
      expect(allEvents.length, 2);
      expect(allEvents[0].type, 'persist1');
      expect(allEvents[0].data['foo'], 'bar');
      expect(allEvents[1].type, 'persist2');
      expect(allEvents[1].data['baz'], 123);
      await reopenedStore.dispose();
    });
  });
}
