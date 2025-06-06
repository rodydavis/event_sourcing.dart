import 'dart:async';

import 'package:event_sourcing/event_sourcing.dart';
import 'package:signals/signals.dart';
import 'package:sqlite3/common.dart';

import 'events.dart';
import 'hooks.dart';

class PosStore {
  late final EventStore eventStore = InMemoryEventStore(onEvent);
  final CommonDatabase db;

  PosStore(this.db);

  FutureOr<void> init() async {
    // Create tables and indexes if they do not exist

    // Products
    db.execute('''
      CREATE TABLE IF NOT EXISTS products (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        price REAL NOT NULL
      );
    ''');

    // Inventory
    db.execute('''
      CREATE TABLE IF NOT EXISTS inventory (
        product_id INTEGER NOT NULL PRIMARY KEY,
        quantity INTEGER NOT NULL,
        FOREIGN KEY (product_id) REFERENCES products(id)
      );
    ''');

    // Customers
    db.execute('''
      CREATE TABLE IF NOT EXISTS customers (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        name TEXT NOT NULL,
        email TEXT UNIQUE
      );
    ''');

    // Balances
    db.execute('''
      CREATE TABLE IF NOT EXISTS balances (
        customer_id INTEGER NOT NULL PRIMARY KEY,
        balance REAL NOT NULL DEFAULT 0,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      );
    ''');

    // Orders and order items (product item or balance adjustment)
    db.execute('''
      CREATE TABLE IF NOT EXISTS orders (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        customer_id INTEGER,
        order_date DATETIME NOT NULL DEFAULT CURRENT_TIMESTAMP,
        refunded BOOLEAN NOT NULL DEFAULT FALSE,
        completed BOOLEAN NOT NULL DEFAULT FALSE,
        FOREIGN KEY (customer_id) REFERENCES customers(id)
      );

      CREATE TABLE IF NOT EXISTS order_items (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        order_id INTEGER NOT NULL,
        product_id INTEGER,
        product_price REAL,
        balance_adjustment REAL,
        quantity INTEGER,
        FOREIGN KEY (order_id) REFERENCES orders(id),
        FOREIGN KEY (product_id) REFERENCES products(id),
        UNIQUE(order_id, product_id)
      );
    ''');
  }

  FutureOr<void> onReset() {
    // Delete all rows in all tables
    db.execute('DELETE FROM products;');
    db.execute('DELETE FROM inventory;');
    db.execute('DELETE FROM customers;');
    db.execute('DELETE FROM balances;');
    db.execute('DELETE FROM orders;');
    db.execute('DELETE FROM order_items;');
  }

  FutureOr<void> onEvent(Event event) async {
    assert(event is PosEvent, 'Event must be a PosEvent');
    return switch (event) {
      AddCustomerEvent() => () async {
        final customerId = event.customerId;
        final name = event.name;
        db.execute(
          'INSERT INTO customers (id, name) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name;',
          [customerId, name],
        );
        db.execute(
          'INSERT INTO balances (customer_id, balance) VALUES (?, 0) ON CONFLICT(customer_id) DO UPDATE SET balance = balance;',
          [customerId],
        );
      }(),
      UpdateCustomerEvent() => () async {
        final customerId = event.customerId;
        final name = event.name;
        db.execute(
          'INSERT INTO customers (id, name) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name;',
          [customerId, name],
        );
      }(),
      DeleteCustomerEvent() => () async {
        final customerId = event.customerId;
        db.execute('DELETE FROM customers WHERE id = ?;', [customerId]);
        db.execute('DELETE FROM balances WHERE customer_id = ?;', [customerId]);
      }(),
      AddProductEvent() => () async {
        final productId = event.productId;
        final name = event.name;
        final price = event.price;
        db.execute(
          'INSERT INTO products (id, name, price) VALUES (?, ?, ?) ON CONFLICT(id) DO UPDATE SET name = excluded.name, price = excluded.price;',
          [productId, name, price],
        );
        db.execute(
          'INSERT INTO inventory (product_id, quantity) VALUES (?, 0) ON CONFLICT(product_id) DO UPDATE SET quantity = quantity;',
          [productId],
        );
      }(),
      UpdateProductNameEvent() => () async {
        final productId = event.productId;
        final name = event.name;
        db.execute(
          'INSERT INTO products (id, name, price) VALUES (?, ?, COALESCE((SELECT price FROM products WHERE id = ?), 0)) ON CONFLICT(id) DO UPDATE SET name = excluded.name;',
          [productId, name, productId],
        );
      }(),
      UpdateProductPriceEvent() => () async {
        final productId = event.productId;
        final price = event.price;
        db.execute(
          'INSERT INTO products (id, name, price) VALUES (?, COALESCE((SELECT name FROM products WHERE id = ?), \'\'), ?) ON CONFLICT(id) DO UPDATE SET price = excluded.price;',
          [productId, productId, price],
        );
      }(),
      DeleteProductEvent() => () async {
        final productId = event.productId;
        db.execute('DELETE FROM products WHERE id = ?;', [productId]);
        db.execute('DELETE FROM inventory WHERE product_id = ?;', [productId]);
      }(),
      SetProductInventoryEvent() => () async {
        final productId = event.productId;
        final quantity = event.quantity;
        db.execute(
          'INSERT INTO inventory (product_id, quantity) VALUES (?, ?) ON CONFLICT(product_id) DO UPDATE SET quantity = excluded.quantity;',
          [productId, quantity],
        );
      }(),
      StartOrderEvent() => () async {
        final orderId = event.orderId;
        final customerId = event.customerId;
        db.execute(
          'INSERT INTO orders (id, customer_id) VALUES (?, ?) ON CONFLICT(id) DO UPDATE SET customer_id = excluded.customer_id;',
          [orderId, customerId],
        );
        db.execute(
          'INSERT INTO balances (customer_id, balance) VALUES (?, 0) ON CONFLICT(customer_id) DO UPDATE SET balance = balance;',
          [customerId],
        );
      }(),
      AddProductToOrderEvent() => () async {
        final orderId = event.orderId;
        final productId = event.productId;
        final quantity = event.quantity;
        final priceResult = db.select(
          'SELECT price FROM products WHERE id = ?;',
          [productId],
        );
        final price =
            priceResult.isNotEmpty ? priceResult.first['price'] as double : 0.0;
        db.execute(
          'INSERT INTO order_items (order_id, product_id, product_price, quantity) VALUES (?, ?, ?, ?) ON CONFLICT(order_id, product_id) DO UPDATE SET quantity = excluded.quantity, product_price = excluded.product_price;',
          [orderId, productId, price, quantity],
        );
      }(),
      RemoveProductFromOrderEvent() => () async {
        final orderId = event.orderId;
        final productId = event.productId;
        db.execute(
          'DELETE FROM order_items WHERE order_id = ? AND product_id = ?;',
          [orderId, productId],
        );
      }(),
      IncreaseProductQuantityEvent() => () async {
        final orderId = event.orderId;
        final productId = event.productId;
        final quantity = event.quantity;
        db.execute(
          'UPDATE order_items SET quantity = quantity + ? WHERE order_id = ? AND product_id = ?;',
          [quantity, orderId, productId],
        );
      }(),
      DecreaseProductQuantityEvent() => () async {
        final orderId = event.orderId;
        final productId = event.productId;
        final quantity = event.quantity;
        db.execute(
          'UPDATE order_items SET quantity = quantity - ? WHERE order_id = ? AND product_id = ?;',
          [quantity, orderId, productId],
        );
      }(),
      UpdateCustomerBalanceEvent() => () async {
        final customerId = event.customerId;
        final balance = event.balance;
        db.execute(
          'INSERT INTO balances (customer_id, balance) VALUES (?, ?) ON CONFLICT(customer_id) DO UPDATE SET balance = excluded.balance;',
          [customerId, balance],
        );
      }(),
      CompleteOrderEvent() => () async {
        final orderId = event.orderId;
        db.execute('UPDATE orders SET completed = 1 WHERE id = ?;', [orderId]);
        final orderResult = db.select(
          'SELECT customer_id FROM orders WHERE id = ?;',
          [orderId],
        );
        if (orderResult.isNotEmpty) {
          // get the total amount from order items
          final totalResult = db.select(
            'SELECT SUM(product_price * quantity) AS total FROM order_items WHERE order_id = ?;',
            [orderId],
          );
          final totalAmount =
              totalResult.isNotEmpty
                  ? totalResult.first['total'] as double? ?? 0.0
                  : 0.0;
          final customerId = orderResult.first['customer_id'];
          db.execute(
            'UPDATE balances SET balance = balance - ? WHERE customer_id = ?;',
            [totalAmount, customerId],
          );

          // Get order items to update inventory
          final orderItems = db.select(
            'SELECT product_id, quantity FROM order_items WHERE order_id = ?;',
            [orderId],
          );
          for (final item in orderItems) {
            final productId = item['product_id'] as int;
            final quantity = item['quantity'] as int;
            db.execute(
              'UPDATE inventory SET quantity = quantity - ? WHERE product_id = ?;',
              [quantity, productId],
            );
          }
        }
      }(),
      CancelOrderEvent() => () async {
        final orderId = event.orderId;
        db.execute('DELETE FROM order_items WHERE order_id = ?;', [orderId]);
        db.execute('DELETE FROM orders WHERE id = ?;', [orderId]);
      }(),
      RefundOrderEvent() => () async {
        final orderId = event.orderId;
        db.execute('UPDATE orders SET refunded = 1 WHERE id = ?;', [orderId]);
        final orderResult = db.select(
          'SELECT customer_id FROM orders WHERE id = ?;',
          [orderId],
        );
        if (orderResult.isNotEmpty) {
          // get the refund amount from order items
          final refundAmountResult = db.select(
            'SELECT SUM(product_price * quantity) AS total FROM order_items WHERE order_id = ?;',
            [orderId],
          );
          final refundAmount =
              refundAmountResult.isNotEmpty
                  ? refundAmountResult.first['total'] as double
                  : 0.0;
          final customerId = orderResult.first['customer_id'];
          db.execute(
            'UPDATE balances SET balance = balance + ? WHERE customer_id = ?;',
            [refundAmount, customerId],
          );
        }
      }(),
      _ => throw UnimplementedError('Unknown event type: [${event.type}'),
    };
  }

  SqliteQuerySignal watch(String sql, [List<Object?> args = const []]) {
    final s = signal(sql);
    final a = signal(args);
    return SqliteQuerySignal(db, s, a);
  }
}
