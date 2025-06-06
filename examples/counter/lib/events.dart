import 'package:event_sourcing/event_sourcing.dart';

class CounterEvent extends AutoIncrementEvent {
  CounterEvent(String type, this.key, [Map<String, Object?> data = const {}])
    : super(type, data);

  final String key;
}

class SetValueEvent extends CounterEvent {
  SetValueEvent(String key, [this.value = 0])
    : super('SET_VALUE', key, {'value': value});

  final int value;
}

class ResetEvent extends CounterEvent {
  ResetEvent(String key, [this.value = 0])
    : super('RESET', key, {'value': value});

  final int value;
}

class IncrementEvent extends CounterEvent {
  IncrementEvent(String key, [this.value = 1])
    : super('INCREMENT', key, {'value': value});

  final int value;
}

class DecrementEvent extends CounterEvent {
  DecrementEvent(String key, [this.value = -1])
    : super('DECREMENT', key, {'value': value});

  final int value;
}
