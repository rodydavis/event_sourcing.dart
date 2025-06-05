import 'package:test/test.dart';
import 'package:event_sourcing/event_sourcing.dart';

void main() {
  group('InMemoryEventStore', () {
    late InMemoryEventStore store;
    setUp(() {
      store = InMemoryEventStore((_) {});
    });

    test('add and getAll', () async {
      final event = Event(
        id: Hlc.now('test-node'),
        type: 'created',
        data: {'foo': 'bar'},
        version: '2.0.0',
      );
      await store.add(event);
      final allEvents = await store.getAll();
      expect(allEvents.length, 1);
      expect(allEvents.first.id, event.id);
      expect(allEvents.first.version, '2.0.0');
    });

    test('addAll and getAll', () async {
      final events = [
        Event(id: Hlc.now('test-node'), type: 'a', data: {}),
        Event(id: Hlc.now('test-node'), type: 'b', data: {}),
      ];
      await store.addAll(events);
      final allEvents = await store.getAll();
      expect(allEvents.length, 2);
      expect(
        allEvents.map((e) => e.id),
        containsAll([events[0].id, events[1].id]),
      );
    });

    test('getById returns correct event', () async {
      final event = Event(id: Hlc.now('test-node'), type: 'test', data: {});
      await store.add(event);
      final fetched = await store.getById(event.id.toString());
      expect(fetched, isNotNull);
      expect(fetched!.id, event.id);
    });

    test('deleteAll clears all events', () async {
      await store.add(Event(id: Hlc.now('test-node'), type: 'a', data: {}));
      await store.deleteAll();
      final allEvents = await store.getAll();
      expect(allEvents, isEmpty);
    });

    test('watchAll emits events as they are added', () async {
      final events = [
        Event(id: Hlc.now('test-node'), type: 'a', data: {}),
        Event(id: Hlc.now('test-node'), type: 'b', data: {}),
      ];
      final emitted = <Event>[];
      final sub = store.onEvent().listen(emitted.add);
      await store.addAll(events);
      // Wait for stream events to be delivered
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
        id: Hlc.now('test-node'),
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
      final id = Hlc.now('test-node');
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
  });
}
