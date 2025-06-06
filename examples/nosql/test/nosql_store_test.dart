import 'package:sqlite3/common.dart';
import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:nosql/store.dart';
import 'package:nosql/events.dart';

void main() {
  group('NoSqlStore', () {
    late NoSqlStore store;
    late CommonDatabase db;

    setUp(() async {
      db = sqlite3.openInMemory();
      store = NoSqlStore(db);
      await store.init();
    });

    tearDown(() async {
      db.dispose();
    });

    test('Create, update, and delete collection', () async {
      final collectionId = 'col1';
      await store.eventStore.add(
        CreateCollectionEvent(collectionId, 'Test Collection'),
      );
      expect(store.getCollection(collectionId)?.name, 'Test Collection');

      await store.eventStore.add(
        UpdateCollectionEvent(collectionId, 'Updated Name'),
      );
      expect(store.getCollection(collectionId)?.name, 'Updated Name');

      await store.eventStore.add(DeleteCollectionEvent(collectionId));
      expect(store.getCollection(collectionId)?.name, isNull);
    });

    test('Create, update, and delete document', () async {
      final collectionId = 'col2';
      await store.eventStore.add(CreateCollectionEvent(collectionId, 'Docs'));
      await store.eventStore.add(CreateDocumentEvent(collectionId));
      final events = await store.eventStore.getAll();
      final docEvent = events.whereType<CreateDocumentEvent>().first;
      final documentId = docEvent.id.toString();
      expect(store.getDocument(collectionId, documentId)?.data, {});

      await store.eventStore.add(
        PatchDocumentEvent(collectionId, documentId, {'foo': 'bar'}),
      );
      final updated = store.getDocument(collectionId, documentId)?.data;
      expect(updated, {'foo': 'bar'});

      await store.eventStore.add(DeleteDocumentEvent(collectionId, documentId));
      expect(store.getDocument(collectionId, documentId)?.data, isNull);
    });

    test('Deleting a collection deletes its documents', () async {
      final collectionId = 'col3';
      await store.eventStore.add(
        CreateCollectionEvent(collectionId, 'Cascade'),
      );
      await store.eventStore.add(CreateDocumentEvent(collectionId));
      final events = await store.eventStore.getAll();
      final docEvent = events.whereType<CreateDocumentEvent>().first;
      final documentId = docEvent.id.toString();
      expect(store.getDocument(collectionId, documentId)?.data, isNotNull);

      await store.eventStore.add(DeleteCollectionEvent(collectionId));
      expect(store.getDocument(collectionId, documentId)?.data, isNull);
    });

    test('Update non-existent document does nothing', () async {
      final collectionId = 'col4';
      final documentId = 'nonexistent';
      await store.eventStore.add(CreateCollectionEvent(collectionId, 'Test'));
      // Should not throw
      await store.eventStore.add(
        PatchDocumentEvent(collectionId, documentId, {'foo': 'bar'}),
      );
      expect(store.getDocument(collectionId, documentId)?.data, isNull);
    });

    test('Create multiple documents in a collection', () async {
      final collectionId = 'col5';
      await store.eventStore.add(
        CreateCollectionEvent(collectionId, 'MultiDocs'),
      );
      await store.eventStore.add(CreateDocumentEvent(collectionId));
      await store.eventStore.add(CreateDocumentEvent(collectionId));
      final events = await store.eventStore.getAll();
      final docEvents = events.whereType<CreateDocumentEvent>().toList();
      expect(docEvents.length, 2);
      for (final docEvent in docEvents) {
        final documentId = docEvent.id.toString();
        expect(store.getDocument(collectionId, documentId)?.data, {});
      }
    });

    test('Update document with empty patch does not change data', () async {
      final collectionId = 'col6';
      await store.eventStore.add(
        CreateCollectionEvent(collectionId, 'EmptyPatch'),
      );
      await store.eventStore.add(CreateDocumentEvent(collectionId));
      final events = await store.eventStore.getAll();
      final docEvent = events.whereType<CreateDocumentEvent>().first;
      final documentId = docEvent.id.toString();
      await store.eventStore.add(
        PatchDocumentEvent(collectionId, documentId, {}),
      );
      expect(store.getDocument(collectionId, documentId)?.data, {});
    });

    test(
      'Delete non-existent collection and document does not throw',
      () async {
        final collectionId = 'col7';
        final documentId = 'doesnotexist';
        // Should not throw
        await store.eventStore.add(DeleteCollectionEvent(collectionId));
        await store.eventStore.add(
          DeleteDocumentEvent(collectionId, documentId),
        );
        expect(store.getCollection(collectionId)?.name, isNull);
        expect(store.getDocument(collectionId, documentId)?.data, isNull);
      },
    );

    test(
      'PatchDocumentEvent merges fields, SetDocumentEvent replaces data',
      () async {
        final collectionId = 'col_patch_set';
        await store.eventStore.add(
          CreateCollectionEvent(collectionId, 'PatchSet'),
        );
        await store.eventStore.add(CreateDocumentEvent(collectionId));
        final events = await store.eventStore.getAll();
        final docEvent = events.whereType<CreateDocumentEvent>().first;
        final documentId = docEvent.id.toString();

        // Patch: add foo
        await store.eventStore.add(
          PatchDocumentEvent(collectionId, documentId, {'foo': 'bar'}),
        );
        expect(store.getDocument(collectionId, documentId)?.data, {
          'foo': 'bar',
        });

        // Patch: add baz
        await store.eventStore.add(
          PatchDocumentEvent(collectionId, documentId, {'baz': 123}),
        );
        expect(store.getDocument(collectionId, documentId)?.data, {
          'foo': 'bar',
          'baz': 123,
        });

        // Set: replace with only qux
        await store.eventStore.add(
          SetDocumentEvent(collectionId, documentId, {'qux': true}),
        );
        expect(store.getDocument(collectionId, documentId)?.data, {
          'qux': true,
        });

        // Patch: add foo back, should merge
        await store.eventStore.add(
          PatchDocumentEvent(collectionId, documentId, {'foo': 'again'}),
        );
        expect(store.getDocument(collectionId, documentId)?.data, {
          'qux': true,
          'foo': 'again',
        });
      },
    );

    test('DuplicateDocumentEvent duplicates a document', () async {
      final collectionId = 'col_dup';
      await store.eventStore.add(
        CreateCollectionEvent(collectionId, 'DupTest'),
      );
      await store.eventStore.add(CreateDocumentEvent(collectionId));
      final events = await store.eventStore.getAll();
      final docEvent = events.whereType<CreateDocumentEvent>().first;
      final documentId = docEvent.id.toString();
      await store.eventStore.add(
        PatchDocumentEvent(collectionId, documentId, {'foo': 'bar'}),
      );
      // Duplicate the document
      final newDocumentId = 'dup_id';
      await store.eventStore.add(
        DuplicateDocumentEvent(collectionId, documentId, newDocumentId),
      );
      // Check original
      expect(store.getDocument(collectionId, documentId)?.data, {'foo': 'bar'});
      // Check duplicate
      expect(store.getDocument(collectionId, newDocumentId)?.data, {
        'foo': 'bar',
      });
    });
  });
}
