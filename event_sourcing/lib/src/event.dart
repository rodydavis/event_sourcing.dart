import 'dart:convert';

import 'hlc.dart';

class AutoIncrementEvent extends Event {
  static var _hlc = Hlc.now('node1');

  static Hlc get newId => _hlc = _hlc.increment();

  /// The node ID for this event. Used to generate the HLC.
  set nodeId(String nodeId) {
    _hlc = Hlc.now(nodeId);
  }

  AutoIncrementEvent(
    String type, [
    Map<String, Object?> data = const {},
    Hlc? id,
  ]) : super(id: id ?? newId, type: type, data: {...data});
}

/// Represents a domain event with a unique ID (HLC), type, and associated data.
class Event {
  /// Globally unique identifier for the event (Hybrid Logical Clock).
  final Hlc id;

  /// The type or name of the event.
  final String type;

  /// The event payload data. Can be any serializable structure.
  final Map<String, dynamic> data;

  /// The version of the event schema. Used to ensure the schema of the data field is as expected.
  final String version;

  DateTime get date => id.dateTime;
  String get nodeId => id.nodeId;
  int get counter => id.counter;

  /// Creates a new [Event] instance.
  ///
  /// [id] is the unique identifier for the event (HLC).
  /// [type] is the event type or name.
  /// [data] is the event payload.
  /// [version] is the schema version for the event data.
  Event({
    required this.id,
    required this.type,
    required this.data,
    this.version = '1.0.0',
  });

  static dynamic parseData(dynamic rawData) {
    if (rawData is String) {
      try {
        return parseData(jsonDecode(rawData));
      } catch (e) {
        return rawData;
      }
    } else if (rawData is Map<String, dynamic>) {
      return rawData;
    } else if (rawData is Map) {
      return Map<String, dynamic>.from(rawData);
    }
    return rawData;
  }

  static String parseVersion(dynamic value) {
    if (value == null) return '1.0.0';
    if (value is String) return value;
    if (value is int || value is num) return value.toString();
    return '1.0.0';
  }

  /// Creates an [Event] from a JSON map.
  factory Event.fromJson(Map<String, dynamic> json) {
    return Event(
      id: Hlc.parse(json['id'] as String),
      type: json['type'] as String,
      data: parseData(json['data']),
      version: parseVersion(json['version']),
    );
  }

  /// Converts the [Event] to a JSON map.
  Map<String, dynamic> toJson() => {
    'id': id.toString(),
    'type': type,
    'data': dataToJson(),
    'version': version,
  };

  /// Converts the [data] field to a JSON string.
  String dataToJson() => jsonEncode(data);

  /// Returns a string representation of the [Event].
  @override
  String toString() =>
      'Event(id: $id, type: $type, data: $data, version: $version)';

  /// Checks equality based on all fields.
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is Event &&
          runtimeType == other.runtimeType &&
          id == other.id &&
          type == other.type &&
          data == other.data &&
          version == other.version;

  /// Returns a hash code based on all fields.
  @override
  int get hashCode => Object.hash(id, type, data, version);
}
