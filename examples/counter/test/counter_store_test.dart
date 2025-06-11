import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:counter/store.dart';
import 'package:counter/events.dart';
import 'package:file/memory.dart';

void main() {
  group('Counter Store Integration Tests', () {
    late CounterStore store;
    final tempDir = Directory.systemTemp.createTempSync('counter_store_test');
    final tempFile = File('${tempDir.path}/counter_store.json');

    setUp(() async {
      store = CounterStore(tempFile.path);
      store.fs = MemoryFileSystem();
    });

    tearDown(() async {
      tempFile.deleteSync();
    });

    test('Initial state is zero', () async {
      expect(store.count, 0, reason: 'Counter should start at 0');
    });

    test('Increment event increases counter', () async {
      // Step 1: Increment
      await store.eventStore.add(IncrementEvent(CounterStore.counterKey));
      expect(store.count, 1, reason: 'Counter should be 1 after increment');
    });

    test('Decrement event decreases counter', () async {
      // Step 1: Increment
      await store.eventStore.add(IncrementEvent(CounterStore.counterKey));
      // Step 2: Decrement
      await store.eventStore.add(DecrementEvent(CounterStore.counterKey));
      expect(
        store.count,
        0,
        reason: 'Counter should be 0 after increment and decrement',
      );
    });

    test('SetValueEvent sets counter to specific value', () async {
      // Step 1: Set value to 42
      await store.eventStore.add(SetValueEvent(CounterStore.counterKey, 42));
      expect(store.count, 42, reason: 'Counter should be set to 42');
    });

    test('Multiple increments and decrements', () async {
      // Step 1: Increment 3 times
      await store.eventStore.addAll([
        IncrementEvent(CounterStore.counterKey),
        IncrementEvent(CounterStore.counterKey),
        IncrementEvent(CounterStore.counterKey),
      ]);
      expect(
        store.count,
        3,
        reason: 'Counter should be 3 after three increments',
      );
      // Step 2: Decrement twice
      await store.eventStore.addAll([
        DecrementEvent(CounterStore.counterKey),
        DecrementEvent(CounterStore.counterKey),
      ]);
      expect(
        store.count,
        1,
        reason: 'Counter should be 1 after two decrements',
      );
    });

    test('Reset sets counter to zero', () async {
      // Step 1: Increment
      await store.eventStore.add(IncrementEvent(CounterStore.counterKey));
      expect(store.count, 1, reason: 'Counter should be 1 after increment');

      // Step 2: Reset
      await store.eventStore.add(SetValueEvent(CounterStore.counterKey, 0));
      expect(store.count, 0, reason: 'Counter should be reset to 0');
    });

    test('Decrement below zero', () async {
      // Step 1: Decrement when counter is zero
      await store.eventStore.add(DecrementEvent(CounterStore.counterKey));
      expect(
        store.count,
        -1,
        reason: 'Counter should be -1 after decrement from zero',
      );
    });

    test('Multiple resets', () async {
      // Step 1: Increment
      await store.eventStore.add(IncrementEvent(CounterStore.counterKey));
      expect(store.count, 1, reason: 'Counter should be 1 after increment');
      // Step 2: Reset
      await store.eventStore.add(SetValueEvent(CounterStore.counterKey, 0));
      expect(store.count, 0, reason: 'Counter should be reset to 0');
      // Step 3: Reset again
      await store.eventStore.add(SetValueEvent(CounterStore.counterKey, 0));
      expect(
        store.count,
        0,
        reason: 'Counter should still be 0 after another reset',
      );
    });

    test('SetValueEvent after increment/decrement', () async {
      // Step 1: Increment
      await store.eventStore.add(IncrementEvent(CounterStore.counterKey));
      expect(store.count, 1, reason: 'Counter should be 1 after increment');
      // Step 2: Set value to 10
      await store.eventStore.add(SetValueEvent(CounterStore.counterKey, 10));
      expect(store.count, 10, reason: 'Counter should be set to 10');
      // Step 3: Decrement
      await store.eventStore.add(DecrementEvent(CounterStore.counterKey));
      expect(store.count, 9, reason: 'Counter should be 9 after decrement');
    });

    test('Increment after reset', () async {
      // Step 1: Increment
      await store.eventStore.add(IncrementEvent(CounterStore.counterKey));
      expect(store.count, 1, reason: 'Counter should be 1 after increment');
      // Step 2: Reset
      await store.eventStore.add(SetValueEvent(CounterStore.counterKey, 0));
      expect(store.count, 0, reason: 'Counter should be reset to 0');
      // Step 3: Increment again
      await store.eventStore.add(IncrementEvent(CounterStore.counterKey));
      expect(
        store.count,
        1,
        reason: 'Counter should be 1 after incrementing from reset',
      );
    });
  });
}

extension on CounterStore {
  int get count => counters()[CounterStore.counterKey] ?? 0;
}
