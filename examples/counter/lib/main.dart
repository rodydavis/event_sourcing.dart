import 'package:event_sourcing/event_sourcing_flutter.dart';
import 'package:flutter/material.dart';
import 'package:path_provider/path_provider.dart';

import 'events.dart';
import 'store.dart';
import 'example.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final dir = await getApplicationDocumentsDirectory();
  final path = '${dir.path}/counters.json';
  final store = CounterStore(path);
  final key = CounterStore.counterKey;
  final current = await store.eventStore.getAll();
  if (current.isEmpty) {
    await store.eventStore.addAll([
      ResetEvent(key),
      IncrementEvent(key),
      IncrementEvent(key),
      DecrementEvent(key),
      SetValueEvent(key, 5),
    ]);
  }
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
