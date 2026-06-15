class Product {
  final int? id;
  final String name;
  final String barcode;
  final String category;
  final double price;
  final double purchasePrice;
  final double stock;
  final String saleType;

  const Product({
    this.id,
    required this.name,
    required this.barcode,
    required this.price,
    this.purchasePrice = 0,
    required this.stock,
    required this.category,
    this.saleType = 'unit',
  });

  double get profitMargin => price - purchasePrice;

  bool get isKg => saleType == 'kg';

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
    );
  }
}
