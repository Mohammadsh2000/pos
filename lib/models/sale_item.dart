class SaleItem {
  final int? productId;
  final String productName;
  final String barcode;
  final double price;
  final double purchasePrice;
  int quantity;

  SaleItem({
    this.productId,
    required this.productName,
    required this.barcode,
    required this.price,
    this.purchasePrice = 0,
    required this.quantity,
  });

  double get subtotal {
    return price * quantity;
  }

  double get profit {
    return (price - purchasePrice) * quantity;
  }

  Map<String, dynamic> toMap() {
    return {
      'product_id': productId,
      'product_name': productName,
      'barcode': barcode,
      'price': price,
      'purchase_price': purchasePrice,
      'quantity': quantity,
      'subtotal': subtotal,
      'profit': profit,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> m) {
    return SaleItem(
      productId: m['product_id'] as int?,
      productName: m['product_name'] as String,
      barcode: m['barcode'] as String,
      price: (m['price'] as num).toDouble(),
      purchasePrice: (m['purchase_price'] as num?)?.toDouble() ?? 0,
      quantity: m['quantity'] as int,
    );
  }
}
