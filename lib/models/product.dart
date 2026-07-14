class Product {
  final int? id;
  final String name;
  final String barcode;
  final String category;
  final double price;
  final double purchasePrice;
  final double stock;
  final String saleType;
  final double discountPercent;
  final int piecesPerCarton;
  final double cartonPrice;
  final String secondaryBarcode;

  const Product({
    this.id,
    required this.name,
    required this.barcode,
    required this.price,
    this.purchasePrice = 0,
    required this.stock,
    required this.category,
    this.saleType = 'unit',
    this.discountPercent = 0,
    this.piecesPerCarton = 1,
    this.cartonPrice = 0,
    this.secondaryBarcode = '',
  });

  double get cartonProfitMargin => cartonPrice - purchasePrice;
  double get unitPurchaseCost => piecesPerCarton > 0 ? purchasePrice / piecesPerCarton : purchasePrice;

  bool get isKg => saleType == 'kg';

  bool get isCarton => saleType == 'carton';

  bool get hasCartonSale => isCarton || (piecesPerCarton > 1 && cartonPrice > 0);

  double get discountedPrice => price * (1 - discountPercent / 100);

  double get cartonDiscountedPrice => cartonPrice * (1 - discountPercent / 100);

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'barcode': barcode,
      'price': price,
      'purchase_price': purchasePrice,
      'stock': stock,
      'category': category,
      'sale_type': saleType,
      'discount_percent': discountPercent,
      'pieces_per_carton': piecesPerCarton,
      'carton_price': cartonPrice,
      'secondary_barcode': secondaryBarcode,
    };
  }

  factory Product.fromMap(Map<String, dynamic> m) {
    return Product(
      id: m['id'] as int?,
      name: m['name'] as String,
      barcode: m['barcode'] as String,
      price: (m['price'] as num).toDouble(),
      purchasePrice: (m['purchase_price'] as num?)?.toDouble() ?? 0,
      stock: (m['stock'] as num).toDouble(),
      category: m['category'] as String? ?? '',
      saleType: m['sale_type'] as String? ?? 'unit',
      discountPercent: (m['discount_percent'] as num?)?.toDouble() ?? 0,
      piecesPerCarton: (m['pieces_per_carton'] as int?) ?? 1,
      cartonPrice: (m['carton_price'] as num?)?.toDouble() ?? 0,
      secondaryBarcode: (m['secondary_barcode'] as String?) ?? '',
    );
  }
}
