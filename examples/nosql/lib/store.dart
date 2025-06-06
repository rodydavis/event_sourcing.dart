import 'package:event_sourcing/event_sourcing.dart';
import 'package:sqlite3/common.dart';
import 'dart:async';
import 'dart:convert';
import 'events.dart';

class NoSqlStore with ViewStore<CommonDatabase> {
  @override
  late final EventStore eventStore = InMemoryEventStore(onEvent);
  final CommonDatabase db;

  NoSqlStore(this.db);

  @override
  FutureOr<void> init() async {
    await super.init();
    // Create collections and documents tables
    db.execute('''
      CREATE TABLE IF NOT EXISTS collections (
        id TEXT PRIMARY KEY,
        name TEXT NOT NULL
      );
    ''');
    db.execute('''
      CREATE TABLE IF NOT EXISTS documents (
        id TEXT PRIMARY KEY,
        collection_id TEXT NOT NULL,
        data TEXT NOT NULL,
        FOREIGN KEY (collection_id) REFERENCES collections(id)
      );
    ''');
  }

  @override
  FutureOr<void> onReset() {
    db.execute('DELETE FROM documents;');
    db.execute('DELETE FROM collections;');
  }

  @override
  FutureOr<void> onEvent(Event event) async {
    return switch (event) {
      CreateCollectionEvent() => () async {
        final collectionId = event.collectionId;
        final collectionName = event.collectionName;
        db.execute(
          'INSERT INTO collections (id, name) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name;',
          [collectionId, collectionName],
        );
      }(),
      UpdateCollectionEvent() => () async {
        final collectionId = event.collectionId;
        final collectionName = event.collectionName;
        if (collectionName != null) {
          db.execute('UPDATE collections SET name = ? WHERE id = ?;', [
            collectionName,
            collectionId,
          ]);
        }
      }(),
      DeleteCollectionEvent() => () async {
        final collectionId = event.collectionId;
        db.execute('DELETE FROM collections WHERE id = ?;', [collectionId]);
        db.execute('DELETE FROM documents WHERE collection_id = ?;', [
          collectionId,
        ]);
      }(),
      CreateDocumentEvent() => () async {
        final collectionId = event.collectionId;
        final documentId = event.id.toString();
        db.execute(
          'INSERT INTO documents (id, collection_id, data) VALUES (?, ?, ?) ON CONFLICT(id) DO NOTHING;',
          [documentId, collectionId, '{}'],
        );
      }(),
      PatchDocumentEvent() => () async {
        final collectionId = event.collectionId;
        final documentId = event.documentId;
        final patch = event.patch ?? {};
        // Use SQLite's json_patch for atomic patching
        db.execute(
          '''
          UPDATE documents
          SET data = json_patch(data, ?)
          WHERE id = ? AND collection_id = ?;
          ''',
          [jsonEncode(patch), documentId, collectionId],
        );
      }(),
      SetDocumentEvent() => () async {
        final collectionId = event.collectionId;
        final documentId = event.documentId;
        final patch = event.patch ?? {};
        // Use SQLite's json_patch for atomic set
        db.execute(
          '''
          UPDATE documents
          SET data = ?
          WHERE id = ? AND collection_id = ?;
          ''',
          [jsonEncode(patch), documentId, collectionId],
        );
      }(),
      DeleteDocumentEvent() => () async {
        final collectionId = event.collectionId;
        final documentId = event.documentId;
        db.execute(
          'DELETE FROM documents WHERE id = ? AND collection_id = ?;',
          [documentId, collectionId],
        );
      }(),
      _ =>
        throw UnimplementedError('Unknown event type: [${event.runtimeType}'),
    };
  }

  Document? getDocument(String collectionId, String documentId) {
    final result = db.select(
      'SELECT data FROM documents WHERE id = ? AND collection_id = ?;',
      [documentId, collectionId],
    );
    if (result.isEmpty) return null;
    return Document(result.first);
  }

  Collection? getCollection(String collectionId) {
    final result = db.select('SELECT name FROM collections WHERE id = ?;', [
      collectionId,
    ]);
    if (result.isEmpty) return null;
    return Collection(result.first);
  }
}

extension type Document(Row row) {
  String get id => row['id'] as String;
  String get collectionId => row['collection_id'] as String;
  Map<String, dynamic> get data {
    final data = row['data'] as String;
    return data.isNotEmpty ? jsonDecode(data) as Map<String, dynamic> : {};
  }
}

extension type Collection(Row row) {
  String get id => row['id'] as String;
  String get name => row['name'] as String;
}
