import 'package:flutter/material.dart';

import 'store.dart';
import 'events.dart';
import 'example.dart';

void main() async {
  final store = CounterStore();
  await store.init();
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
      home: NotificationListener<CounterNotification>(
        onNotification: (event) {
          counterStore.eventStore.add(event.event);
          return true;
        },
        child: CounterExample(store: counterStore),
      ),
    );
  }
}
