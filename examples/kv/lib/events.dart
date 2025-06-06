import 'package:event_sourcing/event_sourcing.dart';

class SetKeyValueEvent extends AutoIncrementEvent {
  final String key;
  final Object? value;

  SetKeyValueEvent(this.key, this.value)
      : super('SET_KEY_VALUE', {'key': key, 'value': value});
}

class DeleteKeyValueEvent extends AutoIncrementEvent {
  final String key;

  DeleteKeyValueEvent(this.key)
      : super('DELETE_KEY_VALUE', {'key': key});
}
