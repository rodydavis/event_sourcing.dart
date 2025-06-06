import 'package:event_sourcing/event_sourcing_flutter.dart';
import 'package:flutter/material.dart';

import 'store.dart';
import 'events.dart';
import 'example.dart';

void main() async {
  final store = CounterStore();
  final key = CounterStore.counterKey;
  await store.eventStore.addAll([
    ResetEvent(key),
    IncrementEvent(key),
    IncrementEvent(key),
    DecrementEvent(key),
    SetValueEvent(key, 5),
  ]);
  runApp(App(counterStore: store));
}

class App extends StatelessWidget {
  const App({super.key, required this.counterStore});

  final CounterStore counterStore;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: EventNotificationHandler(
        eventStore: counterStore.eventStore,
        child: CounterExample(store: counterStore),
      ),
    );
  }
}
