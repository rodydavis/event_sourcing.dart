import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';
import 'package:pos/store.dart';
import 'package:pos/events.dart';

void main() {
  group('POS Store Integration Tests', () {
    late PosStore store;
    late Database db;

    setUp(() async {
      db = sqlite3.openInMemory();
      store = PosStore(db);
      await store.init();
    });

    tearDown(() async {
      await store.dispose();
    });

    test('Add products, inventory, and customer, then query state', () async {
      // Step 1: Add products
      final product1Id = 1;
      final product2Id = 2;
      final customer1Id = 3;
      await store.eventStore.addAll([
        AddProductEvent(product1Id, 'Laptop', 1200.00),
        AddProductEvent(product2Id, 'Mouse', 25.00),
      ]);
      var products = store.db.select('SELECT * FROM products');
      expect(products.length, 2, reason: 'Two products should be added');
      expect(
        products.first['name'],
        'Laptop',
        reason: 'First product should be Laptop',
      );

      // Step 2: Set inventory for products
      await store.eventStore.addAll([
        SetProductInventoryEvent(product1Id, 10),
        SetProductInventoryEvent(product2Id, 50),
      ]);
      var inventory = store.db.select('SELECT * FROM inventory');
      expect(
        inventory.length,
        2,
        reason: 'Inventory should be set for both products',
      );
      expect(
        inventory.first['quantity'],
        10,
        reason: 'First product inventory should be 10',
      );

      // Step 3: Add customer
      await store.eventStore.addAll([
        AddCustomerEvent(customer1Id, 'Alice Smith'),
      ]);
      var customers = store.db.select('SELECT * FROM customers');
      expect(customers.length, 1, reason: 'One customer should be added');
      expect(
        customers.first['name'],
        'Alice Smith',
        reason: 'Customer name should be Alice Smith',
      );

      // Step 4: Set customer balance
      await store.eventStore.addAll([
        UpdateCustomerBalanceEvent(customer1Id, 100.00),
      ]);
      var balances = store.db.select('SELECT * FROM balances');
      expect(balances.length, 1, reason: 'One balance entry should exist');
      expect(
        balances.first['balance'],
        100.00,
        reason: 'Balance should be set to 100.00',
      );
    });

    test('Start order, add product to order, and complete order', () async {
      // Step 1: Add product and set inventory
      final productId = 1;
      final customerId = 2;
      final orderId = 10;
      await store.eventStore.addAll([
        AddProductEvent(productId, 'Keyboard', 50.0),
        SetProductInventoryEvent(productId, 5),
      ]);
      var products = store.db.select('SELECT * FROM products');
      var inventory = store.db.select(
        'SELECT quantity FROM inventory WHERE product_id = ?',
        [productId],
      );
      expect(products.length, 1, reason: 'Product should be added');
      expect(
        inventory.first['quantity'],
        5,
        reason: 'Inventory should be set to 5',
      );

      // Step 2: Add customer and set balance
      await store.eventStore.addAll([
        AddCustomerEvent(customerId, 'Bob'),
        UpdateCustomerBalanceEvent(customerId, 200.0),
      ]);
      var customers = store.db.select('SELECT * FROM customers');
      var balances = store.db.select(
        'SELECT balance FROM balances WHERE customer_id = ?',
        [customerId],
      );
      expect(customers.length, 1, reason: 'Customer should be added');
      expect(
        balances.first['balance'],
        200.0,
        reason: 'Balance should be set to 200',
      );

      // Step 3: Start order
      await store.eventStore.addAll([StartOrderEvent(orderId, customerId)]);
      var orders = store.db.select('SELECT * FROM orders');
      expect(orders.length, 1, reason: 'Order should be started');
      expect(
        orders.first['customer_id'],
        customerId,
        reason: 'Order should be for correct customer',
      );

      // Step 4: Add product to order (set quantity to 2)
      await store.eventStore.addAll([
        AddProductToOrderEvent(orderId, productId, 2),
      ]);
      var orderItems = store.db.select('SELECT * FROM order_items');
      expect(orderItems.length, 1, reason: 'Order item should be created');
      expect(
        orderItems.first['quantity'],
        2,
        reason: 'Order item quantity should be 2',
      );

      // Step 5: Complete order
      await store.eventStore.addAll([CompleteOrderEvent(orderId)]);
      inventory = store.db.select(
        'SELECT quantity FROM inventory WHERE product_id = ?',
        [productId],
      );
      expect(
        inventory.first['quantity'],
        3,
        reason: 'Inventory should be decremented by 2',
      );
      balances = store.db.select(
        'SELECT balance FROM balances WHERE customer_id = ?',
        [customerId],
      );
      expect(
        balances.first['balance'],
        100.0,
        reason: 'Balance should be decremented by 100 (2 x 50)',
      );
    });

    test('Refund order restores customer balance', () async {
      // Step 1: Add product and set inventory
      final productId = 1;
      final customerId = 2;
      final orderId = 10;
      await store.eventStore.addAll([
        AddProductEvent(productId, 'Monitor', 300.0),
        SetProductInventoryEvent(productId, 2),
      ]);
      var products = store.db.select('SELECT * FROM products');
      var inventory = store.db.select(
        'SELECT quantity FROM inventory WHERE product_id = ?',
        [productId],
      );
      expect(products.length, 1, reason: 'Product should be added');
      expect(
        inventory.first['quantity'],
        2,
        reason: 'Inventory should be set to 2',
      );

      // Step 2: Add customer and set balance
      await store.eventStore.addAll([
        AddCustomerEvent(customerId, 'Carol'),
        UpdateCustomerBalanceEvent(customerId, 500.0),
      ]);
      var customers = store.db.select('SELECT * FROM customers');
      var balances = store.db.select(
        'SELECT balance FROM balances WHERE customer_id = ?',
        [customerId],
      );
      expect(customers.length, 1, reason: 'Customer should be added');
      expect(
        balances.first['balance'],
        500.0,
        reason: 'Balance should be set to 500',
      );

      // Step 3: Start order
      await store.eventStore.addAll([StartOrderEvent(orderId, customerId)]);
      var orders = store.db.select('SELECT * FROM orders');
      expect(orders.length, 1, reason: 'Order should be started');
      expect(
        orders.first['customer_id'],
        customerId,
        reason: 'Order should be for correct customer',
      );

      // Step 4: Add product to order (set quantity to 1)
      await store.eventStore.addAll([
        AddProductToOrderEvent(orderId, productId, 1),
      ]);
      var orderItems = store.db.select('SELECT * FROM order_items');
      expect(orderItems.length, 1, reason: 'Order item should be created');
      expect(
        orderItems.first['quantity'],
        1,
        reason: 'Order item quantity should be 1',
      );

      // Step 5: Complete order
      await store.eventStore.addAll([CompleteOrderEvent(orderId)]);
      balances = store.db.select(
        'SELECT balance FROM balances WHERE customer_id = ?',
        [customerId],
      );
      expect(
        balances.first['balance'],
        200.0,
        reason: 'Balance should be decremented by 300 (1 x 300)',
      );

      // Step 6: Refund order
      await store.eventStore.addAll([RefundOrderEvent(orderId)]);
      balances = store.db.select(
        'SELECT balance FROM balances WHERE customer_id = ?',
        [customerId],
      );
      expect(
        balances.first['balance'],
        500.0,
        reason: 'Balance should be restored to 500 after refund',
      );
      orders = store.db.select('SELECT refunded FROM orders WHERE id = ?', [
        orderId,
      ]);
      expect(
        orders.first['refunded'],
        1,
        reason: 'Order should be marked as refunded',
      );
    });

    test('Inventory upsert works for new and existing products', () async {
      // Step 1: Add product
      final productId = 1;
      final orderId = 1;
      final customerId = 1;
      await store.eventStore.addAll([
        StartOrderEvent(orderId, customerId),
        AddCustomerEvent(customerId, 'Alice'),
        AddProductEvent(productId, 'Tablet', 400.0),
      ]);
      var inventory = store.db.select(
        'SELECT quantity FROM inventory WHERE product_id = ?',
        [productId],
      );
      expect(
        inventory.first['quantity'],
        0,
        reason: 'Inventory should default to 0',
      );

      // Step 2: Set inventory
      await store.eventStore.addAll([SetProductInventoryEvent(productId, 7)]);
      inventory = store.db.select(
        'SELECT quantity FROM inventory WHERE product_id = ?',
        [productId],
      );
      expect(
        inventory.first['quantity'],
        7,
        reason: 'Inventory should be set to 7',
      );

      // Step 3: Update inventory
      await store.eventStore.addAll([
        SetProductInventoryEvent(productId, 12),
        CompleteOrderEvent(orderId),
      ]);
      inventory = store.db.select(
        'SELECT quantity FROM inventory WHERE product_id = ?',
        [productId],
      );
      expect(
        inventory.first['quantity'],
        12,
        reason: 'Inventory should be updated to 12',
      );
    });

    test('Add product to order multiple times increments quantity', () async {
      // Step 1: Add product and set inventory
      final productId = 1;
      final customerId = 2;
      final orderId = 10;
      await store.eventStore.addAll([
        AddProductEvent(productId, 'Keyboard', 50.0),
        SetProductInventoryEvent(productId, 5),
      ]);
      var products = store.db.select('SELECT * FROM products');
      var inventory = store.db.select(
        'SELECT quantity FROM inventory WHERE product_id = ?',
        [productId],
      );
      expect(products.length, 1, reason: 'Product should be added');
      expect(
        inventory.first['quantity'],
        5,
        reason: 'Inventory should be set to 5',
      );

      // Step 2: Add customer and set balance
      await store.eventStore.addAll([
        AddCustomerEvent(customerId, 'Bob'),
        UpdateCustomerBalanceEvent(customerId, 200.0),
      ]);
      var customers = store.db.select('SELECT * FROM customers');
      var balances = store.db.select(
        'SELECT balance FROM balances WHERE customer_id = ?',
        [customerId],
      );
      expect(customers.length, 1, reason: 'Customer should be added');
      expect(
        balances.first['balance'],
        200.0,
        reason: 'Balance should be set to 200',
      );

      // Step 3: Start order
      await store.eventStore.addAll([StartOrderEvent(orderId, customerId)]);
      var orders = store.db.select('SELECT * FROM orders');
      expect(orders.length, 1, reason: 'Order should be started');
      expect(
        orders.first['customer_id'],
        customerId,
        reason: 'Order should be for correct customer',
      );

      // Step 4: Add product to order and increment quantity
      await store.eventStore.addAll([
        AddProductToOrderEvent(orderId, productId, 1),
        IncreaseProductQuantityEvent(orderId, productId, 1),
        IncreaseProductQuantityEvent(orderId, productId, 1),
      ]);
      var orderItems = store.db.select(
        'SELECT * FROM order_items WHERE order_id = ?',
        [orderId],
      );
      expect(orderItems.length, 1, reason: 'Order item should be created');
      expect(
        orderItems.first['quantity'],
        3,
        reason: 'Order item quantity should be incremented to 3',
      );
    });

    test(
      'Add product to order with set quantity replaces previous quantity',
      () async {
        // Step 1: Add product and set inventory
        final productId = 1;
        final customerId = 2;
        final orderId = 10;
        await store.eventStore.addAll([
          AddProductEvent(productId, 'Keyboard', 50.0),
          SetProductInventoryEvent(productId, 5),
        ]);
        var products = store.db.select('SELECT * FROM products');
        var inventory = store.db.select(
          'SELECT quantity FROM inventory WHERE product_id = ?',
          [productId],
        );
        expect(products.length, 1, reason: 'Product should be added');
        expect(
          inventory.first['quantity'],
          5,
          reason: 'Inventory should be set to 5',
        );

        // Step 2: Add customer and set balance
        await store.eventStore.addAll([
          AddCustomerEvent(customerId, 'Bob'),
          UpdateCustomerBalanceEvent(customerId, 200.0),
        ]);
        var customers = store.db.select('SELECT * FROM customers');
        var balances = store.db.select(
          'SELECT balance FROM balances WHERE customer_id = ?',
          [customerId],
        );
        expect(customers.length, 1, reason: 'Customer should be added');
        expect(
          balances.first['balance'],
          200.0,
          reason: 'Balance should be set to 200',
        );

        // Step 3: Start order
        await store.eventStore.addAll([StartOrderEvent(orderId, customerId)]);
        var orders = store.db.select('SELECT * FROM orders');
        expect(orders.length, 1, reason: 'Order should be started');
        expect(
          orders.first['customer_id'],
          customerId,
          reason: 'Order should be for correct customer',
        );

        // Step 4: Add product to order (set quantity to 2, then replace with 5)
        await store.eventStore.addAll([
          AddProductToOrderEvent(orderId, productId, 2),
          AddProductToOrderEvent(orderId, productId, 5),
        ]);
        var orderItems = store.db.select('SELECT * FROM order_items');
        expect(orderItems.length, 1, reason: 'Order item should be created');
        expect(
          orderItems.first['quantity'],
          5,
          reason: 'Order item quantity should be replaced with 5',
        );
      },
    );
  });
}
