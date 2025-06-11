import 'dart:async';
import 'dart:convert';
import 'package:event_sourcing/event_sourcing.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:signals/signals.dart';
import 'events.dart';

class CounterStore {
  final String path;
  FileSystem fs = const LocalFileSystem();
  late final File file = fs.file(path);
  late final EventStore<CounterEvent> eventStore = JsonFileEventStore(
    file,
    fs,
    onEvent,
    (event) {
      final type = event.type;
      final id = event.id;
      final key = event.data['key'] as String;
      final value = event.data['value'] as int? ?? 0;
      return switch (type) {
        'SET_VALUE' => SetValueEvent(key, value, id),
        'RESET' => ResetEvent(key, value, id),
        'INCREMENT' => IncrementEvent(key, value, id),
        'DECREMENT' => DecrementEvent(key, value, id),
        _ => throw ArgumentError('Unknown event type: $type'),
      };
    },
  );

  CounterStore(this.path) {
    if (!file.existsSync()) {
      file.createSync(recursive: true);
    }
  }

  final version = '1.0.0';

  late final metadata = () {
    final file = '$path.metadata';
    final metadataFile = fs.file(file);
    if (metadataFile.existsSync()) {
      final content = metadataFile.readAsStringSync();
      if (content.isNotEmpty) {
        return Map<String, dynamic>.from(jsonDecode(content));
      }
    } else {
      metadataFile.createSync(recursive: true);
    }
    final value = <String, dynamic>{
      'version': version,
      'createdAt': DateTime.now().toIso8601String(),
    };
    effect(() {
      final content = jsonEncode(value);
      metadataFile.writeAsStringSync(content);
    });
    return value;
  }();

  late final savedVersion = () {
    final metadata = this.metadata;
    final version = metadata['version'] as String?;
    if (version == null) {
      throw Exception('Metadata version is missing');
    }
    return version;
  }();

  late final counters = () {
    final value = mapSignal(<String, int>{});
    final countersPath = '$path.state';
    final countersFile = fs.file(countersPath);
    if (countersFile.existsSync()) {
      final content = countersFile.readAsStringSync();
      if (content.isNotEmpty) {
        final parsed = Map<String, dynamic>.from(jsonDecode(content));
        for (final entry in parsed.entries) {
          value[entry.key] = entry.value as int;
        }
      }
    } else {
      countersFile.createSync(recursive: true);
    }
    effect(() {
      final content = jsonEncode(value.toMap());
      countersFile.writeAsStringSync(content);
    });
    if (savedVersion != version && savedVersion.isNotEmpty) {
      // print('Migrating from version $savedVersion to $version');
      value.clear();
      eventStore.replayAll();
    }
    return value;
  }();

  static const String counterKey = 'counter';

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
      _ => throw UnimplementedError('Unknown event type: ${event.type}'),
    };
  }

  FutureOr<void> onReset() async => counters.clear();
}
