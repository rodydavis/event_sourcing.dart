import 'package:flutter/material.dart';
import 'package:sqlite3/sqlite3.dart';
import 'store.dart';
import 'events.dart';
import 'example.dart';

void main() async {
  // Initialize sqflite for Flutter
  // WidgetsFlutterBinding.ensureInitialized(); // Not needed for sqlite3 package
  final db = sqlite3.openInMemory();
  final store = PosStore(db);
  await store.init();

  // Example initial events (optional)
  final product1Id = 1;
  final product2Id = 2;
  final customer1Id = 3;

  await store.eventStore.addAll([
    AddProductEvent(product1Id, 'Laptop', 1200.00),
    AddProductEvent(product2Id, 'Mouse', 25.00),
    SetProductInventoryEvent(product1Id, 10),
    SetProductInventoryEvent(product2Id, 50),
    AddCustomerEvent(customer1Id, 'Alice Smith'),
    UpdateCustomerBalanceEvent(customer1Id, 100.00),
  ]);

  runApp(App(store: store));
}

class App extends StatelessWidget {
  const App({super.key, required this.store});

  final PosStore store;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: NotificationListener<PosNotification>(
        onNotification: (notification) {
          store.eventStore.add(notification.event);
          return true;
        },
        child: PosExample(store: store),
      ),
    );
  }
}
