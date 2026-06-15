class SaleItem {
  final int? productId;
  final String productName;
  final String barcode;
  final double price;
  final double purchasePrice;
  double quantity;
  final String saleType;

  SaleItem({
    this.productId,
    required this.productName,
    required this.barcode,
    required this.price,
    this.purchasePrice = 0,
    required this.quantity,
    this.saleType = 'unit',
  });

  bool get isKg => saleType == 'kg';

  String get unitLabel => isKg ? 'كجم' : 'عدد';

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
      'sale_type': saleType,
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
      quantity: (m['quantity'] as num).toDouble(),
      saleType: m['sale_type'] as String? ?? 'unit',
    );
  }
}
