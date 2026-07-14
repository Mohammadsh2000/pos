class AdjustmentEntry {
  final int productId;
  final String productName;
  final double systemQty;
  final double actualQty;
  final double costAtTime;

  const AdjustmentEntry({
    required this.productId,
    required this.productName,
    required this.systemQty,
    required this.actualQty,
    required this.costAtTime,
  });

  double get difference => actualQty - systemQty;
  double get financialValue => difference * costAtTime;

  Map<String, dynamic> toMap() => {
    'product_id': productId,
    'product_name': productName,
    'system_qty': systemQty,
    'actual_qty': actualQty,
    'difference': difference,
    'cost_at_time': costAtTime,
  };

  factory AdjustmentEntry.fromMap(Map<String, dynamic> m) => AdjustmentEntry(
    productId: m['product_id'] as int,
    productName: m['product_name'] as String,
    systemQty: (m['system_qty'] as num).toDouble(),
    actualQty: (m['actual_qty'] as num).toDouble(),
    costAtTime: (m['cost_at_time'] as num).toDouble(),
  );
}
