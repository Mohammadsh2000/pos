import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../models/sale_item.dart';
import '../services/database_helper.dart';
import '../utils/excel_helpers.dart';

class POSProvider extends ChangeNotifier {
  final DatabaseHelper _db = DatabaseHelper();

  int _currentTab = 0;
  int get currentTab => _currentTab;
  void setTab(int i) {
    _currentTab = i;
    if (i != 0) {
      _isCameraActive = false;
    }
    notifyListeners();
  }

  double _todaySalesTotal = 0;
  int _todaySalesCount = 0;
  double get todaySalesTotal => _todaySalesTotal;
  int get todaySalesCount => _todaySalesCount;

  Future<void> loadDashboard() async {
    _todaySalesTotal = await _db.getTodaySalesTotal();
    _todaySalesCount = await _db.getTodaySalesCount();
    notifyListeners();
  }

  List<Product> _allProducts = [];
  List<Product> get allProducts => _allProducts;

  List<Product> _products = [];
  List<Product> get products => _products;

  final Map<String, Product> _productByBarcode = {};

  Product? findProductByBarcode(String barcode) => _productByBarcode[barcode];

  Future<void> loadProducts() async {
    _allProducts = await _db.getAllProducts();
    _productByBarcode
      ..clear()
      ..addEntries(_allProducts.map((p) => MapEntry(p.barcode, p)));
    _products = List.of(_allProducts);
    notifyListeners();
  }

  Future<void> searchProducts(String q) async {
    if (q.isEmpty) {
      _products = List.of(_allProducts);
    } else {
      _products = await _db.searchProducts(q);
    }
    notifyListeners();
  }

  Future<String?> addProduct(Product product) async {
    try {
      await _db.insertProduct(product);
      await loadProducts();
      return null;
    } on sqlite.DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        return 'الباركود مستخدم من قبل منتج آخر';
      }
      return 'تعذّر حفظ المنتج: ${e.toString().split('\n').first}';
    } catch (e) {
      return 'تعذّر حفظ المنتج: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> updateProduct(Product product) async {
    try {
      await _db.updateProduct(product);
      await loadProducts();
      return null;
    } on sqlite.DatabaseException catch (e) {
      if (e.isUniqueConstraintError()) {
        return 'الباركود مستخدم من قبل منتج آخر';
      }
      return 'تعذّر تحديث المنتج: ${e.toString().split('\n').first}';
    } catch (e) {
      return 'تعذّر تحديث المنتج: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> deleteProduct(int id) async {
    try {
      await _db.deleteProduct(id);
      await loadProducts();
      return null;
    } catch (e) {
      return 'تعذّر حذف المنتج';
    }
  }

  final List<SaleItem> _cart = [];
  List<SaleItem> get cart => _cart;

  double _cartTotal = 0.0;
  double get cartTotal => _cartTotal;
  int get cartItemsCount => _cart.length;

  void startNewSale() {
    _cart.clear();
    _recalcCartTotal();
    _lastScan = DateTime.fromMillisecondsSinceEpoch(0);
    _lastScanPerBarcode.clear();
    notifyListeners();
  }

  StockCheckResult canAddToCart(Product product, int quantity) {
    final existing = _cart.firstWhere(
      (i) => i.barcode == product.barcode,
      orElse: () => _emptyItem,
    );
    final inCart = existing.productName.isEmpty ? 0 : existing.quantity;
    final desired = inCart + quantity;
    if (product.stock <= 0) {
      return StockCheckResult.fail('المخزون نفد لهذا المنتج');
    }
    if (desired > product.stock) {
      return StockCheckResult.fail(
        'المخزون غير كافٍ: ${product.stock} متاح، المطلوب $desired',
      );
    }
    return StockCheckResult.ok();
  }

  static final SaleItem _emptyItem = SaleItem(
    productName: '',
    barcode: '',
    price: 0,
    quantity: 0,
  );

  bool addToCart(Product product) {
    return addToCartWithQuantity(product, 1);
  }

  bool addToCartWithQuantity(Product product, int quantity) {
    final check = canAddToCart(product, quantity);
    if (!check.ok) return false;
    final e = _cart.where((i) => i.barcode == product.barcode).firstOrNull;
    if (e != null) {
      e.quantity += quantity;
    } else {
      _cart.add(SaleItem(
        productId: product.id,
        productName: product.name,
        barcode: product.barcode,
        price: product.price,
        purchasePrice: product.purchasePrice,
        quantity: quantity,
      ));
    }
    _recalcCartTotal();
    notifyListeners();
    return true;
  }

  void removeFromCart(int i) {
    _cart.removeAt(i);
    _recalcCartTotal();
    notifyListeners();
  }

  void updateCartItemQuantity(int i, int q) {
    if (q <= 0) {
      _cart.removeAt(i);
    } else {
      _cart[i].quantity = q;
    }
    _recalcCartTotal();
    notifyListeners();
  }

  void _recalcCartTotal() {
    _cartTotal = _cart.fold(0.0, (s, i) => s + i.subtotal);
  }

  Future<Map<String, dynamic>?> completeSale() async {
    if (_cart.isEmpty) {
      return null;
    }
    final total = _cartTotal;
    final totalProfit = _cart.fold(0.0, (s, i) => s + i.profit);
    final items = List<SaleItem>.from(_cart);
    int? saleId;

    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        saleId = await _db.saveSaleOn(txn, total, totalProfit, _cart);
        for (final item in _cart) {
          if (item.productId != null) {
            await _db.deductStockExec(txn, item.productId!, item.quantity);
          }
        }
      });
    } on InsufficientStockException {
      return null;
    } catch (_) {
      return null;
    }

    if (saleId == null) {
      return null;
    }

    final completed = <String, dynamic>{
      'id': saleId,
      'total': total,
      'total_profit': totalProfit,
      'items_count': items.length,
      'items': jsonEncode(items.map((i) => i.toMap()).toList()),
      'created_at': DateTime.now().toIso8601String(),
    };

    await Future.wait([
      loadDashboard(),
      loadProducts(),
      loadSales(),
      loadStats(),
    ]);

    _cart.clear();
    _recalcCartTotal();
    _isCameraActive = false;
    notifyListeners();
    return completed;
  }

  bool _isCameraActive = false;
  bool get isCameraActive => _isCameraActive;

  void setCameraActive(bool v) {
    _isCameraActive = v;
    notifyListeners();
  }

  DateTime _lastScan = DateTime.fromMillisecondsSinceEpoch(0);
  static const Duration _scanDebounceWindow = Duration(milliseconds: 100);
  final Map<String, DateTime> _lastScanPerBarcode = {};
  static const Duration _sameBarcodeCooldown = Duration(milliseconds: 1500);

  bool canScanBarcode(String barcode) {
    final now = DateTime.now();
    if (now.difference(_lastScan) < _scanDebounceWindow) {
      return false;
    }
    final lastSameBarcode = _lastScanPerBarcode[barcode];
    if (lastSameBarcode != null && now.difference(lastSameBarcode) < _sameBarcodeCooldown) {
      return false;
    }
    _lastScan = now;
    _lastScanPerBarcode[barcode] = now;
    return true;
  }

  double _totalSalesAllTime = 0;
  double _totalProfitAllTime = 0;
  double get totalSalesAllTime => _totalSalesAllTime;
  double get totalProfitAllTime => _totalProfitAllTime;
  double get totalCostAllTime => _totalSalesAllTime - _totalProfitAllTime;

  Future<void> loadStats() async {
    _totalSalesAllTime = await _db.getTotalSalesAllTime();
    _totalProfitAllTime = await _db.getTotalProfitAllTime();
    notifyListeners();
  }

  List<Map<String, dynamic>> _parkedCarts = [];
  List<Map<String, dynamic>> get parkedCarts => _parkedCarts;
  int get parkedCartCount => _parkedCarts.length;

  Future<void> loadParkedCarts() async {
    _parkedCarts = await _db.getParkedCarts();
    notifyListeners();
  }

  Future<String?> parkSale(String name) async {
    try {
      if (_cart.isEmpty) return 'السلة فارغة';
      if (_parkedCarts.length >= 20) {
        await _db.deleteOldestParkedCart();
      }
      await _db.parkCart(name, List<SaleItem>.from(_cart));
      startNewSale();
      await loadParkedCarts();
      return null;
    } catch (e) {
      return 'فشل تعليق الفاتورة: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> restoreParkedSale(int id) async {
    try {
      final data = await _db.getParkedCart(id);
      if (data == null) return 'الفاتورة غير موجودة';
      final items = (jsonDecode(data['items'] as String) as List)
          .map((m) => SaleItem.fromMap(m as Map<String, dynamic>))
          .toList();
      startNewSale();
      _cart.addAll(items);
      _recalcCartTotal();
      await _db.deleteParkedCart(id);
      await loadParkedCarts();
      notifyListeners();
      return null;
    } catch (e) {
      return 'فشل استعادة الفاتورة: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> deleteParkedSale(int id) async {
    try {
      await _db.deleteParkedCart(id);
      await loadParkedCarts();
      return null;
    } catch (e) {
      return 'فشل حذف الفاتورة المعلقة';
    }
  }

  List<Map<String, dynamic>> _sales = [];
  List<Map<String, dynamic>> get sales => _sales;

  Future<void> loadSales() async {
    _sales = await _db.getAllSales();
    notifyListeners();
  }

  Future<String?> updateSale(int saleId, double newTotal, double newProfit, List<SaleItem> oldItems, List<SaleItem> newItems) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        for (final item in oldItems) {
          if (item.productId != null) {
            await _db.restoreStockOn(txn, item.productId!, item.quantity);
          }
        }
        for (final item in newItems) {
          if (item.productId != null) {
            await _db.deductStockExec(txn, item.productId!, item.quantity);
          }
        }
        await _db.updateSaleOn(txn, saleId, newTotal, newProfit, newItems);
      });

      await Future.wait([
        loadSales(),
        loadProducts(),
        loadDashboard(),
        loadStats(),
      ]);
      return null;
    } on InsufficientStockException {
      return 'المخزون غير كافٍ لتعديل هذه الفاتورة';
    } catch (_) {
      return 'فشل تحديث الفاتورة';
    }
  }

  Future<bool> voidSale(int saleId, List<SaleItem> items) async {
    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        for (final item in items) {
          if (item.productId != null) {
            await _db.restoreStockOn(txn, item.productId!, item.quantity);
          }
        }
        await _db.deleteSaleOn(txn, saleId);
      });

      await Future.wait([
        loadSales(),
        loadProducts(),
        loadDashboard(),
        loadStats(),
      ]);
      return true;
    } catch (_) {
      return false;
    }
  }



  Future<List<Map<String, dynamic>>> getAllProductsRaw() => _db.getAllProductsRaw();
  Future<List<Map<String, dynamic>>> getAllSalesRaw() => _db.getAllSalesRaw();

  Future<String?> importProducts(String filePath) async {
    try {
      final products = await importProductsFromExcel(filePath);
      if (products.isEmpty) return 'لا توجد منتجات صالحة للاستيراد';
      for (final product in products) {
        try {
          await _db.insertProduct(product);
        } on sqlite.DatabaseException catch (e) {
          if (!e.isUniqueConstraintError()) rethrow;
        }
      }
      await loadProducts();
      return null;
    } catch (e) {
      return 'فشل الاستيراد: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> importSales(String filePath) async {
    try {
      final sales = await importSalesFromExcel(filePath);
      if (sales.isEmpty) return 'الملف لا يحتوي على بيانات عمليات';
      int count = 0;
      for (final sale in sales) {
        await _db.insertSaleFromBackup(sale);
        count++;
      }
      if (count == 0) return 'لم يتم العثور على بيانات صالحة';
      await loadSales();
      await loadDashboard();
      await loadStats();
      return null;
    } catch (e) {
      return 'فشل استيراد العمليات: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> archiveSales() async {
    try {
      final count = await _db.archiveSales();
      if (count == 0) return 'لا توجد عمليات للأرشفة';
      await loadSales();
      await loadDashboard();
      await loadStats();
      return null;
    } catch (e) {
      return 'فشلت الأرشفة: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> importArchivedSales(String filePath) async {
    try {
      final rows = await importSalesFromExcel(filePath);
      if (rows.isEmpty) return 'الملف لا يحتوي على بيانات';
      double totalSales = 0;
      double totalProfit = 0;
      for (final row in rows) {
        totalSales += (row['total'] as num?)?.toDouble() ?? 0;
        totalProfit += (row['total_profit'] as num?)?.toDouble() ?? 0;
      }
      if (totalSales == 0 && totalProfit == 0) {
        return 'لا توجد بيانات صالحة للاستعادة';
      }
      await _db.insertArchivedTotal(totalSales, totalProfit);
      await loadStats();
      return null;
    } catch (e) {
      return 'فشل استيراد ملف الأرشفة: ${e.toString().split('\n').first}';
    }
  }

  Future<void> updateBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_backup_date', DateTime.now().toIso8601String());
  }
}

class StockCheckResult {
  final bool ok;
  final String? message;
  const StockCheckResult.ok() : ok = true, message = null;
  const StockCheckResult.fail(this.message) : ok = false;
}