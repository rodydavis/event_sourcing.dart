import 'package:event_sourcing/event_sourcing.dart';

class PosEvent extends Event {
  static var _hlc = Hlc.now('node1');

  PosEvent(String type, [Map<String, Object?> data = const {}])
    : super(id: _hlc = _hlc.increment(), type: type, data: {...data});
}

class AddCustomerEvent extends PosEvent {
  AddCustomerEvent(this.customerId, this.name)
    : super('ADD_CUSTOMER', {'customerId': customerId, 'name': name});

  final int customerId;
  final String name;
}

class UpdateCustomerEvent extends PosEvent {
  UpdateCustomerEvent(this.customerId, this.name)
    : super('UPDATE_CUSTOMER', {'customerId': customerId, 'name': name});

  final int customerId;
  final String name;
}

class DeleteCustomerEvent extends PosEvent {
  DeleteCustomerEvent(this.customerId)
    : super('DELETE_CUSTOMER', {'customerId': customerId});

  final int customerId;
}

class AddProductEvent extends PosEvent {
  AddProductEvent(this.productId, this.name, this.price)
    : super('ADD_PRODUCT', {
        'productId': productId,
        'name': name,
        'price': price,
      });

  final int productId;
  final String name;
  final double price;
}

class UpdateProductNameEvent extends PosEvent {
  UpdateProductNameEvent(this.productId, this.name)
    : super('UPDATE_PRODUCT_NAME', {'productId': productId, 'name': name});

  final int productId;
  final String name;
}

class UpdateProductPriceEvent extends PosEvent {
  UpdateProductPriceEvent(this.productId, this.price)
    : super('UPDATE_PRODUCT_PRICE', {'productId': productId, 'price': price});

  final int productId;
  final double price;
}

class DeleteProductEvent extends PosEvent {
  DeleteProductEvent(this.productId)
    : super('DELETE_PRODUCT', {'productId': productId});

  final int productId;
}

class SetProductInventoryEvent extends PosEvent {
  SetProductInventoryEvent(this.productId, this.quantity)
    : super('SET_PRODUCT_INVENTORY', {
        'productId': productId,
        'quantity': quantity,
      });

  final int productId;
  final int quantity;
}

class StartOrderEvent extends PosEvent {
  StartOrderEvent(this.orderId, this.customerId)
    : super('START_ORDER', {'orderId': orderId, 'customerId': customerId});

  final int orderId;
  final int customerId;
}

class AddProductToOrderEvent extends PosEvent {
  AddProductToOrderEvent(this.orderId, this.productId, this.quantity)
    : super('ADD_PRODUCT_TO_ORDER', {
        'orderId': orderId,
        'productId': productId,
        'quantity': quantity,
      });

  final int orderId;
  final int productId;
  final int quantity;
}

class RemoveProductFromOrderEvent extends PosEvent {
  RemoveProductFromOrderEvent(this.orderId, this.productId)
    : super('REMOVE_PRODUCT_FROM_ORDER', {
        'orderId': orderId,
        'productId': productId,
      });

  final int orderId;
  final int productId;
}

class IncreaseProductQuantityEvent extends PosEvent {
  IncreaseProductQuantityEvent(this.orderId, this.productId, this.quantity)
    : super('INCREASE_PRODUCT_QUANTITY', {
        'orderId': orderId,
        'productId': productId,
        'quantity': quantity,
      });

  final int orderId;
  final int productId;
  final int quantity;
}

class DecreaseProductQuantityEvent extends PosEvent {
  DecreaseProductQuantityEvent(this.orderId, this.productId, this.quantity)
    : super('DECREASE_PRODUCT_QUANTITY', {
        'orderId': orderId,
        'productId': productId,
        'quantity': quantity,
      });

  final int orderId;
  final int productId;
  final int quantity;
}

class UpdateCustomerBalanceEvent extends PosEvent {
  UpdateCustomerBalanceEvent(this.customerId, this.balance)
    : super('UPDATE_CUSTOMER_BALANCE', {
        'customerId': customerId,
        'balance': balance,
      });

  final int customerId;
  final double balance;
}

class CompleteOrderEvent extends PosEvent {
  CompleteOrderEvent(this.orderId)
    : super('COMPLETE_ORDER', {'orderId': orderId});

  final int orderId;
}

class CancelOrderEvent extends PosEvent {
  CancelOrderEvent(this.orderId) : super('CANCEL_ORDER', {'orderId': orderId});

  final int orderId;
}

class RefundOrderEvent extends PosEvent {
  RefundOrderEvent(this.orderId) : super('REFUND_ORDER', {'orderId': orderId});

  final int orderId;
}
