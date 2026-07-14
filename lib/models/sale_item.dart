class SaleItem {
  final int? productId;
  final String productName;
  final String barcode;
  final double price;
  final double purchasePrice;
  double quantity;
  final String saleType;
  final double discountPercent;
  final int piecesPerCarton;
  final bool sellAsCarton;

  SaleItem({
    this.productId,
    required this.productName,
    required this.barcode,
    required this.price,
    this.purchasePrice = 0,
    required this.quantity,
    this.saleType = 'unit',
    this.discountPercent = 0,
    this.piecesPerCarton = 1,
    this.sellAsCarton = false,
  });

  bool get isKg => saleType == 'kg';

  bool get isCarton => sellAsCarton;

  String get unitLabel => isCarton ? 'كرتونة' : (isKg ? 'كجم' : 'عدد');

  double get discountedPrice => price * (1 - discountPercent / 100);

  double get qtyInPieces => isCarton ? quantity * piecesPerCarton : quantity;

  double get subtotal {
    return discountedPrice * quantity;
  }

  double get savedAmount {
    return (price - discountedPrice) * quantity;
  }

  double get profit {
    final costPrice = isCarton ? purchasePrice : (piecesPerCarton > 0 ? purchasePrice / piecesPerCarton : purchasePrice);
    return (discountedPrice - costPrice) * quantity;
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
      'discount_percent': discountPercent,
      'pieces_per_carton': piecesPerCarton,
      'sell_as_carton': sellAsCarton,
      'subtotal': subtotal,
      'profit': profit,
    };
  }

  factory SaleItem.fromMap(Map<String, dynamic> m) {
    final hasSellAsCarton = m.containsKey('sell_as_carton');
    final sellAsCartonValue = (m['sell_as_carton'] as bool?) ?? false;
    return SaleItem(
      productId: m['product_id'] as int?,
      productName: m['product_name'] as String,
      barcode: m['barcode'] as String,
      price: (m['price'] as num).toDouble(),
      purchasePrice: (m['purchase_price'] as num?)?.toDouble() ?? 0,
      quantity: (m['quantity'] as num).toDouble(),
      saleType: m['sale_type'] as String? ?? 'unit',
      discountPercent: (m['discount_percent'] as num?)?.toDouble() ?? 0,
      piecesPerCarton: (m['pieces_per_carton'] as int?) ?? 1,
      sellAsCarton: hasSellAsCarton ? sellAsCartonValue : (m['sale_type'] == 'carton'),
    );
  }
}
