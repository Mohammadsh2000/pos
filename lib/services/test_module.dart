import '../models/product.dart';
import '../models/sale_item.dart';
import '../models/stock_in_entry.dart';
import 'database_helper.dart';

class TestScenario {
  final String name;
  final bool passed;
  final String expected;
  final String actual;
  final String? details;

  const TestScenario({
    required this.name,
    required this.passed,
    required this.expected,
    required this.actual,
    this.details,
  });
}

class TestModule {
  final DatabaseHelper _db = DatabaseHelper();
  final List<TestScenario> _results = [];
  final List<int> _productIds = [];
  final List<int> _saleIds = [];
  int? _testCustomerId;

  List<TestScenario> get results => List.unmodifiable(_results);
  int get passedCount => _results.where((r) => r.passed).length;
  int get totalCount => _results.length;

  Future<List<TestScenario>> runAllTests() async {
    _results.clear();
    _productIds.clear();
    _saleIds.clear();
    _testCustomerId = null;

    try {
      await _cleanupExistingTestData();
    } catch (_) {}

    try {
      await _test1_initialStockIn();
      await _test2_additionalStockIn();
      await _test3_saleProfit();
      await _test4_saleDifferentPrice();
      await _test5_stockInAfterSales();
      await _test6_zeroInitialStock();
      await _test7_kgProduct();
      await _test8_debtCreation();
      await _test9_largeNumbersPrecision();
      await _test10_multipleStockIns();
    } catch (e) {
      _error('خطأ عام في الاختبارات', e);
    }

    return List.from(_results);
  }

  Future<void> cleanupTestData() async {
    final db = await _db.database;
    for (final saleId in _saleIds) {
      await db.delete('sales', where: 'id = ?', whereArgs: [saleId]);
    }
    if (_testCustomerId != null) {
      await db.delete('debt_payments',
          where: 'customer_id = ?', whereArgs: [_testCustomerId]);
      await db.update('sales',
          {'customer_id': null, 'customer_name': null},
          where: 'customer_id = ?', whereArgs: [_testCustomerId]);
      await db.delete('customers', where: 'id = ?', whereArgs: [_testCustomerId]);
    }
    for (final pid in _productIds) {
      await db.delete('products', where: 'id = ?', whereArgs: [pid]);
    }
    await db.delete('purchases',
        where: 'id NOT IN (SELECT DISTINCT purchase_id FROM purchase_items)');
  }

  Future<void> _cleanupExistingTestData() async {
    final db = await _db.database;
    final testBarcodes = [
      'TEST-001', 'TEST-002', 'TEST-003', 'TEST-004', 'TEST-005'
    ];
    for (final barcode in testBarcodes) {
      final r = await db.query('products',
          where: 'barcode = ?', whereArgs: [barcode], limit: 1);
      if (r.isEmpty) continue;
      final name = r.first['name'] as String? ?? '';
      if (!name.startsWith('TEST-')) continue;
      final pid = r.first['id'] as int;
      await db.delete('purchase_items',
          where: 'product_id = ?', whereArgs: [pid]);
      await db.delete('products', where: 'id = ?', whereArgs: [pid]);
    }
    final cust = await db.query('customers',
        where: 'name = ?', whereArgs: ['TEST-عميل'], limit: 1);
    if (cust.isNotEmpty) {
      final cid = cust.first['id'] as int;
      await db.delete('debt_payments',
          where: 'customer_id = ?', whereArgs: [cid]);
      await db.update('sales',
          {'customer_id': null, 'customer_name': null},
          where: 'customer_id = ?', whereArgs: [cid]);
      await db.delete('customers', where: 'id = ?', whereArgs: [cid]);
    }
    await db.delete('purchases',
        where: 'id NOT IN (SELECT DISTINCT purchase_id FROM purchase_items)');
  }

  Future<int> _insertProduct(Product p) async {
    final id = await _db.insertProduct(p);
    _productIds.add(id);
    return id;
  }

  Future<Map<String, dynamic>> _getProduct(int id) async {
    final db = await _db.database;
    final r = await db.query('products',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return r.first;
  }

  double _computeWac(
      double oldStock, double oldCost, double newQty, double newCost) {
    final stockAfter = oldStock + newQty;
    if (stockAfter <= 0) return newCost;
    final totalValue = oldStock * oldCost + newQty * newCost;
    return double.parse((totalValue / stockAfter).toStringAsFixed(5));
  }

  bool _approxEqual(double a, double b, {double eps = 0.001}) =>
      (a - b).abs() < eps;

  String _fmt(double v) => v.toStringAsFixed(5);

  void _pass(String name, String expected, String actual, {String? details}) {
    _results.add(TestScenario(
        name: name,
        passed: true,
        expected: expected,
        actual: actual,
        details: details));
  }

  void _fail(String name, String expected, String actual, {String? details}) {
    _results.add(TestScenario(
        name: name,
        passed: false,
        expected: expected,
        actual: actual,
        details: details));
  }

  void _error(String name, dynamic e) {
    _results.add(TestScenario(
        name: name,
        passed: false,
        expected: 'بدون أخطاء',
        actual: 'خطأ: $e',
        details: e.toString()));
  }

  Future<int> _createSale(
      List<SaleItem> items, {int? customerId, String? customerName}) async {
    final total = items.fold(0.0, (s, i) => s + i.subtotal);
    final totalProfit = items.fold(0.0, (s, i) => s + i.profit);
    int? saleId;
    final db = await _db.database;
    await db.transaction((txn) async {
      saleId = await _db.saveSaleOn(txn, total, totalProfit, items,
          customerId: customerId, customerName: customerName);
      for (final item in items) {
        if (item.productId != null) {
          await _db.deductStockExec(txn, item.productId!, item.quantity);
        }
      }
    });
    if (saleId != null) _saleIds.add(saleId!);
    return saleId ?? -1;
  }

  Future<Map<String, dynamic>> _getSale(int id) async {
    final db = await _db.database;
    final r = await db.query('sales',
        where: 'id = ?', whereArgs: [id], limit: 1);
    return r.first;
  }

  // ─── Test 1 ───────────────────────────────────────────
  Future<void> _test1_initialStockIn() async {
    const n = '1. شراء أولي لمنتج — حساب متوسط التكلفة';
    try {
      final id = await _insertProduct(Product(
        name: 'TEST-منتج-أ',
        barcode: 'TEST-001',
        price: 100,
        purchasePrice: 0,
        stock: 0,
        category: 'اختبار',
      ));
      await _db.createPurchase([
        StockInEntry(productId: id, productName: 'TEST-منتج-أ', quantity: 10, cost: 50),
      ]);
      final p = await _getProduct(id);
      final stock = (p['stock'] as num).toDouble();
      final wac = (p['purchase_price'] as num).toDouble();
      if (_approxEqual(stock, 10) && _approxEqual(wac, 50)) {
        _pass(n, 'مخزون=10, تكلفة=50', 'مخزون=$stock, تكلفة=${_fmt(wac)}');
      } else {
        _fail(n, 'مخزون=10, تكلفة=50',
            'مخزون=${_fmt(stock)}, تكلفة=${_fmt(wac)}');
      }
    } catch (e) {
      _error(n, e);
    }
  }

  // ─── Test 2 ───────────────────────────────────────────
  Future<void> _test2_additionalStockIn() async {
    const n = '2. شراء إضافي لنفس المنتج — تحديث WAC';
    try {
      final pid = _productIds[0];
      final before = await _getProduct(pid);
      final oldStock = (before['stock'] as num).toDouble();
      final oldWac = (before['purchase_price'] as num).toDouble();
      await _db.createPurchase([
        StockInEntry(productId: pid, productName: 'TEST-منتج-أ', quantity: 5, cost: 60),
      ]);
      final p = await _getProduct(pid);
      final stock = (p['stock'] as num).toDouble();
      final wac = (p['purchase_price'] as num).toDouble();
      final expected = _computeWac(oldStock, oldWac, 5, 60);
      if (_approxEqual(stock, 15) && _approxEqual(wac, expected)) {
        _pass(n, 'مخزون=15, تكلفة=${_fmt(expected)}',
            'مخزون=$stock, تكلفة=${_fmt(wac)}');
      } else {
        _fail(n, 'مخزون=15, تكلفة=${_fmt(expected)}',
            'مخزون=${_fmt(stock)}, تكلفة=${_fmt(wac)}',
            details: 'قديم: مخزون=$oldStock, تكلفة=${_fmt(oldWac)}');
      }
    } catch (e) {
      _error(n, e);
    }
  }

  // ─── Test 3 ───────────────────────────────────────────
  Future<void> _test3_saleProfit() async {
    const n = '3. عملية بيع — حساب الربح';
    try {
      final pid = _productIds[0];
      final p = await _getProduct(pid);
      final wac = (p['purchase_price'] as num).toDouble();
      final saleId = await _createSale([
        SaleItem(
          productId: pid,
          productName: 'TEST-منتج-أ',
          barcode: 'TEST-001',
          price: 80,
          purchasePrice: wac,
          quantity: 3,
        ),
      ]);
      final prod = await _getProduct(pid);
      final stock = (prod['stock'] as num).toDouble();
      final sale = await _getSale(saleId);
      final profit = (sale['total_profit'] as num).toDouble();
      final expectedProfit = (80 - wac) * 3;
      final stockOk = _approxEqual(stock, 12);
      final profitOk = _approxEqual(profit, expectedProfit);
      if (stockOk && profitOk) {
        _pass(n, 'مخزون=12, ربح=${_fmt(expectedProfit)}',
            'مخزون=$stock, ربح=${_fmt(profit)}');
      } else {
        _fail(n, 'مخزون=12, ربح=${_fmt(expectedProfit)}',
            'مخزون=${_fmt(stock)}, ربح=${_fmt(profit)}',
            details: 'WAC لحظة البيع=${_fmt(wac)}');
      }
    } catch (e) {
      _error(n, e);
    }
  }

  // ─── Test 4 ───────────────────────────────────────────
  Future<void> _test4_saleDifferentPrice() async {
    const n = '4. عملية بيع بسعر مختلف — ربح مختلف';
    try {
      final pid = _productIds[0];
      final p = await _getProduct(pid);
      final wac = (p['purchase_price'] as num).toDouble();
      final stockBefore = (p['stock'] as num).toDouble();
      final saleId = await _createSale([
        SaleItem(
          productId: pid,
          productName: 'TEST-منتج-أ',
          barcode: 'TEST-001',
          price: 90,
          purchasePrice: wac,
          quantity: 2,
        ),
      ]);
      final prod = await _getProduct(pid);
      final stock = (prod['stock'] as num).toDouble();
      final sale = await _getSale(saleId);
      final profit = (sale['total_profit'] as num).toDouble();
      final expectedProfit = (90 - wac) * 2;
      final expectedStock = stockBefore - 2;
      final ok = _approxEqual(stock, expectedStock) &&
          _approxEqual(profit, expectedProfit);
      if (ok) {
        _pass(n, 'مخزون=${_fmt(expectedStock)}, ربح=${_fmt(expectedProfit)}',
            'مخزون=${_fmt(stock)}, ربح=${_fmt(profit)}');
      } else {
        _fail(n, 'مخزون=${_fmt(expectedStock)}, ربح=${_fmt(expectedProfit)}',
            'مخزون=${_fmt(stock)}, ربح=${_fmt(profit)}',
            details: 'WAC=${_fmt(wac)}');
      }
    } catch (e) {
      _error(n, e);
    }
  }

  // ─── Test 5 ───────────────────────────────────────────
  Future<void> _test5_stockInAfterSales() async {
    const n = '5. شراء بعد عمليات البيع — تحديث WAC';
    try {
      final pid = _productIds[0];
      final before = await _getProduct(pid);
      final oldStock = (before['stock'] as num).toDouble();
      final oldWac = (before['purchase_price'] as num).toDouble();
      await _db.createPurchase([
        StockInEntry(productId: pid, productName: 'TEST-منتج-أ', quantity: 10, cost: 55),
      ]);
      final p = await _getProduct(pid);
      final stock = (p['stock'] as num).toDouble();
      final wac = (p['purchase_price'] as num).toDouble();
      final expected = _computeWac(oldStock, oldWac, 10, 55);
      if (_approxEqual(stock, 20) && _approxEqual(wac, expected)) {
        _pass(n, 'مخزون=20, تكلفة=${_fmt(expected)}',
            'مخزون=$stock, تكلفة=${_fmt(wac)}');
      } else {
        _fail(n, 'مخزون=20, تكلفة=${_fmt(expected)}',
            'مخزون=${_fmt(stock)}, تكلفة=${_fmt(wac)}',
            details: 'قبل: مخزون=$oldStock, تكلفة=${_fmt(oldWac)}');
      }
    } catch (e) {
      _error(n, e);
    }
  }

  // ─── Test 6 ───────────────────────────────────────────
  Future<void> _test6_zeroInitialStock() async {
    const n = '6. منتج جديد بدون مخزون — شراء أولي';
    try {
      final id = await _insertProduct(Product(
        name: 'TEST-منتج-ب',
        barcode: 'TEST-002',
        price: 200,
        purchasePrice: 0,
        stock: 0,
        category: 'اختبار',
      ));
      await _db.createPurchase([
        StockInEntry(productId: id, productName: 'TEST-منتج-ب', quantity: 20, cost: 30),
      ]);
      final p = await _getProduct(id);
      final stock = (p['stock'] as num).toDouble();
      final wac = (p['purchase_price'] as num).toDouble();
      if (_approxEqual(stock, 20) && _approxEqual(wac, 30)) {
        _pass(n, 'مخزون=20, تكلفة=30',
            'مخزون=$stock, تكلفة=${_fmt(wac)}');
      } else {
        _fail(n, 'مخزون=20, تكلفة=30',
            'مخزون=${_fmt(stock)}, تكلفة=${_fmt(wac)}');
      }
    } catch (e) {
      _error(n, e);
    }
  }

  // ─── Test 7 ───────────────────────────────────────────
  Future<void> _test7_kgProduct() async {
    const n = '7. منتج وزني (كجم) — شراء وبيع';
    try {
      final id = await _insertProduct(Product(
        name: 'TEST-منتج-ج',
        barcode: 'TEST-003',
        price: 50,
        purchasePrice: 0,
        stock: 0,
        category: 'اختبار',
        saleType: 'kg',
      ));
      await _db.createPurchase([
        StockInEntry(productId: id, productName: 'TEST-منتج-ج', quantity: 25, cost: 20),
      ]);
      final p = await _getProduct(id);
      final stock = (p['stock'] as num).toDouble();
      final wac = (p['purchase_price'] as num).toDouble();
      if (_approxEqual(stock, 25) && _approxEqual(wac, 20)) {
        _pass(n, 'مخزون=25, تكلفة=20',
            'مخزون=$stock, تكلفة=${_fmt(wac)}');
      } else {
        _fail(n, 'مخزون=25, تكلفة=20',
            'مخزون=${_fmt(stock)}, تكلفة=${_fmt(wac)}');
      }
    } catch (e) {
      _error(n, e);
    }
  }

  // ─── Test 8 ───────────────────────────────────────────
  Future<void> _test8_debtCreation() async {
    const n = '8. إنشاء دين — بيع لعميل';
    try {
      final pid = _productIds[1]; // TEST-002
      final p = await _getProduct(pid);
      final wac = (p['purchase_price'] as num).toDouble();
      final stockBefore = (p['stock'] as num).toDouble();
      final customerName = 'TEST-عميل';
      final customerId = await _db.upsertCustomer(customerName);
      _testCustomerId = customerId;

      final saleId = await _createSale([
        SaleItem(
          productId: pid,
          productName: 'TEST-منتج-ب',
          barcode: 'TEST-002',
          price: 200,
          purchasePrice: wac,
          quantity: 5,
        ),
      ], customerId: customerId, customerName: customerName);

      final prod = await _getProduct(pid);
      final stock = (prod['stock'] as num).toDouble();
      final sale = await _getSale(saleId);
      final saleTotal = (sale['total'] as num).toDouble();
      final expectedTotal = 5.0 * 200;
      final expectedStock = stockBefore - 5.0;

      final customers = await _db.getCustomersWithDebts();
      final custRow = customers.firstWhere(
          (c) => c['id'] == customerId, orElse: () => <String, dynamic>{});
      final debtAmount = (custRow['total_debt'] as num?)?.toDouble() ?? 0;
      final paidAmount = (custRow['total_paid'] as num?)?.toDouble() ?? 0;
      final remaining = debtAmount - paidAmount;

      final stockOk = _approxEqual(stock, expectedStock);
      final totalOk = _approxEqual(saleTotal, expectedTotal);
      final debtOk = _approxEqual(debtAmount, expectedTotal);

      if (stockOk && totalOk && debtOk) {
        _pass(n, 'مخزون=$expectedStock, قيمة=1000, دين=1000',
            'مخزون=${_fmt(stock)}, قيمة=${_fmt(saleTotal)}, دين=${_fmt(debtAmount)}');
      } else {
        _fail(n, 'مخزون=$expectedStock, قيمة=1000, دين=1000',
            'مخزون=${_fmt(stock)}, قيمة=${_fmt(saleTotal)}, دين=${_fmt(debtAmount)}',
            details: 'WAC=${_fmt(wac)}, المتبقي=$remaining');
      }
    } catch (e) {
      _error(n, e);
    }
  }

  // ─── Test 9 ───────────────────────────────────────────
  Future<void> _test9_largeNumbersPrecision() async {
    const n = '9. دقة الأعداد الكبيرة — كميات صغيرة';
    try {
      final id = await _insertProduct(Product(
        name: 'TEST-منتج-د',
        barcode: 'TEST-004',
        price: 10,
        purchasePrice: 0,
        stock: 0,
        category: 'اختبار',
      ));
      await _db.createPurchase([
        StockInEntry(productId: id, productName: 'TEST-منتج-د', quantity: 100, cost: 0.75),
      ]);
      var p = await _getProduct(id);
      var stock = (p['stock'] as num).toDouble();
      var wac = (p['purchase_price'] as num).toDouble();
      if (!_approxEqual(stock, 100) || !_approxEqual(wac, 0.75)) {
        _fail(n, 'الشراء الأول: مخزون=100, تكلفة=0.75',
            'مخزون=${_fmt(stock)}, تكلفة=${_fmt(wac)}');
        return;
      }
      await _db.createPurchase([
        StockInEntry(productId: id, productName: 'TEST-منتج-د', quantity: 50, cost: 1.25),
      ]);
      p = await _getProduct(id);
      stock = (p['stock'] as num).toDouble();
      wac = (p['purchase_price'] as num).toDouble();
      final expected = _computeWac(100, 0.75, 50, 1.25);
      if (_approxEqual(stock, 150) && _approxEqual(wac, expected)) {
        _pass(n, 'مخزون=150, تكلفة=${_fmt(expected)}',
            'مخزون=$stock, تكلفة=${_fmt(wac)}');
      } else {
        _fail(n, 'الشراء الثاني: مخزون=150, تكلفة=${_fmt(expected)}',
            'مخزون=${_fmt(stock)}, تكلفة=${_fmt(wac)}');
      }
    } catch (e) {
      _error(n, e);
    }
  }

  // ─── Test 10 ──────────────────────────────────────────
  Future<void> _test10_multipleStockIns() async {
    const n = '10. مشتريين متتاليين — حساب WAC';
    try {
      final id = await _insertProduct(Product(
        name: 'TEST-منتج-هـ',
        barcode: 'TEST-005',
        price: 40,
        purchasePrice: 0,
        stock: 0,
        category: 'اختبار',
      ));
      await _db.createPurchase([
        StockInEntry(productId: id, productName: 'TEST-منتج-هـ', quantity: 7, cost: 15),
      ]);
      var p = await _getProduct(id);
      var stock = (p['stock'] as num).toDouble();
      var wac = (p['purchase_price'] as num).toDouble();
      if (!_approxEqual(stock, 7) || !_approxEqual(wac, 15)) {
        _fail(n, 'الشراء الأول: مخزون=7, تكلفة=15',
            'مخزون=${_fmt(stock)}, تكلفة=${_fmt(wac)}');
        return;
      }
      await _db.createPurchase([
        StockInEntry(productId: id, productName: 'TEST-منتج-هـ', quantity: 3, cost: 25),
      ]);
      p = await _getProduct(id);
      stock = (p['stock'] as num).toDouble();
      wac = (p['purchase_price'] as num).toDouble();
      final expected = _computeWac(7, 15, 3, 25);
      if (_approxEqual(stock, 10) && _approxEqual(wac, expected)) {
        _pass(n, 'مخزون=10, تكلفة=$expected',
            'مخزون=$stock, تكلفة=${_fmt(wac)}');
      } else {
        _fail(n, 'الشراء الثاني: مخزون=10, تكلفة=$expected',
            'مخزون=${_fmt(stock)}, تكلفة=${_fmt(wac)}');
      }
    } catch (e) {
      _error(n, e);
    }
  }
}
