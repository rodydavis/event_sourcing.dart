import 'dart:async';
import 'dart:collection';

import '../event.dart';

abstract class EventStore<E extends Event> {
  final FutureOr<void> Function(Event event) processEvent;
  final E Function(Event) parseEvent;
  EventStore(this.processEvent, this.parseEvent);
  final _eventQueue = Queue<E>();
  final _controller = StreamController<E>.broadcast();
  final eventsController = StreamController<List<E>>.broadcast();

  FutureOr<void> _processEvents() async {
    // print('Processing ${_eventQueue.length} events');
    while (_eventQueue.isNotEmpty) {
      final event = _eventQueue.removeFirst();
      // print('Processing event: ${event.type} with id: ${event.id}');
      await processEvent(event);
      _controller.add(event);
    }
  }

  /// Saves an event to the store.
  Future<void> add(E event) async {
    _eventQueue.add(event);
    await _processEvents();
  }

  /// Saves a list of events to the store.
  Future<void> addAll(Iterable<E> events) async {
    final list = events.toList();
    list.sort((a, b) => a.id.compareTo(b.id));
    _eventQueue.addAll(list);
    await _processEvents();
  }

  /// Watch all events
  Stream<E> onEvent() => _controller.stream;

  /// Retrieves all events from the event store.
  FutureOr<List<E>> getAll();

  /// Retrieve an event by its ID
  FutureOr<E?> getById(String id);

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

  FutureOr<bool> restoreToEvent(E event) async {
    final list = (await getAll()).toList();
    list.sort((a, b) => a.id.compareTo(b.id));
    var staged = <E>[];
    bool found = false;
    for (final e in list) {
      staged.add(e);
      if (e.id == event.id) {
        found = true;
        break;
      }
    }
    // await replayAll(events: staged);
    await deleteAll();
    await addAll(staged.toList());
    return found;
  }

  FutureOr<bool> mergeEvents(Iterable<E> events) async {
    if (events.isEmpty) return false;
    var all = (await getAll()).toSet();
    all.addAll(events);
    await deleteAll();
    await addAll(all.toList());
    return true;
  }

  FutureOr<void> replayAll({Iterable<E>? events}) async {
    var all = events ?? await getAll();
    // await deleteAll();
    // await addAll(all.toList());
    // print('Replaying ${all.length} events');
    for (final event in all) {
      // print('Replaying event: ${event.type} with id: ${event.id}');
      await processEvent(event);
      // print('Processed event: ${event.type} with id: ${event.id}');
    }
  }
}
