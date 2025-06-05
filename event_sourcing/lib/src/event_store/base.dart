import 'dart:async';
import 'dart:collection';

import '../event.dart';

abstract class EventStore {
  final FutureOr<void> Function(Event event) processEvent;
  EventStore(this.processEvent);
  final _eventQueue = Queue<Event>();
  final _controller = StreamController<Event>.broadcast();
  final eventsController = StreamController<List<Event>>.broadcast();

  FutureOr<void> _processEvents() async {
    while (_eventQueue.isNotEmpty) {
      final event = _eventQueue.removeFirst();
      await processEvent(event);
      _controller.add(event);
    }
  }

  /// Saves an event to the store.
  Future<void> add(Event event) async {
    _eventQueue.add(event);
    await _processEvents();
  }

  /// Saves a list of events to the store.
  Future<void> addAll(Iterable<Event> events) async {
    _eventQueue.addAll(events);
    await _processEvents();
  }

  /// Retrieves all events from the event store.
  FutureOr<List<Event>> getAll();

  /// Watch all events
  Stream<Event> onEvent() {
    return _controller.stream;
  }

  /// Retrieve an event by its ID
  FutureOr<Event?> getById(String id);

  /// Clears all events from the event store.
  FutureOr<void> deleteAll() {
    _eventQueue.clear();
    eventsController.add([]);
  }

  /// Disposes resources used by the event store (e.g., closes streams).
  FutureOr<void> dispose() async {
    _eventQueue.clear();
    await _controller.close();
  }
}
