import 'package:event_sourcing/event_sourcing.dart';

class CounterEvent extends AutoIncrementEvent {
  CounterEvent(
    String type,
    this.key, [
    Map<String, Object?> data = const {},
    Hlc? id,
  ]) : super(type, {...data, 'key': key}, id);

  final String key;
}

class SetValueEvent extends CounterEvent {
  SetValueEvent(String key, [this.value = 0, Hlc? id])
    : super('SET_VALUE', key, {'value': value}, id);

  final int value;
}

class ResetEvent extends CounterEvent {
  ResetEvent(String key, [this.value = 0, Hlc? id])
    : super('RESET', key, {'value': value}, id);

  final int value;
}

class IncrementEvent extends CounterEvent {
  IncrementEvent(String key, [this.value = 1, Hlc? id])
    : super('INCREMENT', key, {'value': value}, id);

  final int value;
}

class DecrementEvent extends CounterEvent {
  DecrementEvent(String key, [this.value = -1, Hlc? id])
    : super('DECREMENT', key, {'value': value}, id);

  final int value;
}
