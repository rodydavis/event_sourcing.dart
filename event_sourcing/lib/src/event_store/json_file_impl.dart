import 'dart:convert';
import 'dart:async';

import 'package:file/file.dart';

import 'base.dart';
import '../event.dart';

/// An implementation of [EventStore] that persists events to a JSON file on disk.
///
/// Each event is serialized as a single line of JSON and appended to the file.
/// This means the file is a sequence of newline-delimited JSON objects, with one event per line.
///
/// On initialization, all events are loaded by reading each line and deserializing it.
/// When new events are added, they are simply appended as new lines.
///
/// The [onEvent] method is optimized for efficiency: it keeps track of the last byte offset read in the file.
/// When the file changes, it only reads and parses the new lines that have been appended, avoiding reparsing the entire file.
/// The file is kept open for the duration of the stream to further reduce overhead.
///
/// This approach is highly efficient for append-only event streams, as it minimizes disk I/O and parsing work.
class JsonFileEventStore<E extends Event> extends EventStore<E> {
  final File file;
  final FileSystem fileSystem;

  JsonFileEventStore(
    this.file,
    this.fileSystem,
    super.processEvent,
    super.parseEvent,
  );

  // TODO: Fails when async
  Future<void> _append(E event) async {
    final str = '${jsonEncode(event.toJson())}\n';
    await file.writeAsString(str, mode: FileMode.append);
    // if (!fileSystem.isWatchSupported) {
    //   // Emit to stream if not using file watch
    //   _controller.add(event);
    // }
  }

  @override
  Future<void> add(E event) async {
    await _append(event);
    await super.add(event);
  }

  @override
  Future<void> addAll(Iterable<E> events) async {
    for (final event in events) {
      await _append(event);
    }
    await super.addAll(events);
  }

  @override
  Future<List<E>> getAll() async {
    final lines = file.readAsLinesSync();
    return lines
        .where((line) => line.trim().isNotEmpty)
        .map((line) => Event.fromJson(jsonDecode(line.trim())))
        .map(parseEvent)
        .toList();
  }

  @override
  Future<E?> getById(String id) async {
    final lines = file
        .openRead()
        .transform(utf8.decoder)
        .transform(const LineSplitter());
    await for (final line in lines) {
      if (line.trim().isEmpty) continue;
      final event = Event.fromJson(jsonDecode(line.trim()));
      if (event.id.toString() == id) {
        return parseEvent(event);
      }
    }
    return null;
  }

  @override
  Future<void> deleteAll() async {
    await file.delete();
    await file.create(recursive: true);
    await super.deleteAll();
  }

  /// Streams all events as they are added or detected from file changes.
  // @override
  // Stream<Event> onEvent() async* {
  //   // Emit all current events first
  //   final lines = await file.readAsLines();
  //   final seen = <String>{};
  //   for (final line in lines) {
  //     if (line.trim().isEmpty) continue;
  //     final event = Event.fromJson(jsonDecode(line));
  //     seen.add(event.id.toString());
  //     yield event;
  //   }

  //   if (fileSystem.isWatchSupported) {
  //     int lastPosition = await file.length();
  //     var raf = file.openSync(mode: FileMode.read);
  //     try {
  //       await for (final event in file.parent.watch(
  //         events: FileSystemEvent.modify,
  //       )) {
  //         if (event.type == FileSystemEvent.modify && event.path == file.path) {
  //           final bytesToRead = await file.length() - lastPosition;
  //           if (bytesToRead > 0) {
  //             raf = await raf.setPosition(lastPosition);
  //             final bytes = await raf.read(bytesToRead);
  //             final newContent = utf8.decode(bytes);
  //             final newLines = LineSplitter.split(newContent);
  //             for (final line in newLines) {
  //               if (line.trim().isEmpty) continue;
  //               final loadedEvent = Event.fromJson(jsonDecode(line));
  //               if (!seen.contains(loadedEvent.id.toString())) {
  //                 seen.add(loadedEvent.id.toString());
  //                 yield loadedEvent;
  //               }
  //             }
  //             lastPosition = await file.length();
  //           }
  //         }
  //       }
  //     } finally {
  //       await raf.close();
  //     }
  //   } else {
  //     yield* _controller.stream;
  //   }
  // }
}
