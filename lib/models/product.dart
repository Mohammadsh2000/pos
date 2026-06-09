class Product {
  final int? id;
  final String name;
  final String barcode;
  final String category;
  final double price;
  final double purchasePrice;
  final int stock;

  const Product({
    this.id,
    required this.name,
    required this.barcode,
    required this.price,
    this.purchasePrice = 0,
    required this.stock,
    required this.category,
  });

  double get profitMargin => price - purchasePrice;

  Map<String, dynamic> toMap() {
    return {
      if (id != null) 'id': id,
      'name': name,
      'barcode': barcode,
      'price': price,
      'purchase_price': purchasePrice,
      'stock': stock,
      'category': category,
    };
  }

  factory Product.fromMap(Map<String, dynamic> m) {
    return Product(
      id: m['id'] as int?,
      name: m['name'] as String,
      barcode: m['barcode'] as String,
      price: (m['price'] as num).toDouble(),
      purchasePrice: (m['purchase_price'] as num?)?.toDouble() ?? 0,
      stock: m['stock'] as int,
      category: m['category'] as String? ?? '',
    );
  }
}
