import 'dart:async';

import '../event.dart';
import 'base.dart';

/// An in-memory implementation of [EventStore] that stores events in a map.
///
/// Useful for testing and development purposes.
///
/// Example usage:
/// ```dart
/// final store = InMemoryEventStore();
/// final event = Event(
///   id: '1',
///   type: 'created',
///   timestamp: Hlc.now('node1'),
///   data: {'foo': 'bar'},
/// );
/// await store.add(event);
/// final allEvents = await store.getAll();
/// print(allEvents);
/// ```
class InMemoryEventStore extends EventStore {
  InMemoryEventStore(super.processEvent);
  var events = <Event>[];

  /// Saves an event to the in-memory store.
  @override
  Future<void> add(Event event) async {
    await super.add(event);
    events.add(event);
  }

  /// Saves a list of events to the in-memory store.
  @override
  Future<void> addAll(Iterable<Event> events) async {
    await super.addAll(events);
    this.events.addAll(events);
  }

  /// Disposes resources used by the event store (e.g., closes streams).
  @override
  Future<void> dispose() async {
    await super.dispose();
  }

  @override
  FutureOr<Event?> getById(String id) {
    for (final event in events) {
      if (event.id.toString() == id) {
        return event;
      }
    }
    return null; // Return null if no event with the given ID is found
  }

  @override
  FutureOr<List<Event>> getAll() async {
    return events.toList();
  }

  @override
  FutureOr<void> deleteAll() async {
    await super.deleteAll();
    events.clear();
  }
}
