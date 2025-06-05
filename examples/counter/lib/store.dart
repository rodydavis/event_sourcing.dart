import 'dart:async';
import 'package:event_sourcing/event_sourcing.dart';
import 'package:signals/signals.dart';
import 'events.dart';

class CounterStore with ViewStore<Map<String, int>> {
  @override
  late final EventStore eventStore = InMemoryEventStore(onEvent);
  final counters = mapSignal(<String, int>{});

  static const String counterKey = 'counter';

  @override
  FutureOr<void> onEvent(Event event) async {
    return switch (event) {
      SetValueEvent() => () async {
        counters[event.key] = event.value;
      }(),
      ResetEvent() => () async {
        counters[event.key] = event.value;
      }(),
      IncrementEvent() => () async {
        final currentValue = counters[event.key] ?? 0;
        counters[event.key] = currentValue + event.value;
      }(),
      DecrementEvent() => () async {
        final currentValue = counters[event.key] ?? 0;
        counters[event.key] = currentValue + event.value;
      }(),
      _ => throw UnimplementedError('Unknown event type: [${event.type}'),
    };
  }

  @override
  FutureOr<void> onReset() async => counters.clear();
}
