import 'dart:async';
import 'package:file/file.dart';
import 'package:file/memory.dart';
import 'package:file/local.dart';
import 'package:test/test.dart';
import 'package:event_sourcing/event_sourcing.dart';

void main() {
  group('JsonFileEventStore', () {
    late File tempFile;
    FileSystem fs = MemoryFileSystem();
    late JsonFileEventStore store;

    setUp(() {
      fs = MemoryFileSystem();
      tempFile = fs.file('test_event_store.json');
      if (tempFile.existsSync()) tempFile.deleteSync();
      store = JsonFileEventStore(tempFile, fs, (_) {}, (e) => e);
    });

    tearDown(() {
      if (tempFile.existsSync()) tempFile.deleteSync();
    });

    test('add and getAll persists to disk', () async {
      final event = Event(
        id: Hlc.now('node1'),
        type: 'created',
        data: {'foo': 'bar'},
        version: '2.0.0',
      );
      await store.add(event);
      final loadedStore = JsonFileEventStore(tempFile, fs, (_) {}, (e) => e);
      final allEvents = await loadedStore.getAll();
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
      final loadedStore = JsonFileEventStore(tempFile, fs, (_) {}, (e) => e);
      final event = await loadedStore.getById(events[1].id.toString());
      expect(event, isNotNull);
      expect(event!.type, 'b');
    });

    test('deleteAll clears file', () async {
      await store.add(Event(id: Hlc.now('node1'), type: 'a', data: {}));
      await store.deleteAll();
      final loadedStore = JsonFileEventStore(tempFile, fs, (_) {}, (e) => e);
      final allEvents = await loadedStore.getAll();
      expect(allEvents, isEmpty);
    });

    test(
      'watchAll emits events as they are added (memory filesystem)',
      () async {
        var now = Hlc.now('node1');
        final events = [
          Event(id: now.increment(), type: 'a', data: {}),
          Event(id: now.increment(), type: 'b', data: {}),
        ];
        final emitted = <Event>[];
        final store = JsonFileEventStore(tempFile, fs, (_) {}, (e) => e);
        final completer = Completer<void>();
        final sub = store.onEvent().listen((event) {
          emitted.add(event);
          if (emitted.length == 2 && !completer.isCompleted) {
            completer.complete();
          }
        });
        await store.addAll(events);
        await completer.future.timeout(Duration(seconds: 10));
        expect(emitted.length, 2);
        expect(
          emitted.map((e) => e.id),
          containsAll([events[0].id, events[1].id]),
        );
        await sub.cancel();
      },
    );

    test(
      'watchAll emits events as they are added (local filesystem)',
      () async {
        var now = Hlc.now('node1');
        final events = [
          Event(id: now.increment(), type: 'a', data: {}),
          Event(id: now.increment(), type: 'b', data: {}),
        ];
        final emitted = <Event>[];
        fs = LocalFileSystem();
        final store = JsonFileEventStore(tempFile, fs, (_) {}, (e) => e);
        final completer = Completer<void>();
        final sub = store.onEvent().listen((event) {
          emitted.add(event);
          if (emitted.length == 2 && !completer.isCompleted) {
            completer.complete();
          }
        });
        await store.addAll(events);
        await completer.future.timeout(Duration(seconds: 10));
        expect(emitted.length, 2);
        expect(
          emitted.map((e) => e.id),
          containsAll([events[0].id, events[1].id]),
        );
        await sub.cancel();
      },
    );

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
      final loadedStore = JsonFileEventStore(tempFile, fs, (_) {}, (e) => e);
      final allEvents = await loadedStore.getAll();
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
      final loadedStore = JsonFileEventStore(tempFile, fs, (_) {}, (e) => e);
      final allEvents = await loadedStore.getAll();
      expect(allEvents.last.version, '2.0.0');
      expect(allEvents.last.data['foo'], 'baz');
    });
  });
}
