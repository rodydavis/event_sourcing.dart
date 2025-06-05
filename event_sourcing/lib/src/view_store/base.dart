import 'dart:async';

import '../event.dart';
import '../event_store/base.dart';

mixin ViewStore<State> {
  EventStore get eventStore;

  FutureOr<void> init() async {}

  FutureOr<void> dispose() async {
    await eventStore.dispose();
    // _subscription?.cancel();
  }

  FutureOr<void> onEvent(Event event);

  FutureOr<void> onReset();

  FutureOr<bool> restoreToEvent(Event event) async {
    final events = await eventStore.getAll();
    await onReset();
    final staged = <Event>[];
    bool found = false;
    for (final e in events) {
      staged.add(e);
      if (e.id == event.id) {
        found = true;
        break;
      }
    }
    await eventStore.deleteAll();
    await eventStore.addAll(staged);
    return found;
  }
}
