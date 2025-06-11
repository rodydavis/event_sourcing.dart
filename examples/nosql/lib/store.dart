import 'package:event_sourcing/event_sourcing.dart';
import 'package:sqlite3/common.dart';
import 'dart:async';
import 'dart:convert';
import 'events.dart';

class NoSqlStore {
  late final EventStore eventStore = InMemoryEventStore(onEvent, (event) {
    final type = event.type;
    final collectionId = event.data['collectionId'] as String;
    final documentId = event.data['documentId'] as String?;
    final patch = (event.data['patch'] as Map? ?? {}).cast<String, dynamic>();
    return switch (type) {
      'CREATE_COLLECTION' => CreateCollectionEvent(
        collectionId,
        event.data['collectionName'] as String,
      ),
      'UPDATE_COLLECTION' => UpdateCollectionEvent(
        collectionId,
        event.data['collectionName'] as String?,
      ),
      'DELETE_COLLECTION' => DeleteCollectionEvent(collectionId),
      'CREATE_DOCUMENT' => CreateDocumentEvent(
        collectionId,
        documentId!,
        patch,
      ),
      'PATCH_DOCUMENT' => PatchDocumentEvent(collectionId, documentId!, patch),
      'SET_DOCUMENT' => SetDocumentEvent(collectionId, documentId!, patch),
      'DUPLICATE_DOCUMENT' => DuplicateDocumentEvent(
        collectionId,
        documentId!,
        event.data['newDocumentId'] as String,
      ),
      'DELETE_DOCUMENT' => DeleteDocumentEvent(collectionId, documentId!),
      _ => throw ArgumentError('Unknown event type: $type'),
    };
  });
  final CommonDatabase db;

  NoSqlStore(this.db);

  FutureOr<void> init() async {
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

  FutureOr<void> onReset() {
    db.execute('DELETE FROM documents;');
    db.execute('DELETE FROM collections;');
  }

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
        final documentId = event.documentId;
        final patch = event.patch;
        db.execute(
          'INSERT INTO documents (id, collection_id, data) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET data = ?;',
          [documentId, collectionId, jsonEncode(patch), jsonEncode(patch)],
        );
      }(),
      PatchDocumentEvent() => () async {
        final collectionId = event.collectionId;
        final documentId = event.documentId;
        final patch = event.patch;
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
        final patch = event.patch;
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
      DuplicateDocumentEvent() => () async {
        final collectionId = event.collectionId;
        final documentId = event.documentId;
        final existingDoc = getDocument(collectionId, documentId);
        if (existingDoc != null) {
          final newDocumentId = event.newDocumentId;
          db.execute(
            'INSERT INTO documents (id, collection_id, data) VALUES (?, ?, ?);',
            [newDocumentId, collectionId, jsonEncode(existingDoc.data)],
          );
        }
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

  List<Document> getDocuments(String collectionId) {
    final result = db.select(
      'SELECT id, data FROM documents WHERE collection_id = ?;',
      [collectionId],
    );
    return result.map(Document.new).toList();
  }

  List<Collection> getCollections() {
    final result = db.select('SELECT id, name FROM collections;');
    return result.map(Collection.new).toList();
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
