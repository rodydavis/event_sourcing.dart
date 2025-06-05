/// POS Example App
///
/// This widget demonstrates a simple point-of-sale system using event sourcing.
/// It allows management of customers, products, and orders, and supports event history, refunds, and order restoration.
import 'package:flutter/material.dart';
import 'package:sqlite3/common.dart' show ResultSet;
import 'store.dart';
import 'events.dart';
import 'history.dart';

/// The main POS example widget.
class PosExample extends StatefulWidget {
  /// Create a POS example with the given [store].
  const PosExample({super.key, required this.store});

  /// The store managing all POS data and events.
  final PosStore store;

  @override
  State<PosExample> createState() => _PosExampleState();
}

/// State for [PosExample].
///
/// Manages navigation, selected entities, and all UI logic for the POS demo.
class _PosExampleState extends State<PosExample> {
  // Controllers for text fields used in dialogs and forms.
  final _productNameController = TextEditingController();
  final _productPriceController = TextEditingController();
  final _inventoryQuantityController = TextEditingController();
  final _customerNameController = TextEditingController();
  final _customerBalanceController = TextEditingController();
  final _cartQuantityController = TextEditingController();

  // Selected IDs for products, customers, and orders.
  int? _selectedProductId;
  int? _selectedCustomerId;
  int? _selectedOrderId;
  int _selectedNavIndex = 0;

  @override
  void dispose() {
    _productNameController.dispose();
    _productPriceController.dispose();
    _inventoryQuantityController.dispose();
    _customerNameController.dispose();
    _customerBalanceController.dispose();
    _cartQuantityController.dispose();
    super.dispose();
  }

  /// Dispatches a [PosEvent] to the store using notifications.
  void _dispatchEvent(PosEvent event) {
    PosNotification(event).dispatch(context);
  }

  /// Starts a new order for the selected customer.
  void _startOrder() {
    if (_selectedCustomerId != null) {
      final orderId = DateTime.now().millisecondsSinceEpoch;
      _dispatchEvent(StartOrderEvent(orderId, _selectedCustomerId!));
      setState(() {
        _selectedOrderId = orderId;
        _selectedNavIndex = 2; // Switch to Cart tab
      });
    }
  }

  /// Adds the selected product and quantity to the current order.
  void _addItemToCart() {
    if (_selectedOrderId != null && _selectedProductId != null) {
      final quantity = int.tryParse(_cartQuantityController.text);
      if (quantity != null && quantity > 0) {
        _dispatchEvent(
          AddProductToOrderEvent(
            _selectedOrderId!,
            _selectedProductId!,
            quantity,
          ),
        );
        _cartQuantityController.clear();
      }
    }
  }

  /// Completes the current order and resets selection.
  void _checkout() {
    if (_selectedOrderId != null) {
      _dispatchEvent(CompleteOrderEvent(_selectedOrderId!));
      setState(() {
        _selectedOrderId = null;
        _selectedCustomerId = null;
      });
    }
  }

  /// Refunds the given order by ID.
  void _refundOrder(int orderId) {
    final orderDetails = widget.store.db.select(
      'SELECT SUM(product_price * quantity) AS total FROM order_items WHERE order_id = ?',
      [orderId],
    );
    if (orderDetails.isNotEmpty) {
      _dispatchEvent(RefundOrderEvent(orderId));
    }
  }

  /// Restores a refunded order by ID.
  void _restoreOrder(int orderId) {
    widget.store.db.execute('UPDATE orders SET refunded = 0 WHERE id = ?;', [orderId]);
    _dispatchEvent(CompleteOrderEvent(orderId));
  }

  /// Handles navigation bar tab selection.
  void _onNavBarTap(int index) {
    setState(() {
      _selectedNavIndex = index;
    });
  }

  /// Shows a dialog for adding or editing a product.
  Future<void> _showProductDialog({Map<String, dynamic>? product}) async {
    final isEdit = product != null;
    final nameController = TextEditingController(
      text: isEdit ? product['name'] as String : '',
    );
    final priceController = TextEditingController(
      text: isEdit ? product['price'].toString() : '',
    );
    final inventoryController = TextEditingController(
      text:
          isEdit && product.containsKey('quantity')
              ? product['quantity'].toString()
              : '',
    );

    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit Product' : 'Add Product'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Product Name'),
              ),
              TextField(
                controller: priceController,
                decoration: const InputDecoration(labelText: 'Product Price'),
                keyboardType: TextInputType.number,
              ),
              TextField(
                controller: inventoryController,
                decoration: const InputDecoration(
                  labelText: 'Inventory Quantity',
                ),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text;
                final price = double.tryParse(priceController.text);
                final quantity = int.tryParse(inventoryController.text);
                if (name.isNotEmpty &&
                    price != null &&
                    (quantity != null || !isEdit)) {
                  if (isEdit) {
                    if (name != product['name']) {
                      _dispatchEvent(
                        UpdateProductNameEvent(product['id'] as int, name),
                      );
                    }
                    if (price != product['price']) {
                      _dispatchEvent(
                        UpdateProductPriceEvent(product['id'] as int, price),
                      );
                    }
                    if (quantity != null && product.containsKey('id')) {
                      _dispatchEvent(
                        SetProductInventoryEvent(
                          product['id'] as int,
                          quantity,
                        ),
                      );
                    }
                  } else {
                    final productId = DateTime.now().millisecondsSinceEpoch;
                    _dispatchEvent(AddProductEvent(productId, name, price));
                    if (quantity != null) {
                      _dispatchEvent(
                        SetProductInventoryEvent(productId, quantity),
                      );
                    }
                  }
                  Navigator.pop(context);
                }
              },
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        );
      },
    );
  }

  /// Shows a dialog for adding or editing a customer.
  Future<void> _showCustomerDialog({Map<String, dynamic>? customer}) async {
    final isEdit = customer != null;
    final nameController = TextEditingController(
      text: isEdit ? customer['name'] as String : '',
    );
    final balanceController = TextEditingController(
      text:
          isEdit && customer.containsKey('balance')
              ? customer['balance'].toString()
              : '',
    );
    await showDialog(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: Text(isEdit ? 'Edit Customer' : 'Add Customer'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: nameController,
                decoration: const InputDecoration(labelText: 'Customer Name'),
              ),
              TextField(
                controller: balanceController,
                decoration: const InputDecoration(labelText: 'Balance'),
                keyboardType: TextInputType.number,
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            ElevatedButton(
              onPressed: () {
                final name = nameController.text;
                final balance = double.tryParse(balanceController.text);
                if (name.isNotEmpty && (balance != null || !isEdit)) {
                  if (isEdit) {
                    if (name != customer['name']) {
                      _dispatchEvent(
                        UpdateCustomerEvent(customer['id'] as int, name),
                      );
                    }
                    if (balance != null && customer.containsKey('id')) {
                      _dispatchEvent(
                        UpdateCustomerBalanceEvent(
                          customer['id'] as int,
                          balance,
                        ),
                      );
                    }
                  } else {
                    final customerId = DateTime.now().millisecondsSinceEpoch;
                    _dispatchEvent(AddCustomerEvent(customerId, name));
                    if (balance != null) {
                      _dispatchEvent(
                        UpdateCustomerBalanceEvent(customerId, balance),
                      );
                    }
                  }
                  Navigator.pop(context);
                }
              },
              child: Text(isEdit ? 'Save' : 'Add'),
            ),
          ],
        );
      },
    );
  }

  /// Shows a full-screen dialog listing previous orders for a customer.
  void _showCustomerOrders(BuildContext context, int customerId) async {
    await showDialog(
      context: context,
      builder: (context) {
        return Dialog(
          insetPadding: EdgeInsets.zero,
          backgroundColor: Colors.transparent,
          child: Container(
            width: double.infinity,
            height: MediaQuery.of(context).size.height,
            color: Theme.of(context).scaffoldBackgroundColor,
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Previous Orders'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.of(context).pop(),
                ),
              ),
              body: Padding(
                padding: const EdgeInsets.all(16.0),
                child: ValueListenableBuilder<ResultSet>(
                  valueListenable: widget.store.watch(
                    'SELECT o.id, o.order_date, o.refunded, o.completed, SUM(oi.product_price * oi.quantity) as total '
                    'FROM orders o LEFT JOIN order_items oi ON o.id = oi.order_id '
                    'WHERE o.customer_id = ? GROUP BY o.id, o.order_date, o.refunded, o.completed ORDER BY o.order_date DESC',
                    [customerId],
                  ),
                  builder: (context, orders, child) {
                    if (orders.isEmpty) {
                      return const Center(child: Text('No previous orders.'));
                    }
                    return ListView.builder(
                      itemCount: orders.length,
                      itemBuilder: (context, index) {
                        final order = orders[index];
                        final dateStr = order['order_date'] as String;
                        DateTime? date;
                        try {
                          date = DateTime.parse(dateStr);
                        } catch (_) {
                          date = null;
                        }
                        final total = order['total'] as num? ?? 0.0;
                        final refunded =
                            (order['refunded'] == 1 ||
                                order['refunded'] == true);
                        final completed =
                            (order['completed'] == 1 ||
                                order['completed'] == true);
                        return Card(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          child: ListTile(
                            title: Text('Order #${order['id']}'),
                            subtitle: Text(
                              'Date: ${date != null ? date.toLocal().toString() : dateStr}\nTotal:  24${total.toStringAsFixed(2)}\nStatus: '
                              '${refunded
                                  ? 'Refunded'
                                  : completed
                                  ? 'Completed'
                                  : 'Open'}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (completed && !refunded)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.undo,
                                      color: Colors.red,
                                    ),
                                    tooltip: 'Refund Order',
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _refundOrder(order['id'] as int);
                                    },
                                  ),
                                if (completed && refunded)
                                  IconButton(
                                    icon: const Icon(
                                      Icons.restore,
                                      color: Colors.green,
                                    ),
                                    tooltip: 'Restore Order',
                                    onPressed: () {
                                      Navigator.of(context).pop();
                                      _restoreOrder(order['id'] as int);
                                    },
                                  ),
                              ],
                            ),
                          ),
                        );
                      },
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  /// Builds the main scaffold and navigation for the POS app.
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        centerTitle: false,
        title: Text(switch (_selectedNavIndex) {
          0 => 'Customer Management',
          1 => 'Product Management',
          2 => 'Cart',
          _ => 'POS Example',
        }),
        actions: [
          if (_selectedNavIndex == 0)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Customer',
              onPressed: () => _showCustomerDialog(),
            ),
          if (_selectedNavIndex == 1)
            IconButton(
              icon: const Icon(Icons.add),
              tooltip: 'Add Product',
              onPressed: () => _showProductDialog(),
            ),
          IconButton(
            icon: const Icon(Icons.history),
            tooltip: 'Event History',
            onPressed: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                  builder:
                      (context) => PosEventHistoryScreen(store: widget.store),
                  fullscreenDialog: true,
                ),
              );
            },
          ),
        ],
      ),
      body: switch (_selectedNavIndex) {
        0 => _buildCustomersTab(context),
        1 => _buildProductsTab(context),
        2 => _buildCartTab(context),
        _ => _buildCustomersTab(context),
      },
      bottomNavigationBar: NavigationBar(
        selectedIndex: _selectedNavIndex,
        onDestinationSelected: _onNavBarTap,
        destinations: const [
          NavigationDestination(icon: Icon(Icons.person), label: 'Customers'),
          NavigationDestination(icon: Icon(Icons.inventory), label: 'Products'),
          NavigationDestination(icon: Icon(Icons.shopping_cart), label: 'Cart'),
        ],
      ),
    );
  }

  /// Builds the Customers tab, showing all customers and their info.
  Widget _buildCustomersTab(BuildContext context) {
    return ValueListenableBuilder<ResultSet>(
      valueListenable: widget.store.watch('SELECT * FROM customers'),
      builder: (context, customers, child) {
        if (customers.isEmpty) {
          return const Center(child: Text('No customers found.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: customers.length,
          itemBuilder: (context, index) {
            final customer = customers[index];
            return ListTile(
              title: Text(customer['name'] as String),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ValueListenableBuilder<ResultSet>(
                    valueListenable: widget.store.watch(
                      'SELECT COUNT(*) as order_count FROM orders WHERE customer_id = ?',
                      [customer['id']],
                    ),
                    builder: (context, orders, child) {
                      final count =
                          orders.isNotEmpty ? orders.first['order_count'] : 0;
                      return Text('Orders: $count');
                    },
                  ),
                  ValueListenableBuilder<ResultSet>(
                    valueListenable: widget.store.watch(
                      'SELECT balance FROM balances WHERE customer_id = ?',
                      [customer['id']],
                    ),
                    builder: (context, balances, child) {
                      final balance =
                          balances.isNotEmpty
                              ? (balances.first['balance'] as num? ?? 0.0)
                              : 0.0;
                      return Text(
                        'Balance: \u0024${balance.toStringAsFixed(2)}',
                      );
                    },
                  ),
                ],
              ),
              trailing: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.history),
                    tooltip: 'View Orders',
                    onPressed:
                        () =>
                            _showCustomerOrders(context, customer['id'] as int),
                  ),
                  IconButton(
                    icon: const Icon(Icons.edit),
                    onPressed: () => _showCustomerDialog(customer: customer),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  /// Builds the Products tab, showing all products and inventory.
  Widget _buildProductsTab(BuildContext context) {
    return ValueListenableBuilder<ResultSet>(
      valueListenable: widget.store.watch('SELECT * FROM products'),
      builder: (context, products, child) {
        if (products.isEmpty) {
          return const Center(child: Text('No products found.'));
        }
        return ListView.builder(
          padding: const EdgeInsets.all(16.0),
          itemCount: products.length,
          itemBuilder: (context, index) {
            final product = products[index];
            return ListTile(
              title: Text(product['name'] as String),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Price: \$${product['price']}'),
                  ValueListenableBuilder<ResultSet>(
                    valueListenable: widget.store.watch(
                      'SELECT quantity FROM inventory WHERE product_id = ?',
                      [product['id']],
                    ),
                    builder: (context, inventory, child) {
                      final quantity =
                          inventory.isNotEmpty
                              ? (inventory.first['quantity'] as int? ?? 0)
                              : 0;
                      return Text('Inventory: $quantity');
                    },
                  ),
                ],
              ),
              trailing: IconButton(
                icon: const Icon(Icons.edit),
                onPressed: () => _showProductDialog(product: product),
              ),
            );
          },
        );
      },
    );
  }

  /// Builds the Cart tab, allowing order creation and item management.
  Widget _buildCartTab(BuildContext context) {
    if (_selectedCustomerId == null && _selectedOrderId == null) {
      // Show customer selection if none selected
      return Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Please select a customer to start an order.',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 16),
            ValueListenableBuilder<ResultSet>(
              valueListenable: widget.store.watch('SELECT * FROM customers'),
              builder: (context, customers, child) {
                if (customers.isEmpty) {
                  return const Text(
                    'No customers found. Add one in the Customers tab.',
                  );
                }
                return DropdownButtonFormField<int>(
                  decoration: const InputDecoration(
                    labelText: 'Select Customer',
                  ),
                  value: _selectedCustomerId,
                  items:
                      customers.map<DropdownMenuItem<int>>((row) {
                        return DropdownMenuItem(
                          value: row['id'] as int,
                          child: Text(row['name'] as String),
                        );
                      }).toList(),
                  onChanged: (value) {
                    setState(() => _selectedCustomerId = value);
                  },
                );
              },
            ),
            const SizedBox(height: 24),
            const Text(
              'Or go to the Customers tab to add a new customer.',
              style: TextStyle(fontSize: 14, color: Colors.grey),
            ),
          ],
        ),
      );
    }
    if (_selectedOrderId == null && _selectedCustomerId != null) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            ValueListenableBuilder<ResultSet>(
              valueListenable: widget.store.watch(
                "SELECT name FROM customers WHERE id = ?",
                [_selectedCustomerId!],
              ),
              builder: (context, customerData, child) {
                if (customerData.isEmpty) {
                  return const Text("Loading customer...");
                }
                return Text(
                  'Customer "${customerData.first['name']}" selected.',
                );
              },
            ),
            const SizedBox(height: 20),
            Wrap(
              children: [
                ElevatedButton(
                  onPressed: _startOrder,
                  child: const Text('Start New Order'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    setState(() => _selectedCustomerId = null);
                  },
                  child: const Text('Remove Customer'),
                ),
                const SizedBox(width: 12),
                OutlinedButton(
                  onPressed: () {
                    // Change customer: show a dialog with customer dropdown
                    showDialog(
                      context: context,
                      builder: (context) {
                        int? tempSelected = _selectedCustomerId;
                        return AlertDialog(
                          title: const Text('Change Customer'),
                          content: ValueListenableBuilder<ResultSet>(
                            valueListenable: widget.store.watch(
                              'SELECT * FROM customers',
                            ),
                            builder: (context, customers, child) {
                              if (customers.isEmpty) {
                                return const Text('No customers found.');
                              }
                              return DropdownButtonFormField<int>(
                                decoration: const InputDecoration(
                                  labelText: 'Select Customer',
                                ),
                                value: tempSelected,
                                items:
                                    customers.map<DropdownMenuItem<int>>((row) {
                                      return DropdownMenuItem(
                                        value: row['id'] as int,
                                        child: Text(row['name'] as String),
                                      );
                                    }).toList(),
                                onChanged: (value) {
                                  tempSelected = value;
                                },
                              );
                            },
                          ),
                          actions: [
                            TextButton(
                              onPressed: () => Navigator.pop(context),
                              child: const Text('Cancel'),
                            ),
                            ElevatedButton(
                              onPressed: () {
                                setState(
                                  () => _selectedCustomerId = tempSelected,
                                );
                                Navigator.pop(context);
                              },
                              child: const Text('Change'),
                            ),
                          ],
                        );
                      },
                    );
                  },
                  child: const Text('Change Customer'),
                ),
              ],
            ),
          ],
        ),
      );
    }

    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'Current Order (ID: ${_selectedOrderId ?? 'N/A'})',
            style: Theme.of(context).textTheme.headlineSmall,
          ),
          if (_selectedOrderId != null && _selectedCustomerId != null)
            ValueListenableBuilder<ResultSet>(
              valueListenable: widget.store.watch(
                "SELECT name FROM customers WHERE id = ?",
                [_selectedCustomerId!],
              ),
              builder: (context, customerData, child) {
                if (customerData.isEmpty) return const SizedBox.shrink();
                return Text(
                  'For Customer: ${customerData.first['name']}',
                  style: Theme.of(context).textTheme.titleMedium,
                );
              },
            ),
          const SizedBox(height: 20),
          ValueListenableBuilder<ResultSet>(
            valueListenable: widget.store.watch(
              'SELECT * FROM products',
            ), // Changed to ValueListenableBuilder
            builder: (context, products, child) {
              return DropdownButtonFormField(
                decoration: const InputDecoration(
                  labelText: 'Select Product to Add',
                ),
                value: _selectedProductId,
                items:
                    products.map((row) {
                      return DropdownMenuItem(
                        value: row['id'],
                        child: Text(row['name'] as String),
                      );
                    }).toList(),
                onChanged:
                    (value) =>
                        setState(() => _selectedProductId = value as int?),
              );
            },
          ),
          TextField(
            controller: _cartQuantityController,
            decoration: const InputDecoration(labelText: 'Quantity'),
            keyboardType: TextInputType.number,
          ),
          ElevatedButton(
            onPressed: _addItemToCart,
            child: const Text('Add to Cart'),
          ),
          const SizedBox(height: 10),
          Text('Order Items:', style: Theme.of(context).textTheme.titleMedium),
          Expanded(
            child: ValueListenableBuilder<ResultSet>(
              valueListenable: widget.store.watch(
                // Changed to ValueListenableBuilder
                'SELECT oi.*, p.name as product_name FROM order_items oi JOIN products p ON oi.product_id = p.id WHERE oi.order_id = ?',
                _selectedOrderId != null
                    ? [_selectedOrderId!]
                    : [
                      '_invalid_order_id_',
                    ], // Use a non-null placeholder if no order
              ),
              builder: (context, items, child) {
                if (_selectedOrderId == null) {
                  return const Center(child: Text("No active order."));
                }
                // if (items.isEmpty) return const Center(child: Text('No items in cart.')); // ValueListenable always has a value, check length
                if (items.isEmpty && _selectedOrderId != null) {
                  return const Center(child: Text('No items in cart.'));
                }

                double currentTotal = 0;
                for (var item in items) {
                  currentTotal +=
                      (item['product_price'] as double) *
                      (item['quantity'] as int);
                }

                return Column(
                  children: [
                    Expanded(
                      child: ListView.builder(
                        itemCount: items.length,
                        itemBuilder: (context, index) {
                          final item = items[index];
                          return ListTile(
                            title: Text(item['product_name'] as String),
                            subtitle: Text(
                              'Qty: ${item['quantity']} @ \$${item['product_price']} (Total: \$${(item['product_price'] as double) * (item['quantity'] as int)})',
                            ),
                          );
                        },
                      ),
                    ),
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8.0),
                      child: Text(
                        'Order Total: \$${currentTotal.toStringAsFixed(2)}',
                        style: Theme.of(context).textTheme.titleLarge,
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
          ElevatedButton(onPressed: _checkout, child: const Text('Checkout')),
        ],
      ),
    );
  }
}
