import 'package:test/test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:kv/store.dart';
import 'package:kv/events.dart';

void main() {
  group('KeyValueStore', () {
    late KeyValueStore store;
    late Database db;

    setUp(() async {
      db = sqlite3.openInMemory();
      store = KeyValueStore(db);
      await store.init();
    });

    tearDown(() async {
      await store.dispose();
    });

    test('Set and get value', () async {
      await store.eventStore.add(SetKeyValueEvent('foo', 'bar'));
      expect(store.getValue('foo'), 'bar');
    });

    test('Update value', () async {
      await store.eventStore.add(SetKeyValueEvent('foo', 'bar'));
      await store.eventStore.add(SetKeyValueEvent('foo', 123));
      expect(store.getValue('foo'), 123);
    });

    test('Delete value', () async {
      await store.eventStore.add(SetKeyValueEvent('foo', 'bar'));
      await store.eventStore.add(DeleteKeyValueEvent('foo'));
      expect(store.getValue('foo'), isNull);
    });

    test('Handles JSON values', () async {
      final map = {'a': 1, 'b': true};
      final mapValue = jsonb.encode(map);
      await store.eventStore.add(SetKeyValueEvent('json', mapValue));
      expect(store.getValue('json'), mapValue);
    });
  });
}
