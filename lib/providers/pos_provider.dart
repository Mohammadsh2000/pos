import 'dart:convert';
import 'package:flutter/foundation.dart';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:shared_preferences/shared_preferences.dart';
import '../models/product.dart';
import '../models/sale_item.dart';
import '../models/customer.dart';
import '../models/stock_in_entry.dart';
import '../services/database_helper.dart';
import '../utils/excel_helpers.dart';
import '../constants.dart';

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
  List<Map<String, dynamic>> _dailySales = [];
  List<Map<String, dynamic>> get dailySales => _dailySales;

  Future<void> loadDashboard() async {
    _todaySalesTotal = await _db.getTodaySalesTotal();
    _todaySalesCount = await _db.getTodaySalesCount();
    notifyListeners();
  }

  Future<void> loadDailySales() async {
    _dailySales = await _db.getDailySales();
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

  bool _isProcessingSale = false;
  bool get isProcessingSale => _isProcessingSale;

  final List<SaleItem> _cart = [];
  List<SaleItem> get cart => _cart;

  double _cartTotal = 0.0;
  double get cartTotal => _cartTotal;
  int get cartItemsCount => _cart.length;

  String _customerName = '';
  String get customerName => _customerName;
  set customerName(String v) {
    _customerName = v;
    notifyListeners();
  }

  void startNewSale() {
    if (_isProcessingSale) return;
    _cart.clear();
    _customerName = '';
    _recalcCartTotal();
    _lastScan = DateTime.fromMillisecondsSinceEpoch(0);
    _lastScanPerBarcode.clear();
    notifyListeners();
  }

  bool isStockAvailable(String barcode, double totalQuantity) {
    final product = _productByBarcode[barcode];
    if (product == null) return true;
    return product.stock >= totalQuantity;
  }

  StockCheckResult canAddToCart(Product product, double quantity) {
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
        'المخزون غير كافٍ: ${product.stock.toStringAsFixed(2)} متاح، المطلوب ${desired.toStringAsFixed(2)}',
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
    return addToCartWithQuantity(product, product.isKg ? 1.0 : 1);
  }

  bool addToCartWithQuantity(Product product, double quantity) {
    if (_isProcessingSale) return false;
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
        saleType: product.saleType,
      ));
    }
    _recalcCartTotal();
    notifyListeners();
    return true;
  }

  void removeFromCart(int i) {
    if (_isProcessingSale) return;
    _cart.removeAt(i);
    _recalcCartTotal();
    notifyListeners();
  }

  void updateCartItemQuantity(int i, double q) {
    if (_isProcessingSale) return;
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

  Future<Map<String, dynamic>?> completeSale({String? customerName}) async {
    if (_cart.isEmpty || _isProcessingSale) {
      return null;
    }
    _isProcessingSale = true;
    notifyListeners();
    final total = _cartTotal;
    final totalProfit = _cart.fold(0.0, (s, i) => s + i.profit);
    final items = List<SaleItem>.from(_cart);
    int? saleId;

    int? customerId;
    if (customerName != null && customerName.trim().isNotEmpty) {
      final name = customerName.trim();
      customerId = await _db.upsertCustomer(name);
    }

    try {
      final db = await _db.database;
      await db.transaction((txn) async {
        saleId = await _db.saveSaleOn(txn, total, totalProfit, _cart,
            customerId: customerId, customerName: customerName?.trim());
        for (final item in _cart) {
          if (item.productId != null) {
            await _db.deductStockExec(txn, item.productId!, item.quantity);
          }
        }
      });
    } on InsufficientStockException {
      _isProcessingSale = false;
      notifyListeners();
      return null;
    } catch (_) {
      _isProcessingSale = false;
      notifyListeners();
      return null;
    }

    if (saleId == null) {
      _isProcessingSale = false;
      notifyListeners();
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
    _isProcessingSale = false;
    notifyListeners();
    return completed;
  }

  bool _isCameraActive = false;
  bool get isCameraActive => _isCameraActive;

  void setCameraActive(bool v) {
    _isCameraActive = v;
    notifyListeners();
  }

  List<Customer> _customerSuggestions = [];
  List<Customer> get customerSuggestions => _customerSuggestions;

  Future<void> searchCustomers(String query) async {
    if (query.isEmpty) {
      _customerSuggestions = [];
      notifyListeners();
      return;
    }
    _customerSuggestions = await _db.searchCustomers(query);
    notifyListeners();
  }

  Future<String?> addCustomer(String name, {String phone = ''}) async {
    try {
      await _db.insertCustomer(name, phone: phone);
      await loadDebtData();
      return null;
    } catch (e) {
      return 'فشل إضافة العميل: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> updateCustomer(int id, String name, {String phone = ''}) async {
    try {
      await _db.updateCustomer(id, name, phone: phone);
      await loadDebtData();
      return null;
    } catch (e) {
      return 'فشل تحديث بيانات العميل: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> deleteCustomer(int id) async {
    try {
      await _db.deleteCustomer(id);
      await loadDebtData();
      return null;
    } catch (e) {
      return 'تعذّر حذف العميل';
    }
  }

  Future<String?> createPurchase(List<StockInEntry> entries) async {
    try {
      await _db.createPurchase(entries);
      await loadProducts();
      return null;
    } catch (e) {
      return 'فشل تسجيل فاتورة التزويد: ${e.toString().split('\n').first}';
    }
  }

  List<Map<String, dynamic>> _debtCustomers = [];
  List<Map<String, dynamic>> get debtCustomers => _debtCustomers;

  double _totalDebts = 0;
  double _totalPaid = 0;
  double get totalDebts => _totalDebts;
  double get totalPaid => _totalPaid;
  double get totalRemaining => _totalDebts - _totalPaid;

  Future<void> loadDebtData() async {
    _debtCustomers = await _db.getCustomersWithDebts();
    _totalDebts = await _db.getTotalDebtsAllTime();
    _totalPaid = await _db.getTotalPaidAllTime();
    notifyListeners();
  }

  Future<String?> recordDebtPayment(int customerId, double amount) async {
    try {
      await _db.insertDebtPayment(customerId, amount);
      await loadDebtData();
      return null;
    } catch (e) {
      return 'فشل تسجيل الدفعة: ${e.toString().split('\n').first}';
    }
  }

  Future<Map<String, dynamic>?> getCustomerSales(int customerId) async {
    try {
      final sales = await _db.getCustomerSales(customerId);
      final customer = await _db.getCustomer(customerId);
      return {
        'sales': sales,
        'payments': await _db.getCustomerPayments(customerId),
        'phone': customer?['phone'] as String? ?? '',
        'name': customer?['name'] as String? ?? '',
      };
    } catch (_) {
      return null;
    }
  }

  Future<String?> updateDebtPayment(int id, double amount) async {
    try {
      await _db.updateDebtPayment(id, amount);
      await loadDebtData();
      return null;
    } catch (e) {
      return 'فشل تعديل الدفعة: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> deleteDebtPayment(int id) async {
    try {
      await _db.deleteDebtPayment(id);
      await loadDebtData();
      return null;
    } catch (e) {
      return 'فشل حذف الدفعة: ${e.toString().split('\n').first}';
    }
  }

  Future<String?> consolidatePayments(int customerId) async {
    try {
      await _db.consolidateCustomerPayments(customerId);
      await loadDebtData();
      return null;
    } catch (e) {
      return 'فشل دمج الدفعات: ${e.toString().split('\n').first}';
    }
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

  double _currentSales = 0;
  double _currentProfit = 0;
  double _archivedSales = 0;
  double _archivedProfit = 0;
  List<Map<String, dynamic>> _archiveHistory = [];
  double get currentSales => _currentSales;
  double get currentProfit => _currentProfit;
  double get archivedSales => _archivedSales;
  double get archivedProfit => _archivedProfit;
  List<Map<String, dynamic>> get archiveHistory => _archiveHistory;

  int _salesCount = 0;
  int get salesCount => _salesCount;

  Future<void> loadStats() async {
    _currentSales = await _db.getCurrentSalesTotal();
    _currentProfit = await _db.getCurrentProfitTotal();
    _archivedSales = await _db.getArchivedSalesTotal();
    _archivedProfit = await _db.getArchivedProfitTotal();
    _archiveHistory = await _db.getArchiveHistory();
    _totalSalesAllTime = _currentSales + _archivedSales;
    _totalProfitAllTime = _currentProfit + _archivedProfit;
    _salesCount = await _db.countSales();
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

  List<Map<String, dynamic>> _archivedSalesList = [];
  List<Map<String, dynamic>> get archivedSalesList => _archivedSalesList;

  Future<void> loadSales() async {
    _sales = await _db.getAllSales();
    notifyListeners();
  }

  Future<void> loadArchivedSales() async {
    _archivedSalesList = await _db.getArchivedSales();
    notifyListeners();
  }

  Future<String?> archiveSingleSale(int saleId) async {
    try {
      await _db.archiveSingleSale(saleId);
      await Future.wait([
        loadSales(),
        loadDashboard(),
        loadStats(),
      ]);
      return null;
    } catch (e) {
      return 'فشلت أرشفة الفاتورة';
    }
  }

  Future<String?> unarchiveSingleSale(int saleId) async {
    try {
      await _db.unarchiveSingleSale(saleId);
      await Future.wait([
        loadArchivedSales(),
        loadSales(),
        loadDashboard(),
        loadStats(),
      ]);
      return null;
    } catch (e) {
      return 'فشل إلغاء أرشفة الفاتورة';
    }
  }

  Future<String?> updateSale(int saleId, double newTotal, double newProfit, List<SaleItem> oldItems, List<SaleItem> newItems, {int? customerId, String? customerName}) async {
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

  Future<List<Map<String, dynamic>>> getAllPurchases() => _db.getAllPurchases();
  Future<List<Map<String, dynamic>>> getPurchaseItems(int purchaseId) => _db.getPurchaseItems(purchaseId);

  Future<bool> reversePurchase(int purchaseId) async {
    try {
      final items = await _db.getPurchaseItems(purchaseId);
      await _db.reversePurchase(purchaseId, items);
      await loadProducts();
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
      await Future.wait([
        loadSales(),
        loadArchivedSales(),
        loadDashboard(),
        loadStats(),
      ]);
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

  String get currencySymbol => kCurrencySymbol;

  Future<void> loadCurrencySymbol() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString('currency_symbol');
    if (saved != null && saved.isNotEmpty) {
      kCurrencySymbol = saved;
      notifyListeners();
    }
  }

  Future<void> setCurrencySymbol(String symbol) async {
    kCurrencySymbol = symbol;
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('currency_symbol', symbol);
    notifyListeners();
  }

  Future<void> updateBackupDate() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString('last_backup_date', DateTime.now().toIso8601String());
  }

  Future<String?> exportDebts(String filePath) async {
    try {
      final debtSummary = await _db.getCustomersWithDebts();
      final debtSales = await _db.getAllDebtSales();
      final debtPayments = await _db.getAllDebtPaymentsWithCustomer();
      await exportDebtsToExcel(debtSummary, debtSales, debtPayments, filePath);
      return null;
    } catch (e) {
      return 'فشل تصدير الديون: ${e.toString().split('\n').first}';
    }
  }


}

class StockCheckResult {
  final bool ok;
  final String? message;
  const StockCheckResult.ok() : ok = true, message = null;
  const StockCheckResult.fail(this.message) : ok = false;
}