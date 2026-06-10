import 'dart:convert';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:path/path.dart' as p;
import '../models/product.dart';
import '../models/sale_item.dart';
import '../models/customer.dart';

class DatabaseHelper {
  static final DatabaseHelper _instance = DatabaseHelper._();
  factory DatabaseHelper() => _instance;
  DatabaseHelper._();

  sqlite.Database? _db;
  Future<sqlite.Database>? _initFuture;

  Future<sqlite.Database> get database async {
    if (_db != null) return _db!;
    if (_initFuture != null) {
      try {
        return await _initFuture!;
      } catch (_) {
        _initFuture = null;
      }
    }
    _initFuture = _init().then((db) {
      _db = db;
      return db;
    });
    return await _initFuture!;
  }

  Future<sqlite.Database> _init() async {
    final path = p.join(await sqlite.getDatabasesPath(), 'pos.db');
    return sqlite.openDatabase(
      path,
      version: 9,
      onConfigure: (db) async {
        await db.rawQuery('PRAGMA journal_mode = WAL');
        await db.execute('PRAGMA synchronous = NORMAL');
        await db.execute('PRAGMA temp_store = MEMORY');
        await db.execute('PRAGMA cache_size = -8000');
        await db.execute('PRAGMA foreign_keys = ON');
      },
      onCreate: (db, v) async {
        await db.execute('''
          CREATE TABLE products (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            barcode TEXT UNIQUE NOT NULL,
            price REAL NOT NULL,
            purchase_price REAL NOT NULL DEFAULT 0,
            stock REAL NOT NULL DEFAULT 0,
            category TEXT DEFAULT "",
            sale_type TEXT NOT NULL DEFAULT 'unit'
          )
        ''');
        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total REAL NOT NULL,
            total_profit REAL NOT NULL DEFAULT 0,
            items_count INTEGER NOT NULL,
            items TEXT NOT NULL,
            created_at TEXT NOT NULL,
            customer_id INTEGER DEFAULT NULL,
            customer_name TEXT DEFAULT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS archived_totals (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total_sales REAL NOT NULL,
            total_profit REAL NOT NULL,
            archived_at TEXT NOT NULL
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at)');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS parked_carts (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL,
            items TEXT NOT NULL,
            total REAL NOT NULL,
            items_count INTEGER NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS customers (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT UNIQUE NOT NULL,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS debt_payments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            customer_id INTEGER NOT NULL,
            amount REAL NOT NULL,
            created_at TEXT NOT NULL,
            FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_debt_payments_customer ON debt_payments(customer_id)');
      },
      onUpgrade: (db, oldV, newV) async {
        if (oldV < 2) {
          try {
            await db.execute('ALTER TABLE products ADD COLUMN purchase_price REAL NOT NULL DEFAULT 0');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN total_profit REAL NOT NULL DEFAULT 0');
          } catch (_) {}
        }
        if (oldV < 3) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS archived_totals (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              total_sales REAL NOT NULL,
              total_profit REAL NOT NULL,
              archived_at TEXT NOT NULL
            )
          ''');
        }
        if (oldV < 4) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_products_barcode ON products(barcode)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_sales_created_at ON sales(created_at)');
        }
        if (oldV < 5) {
          await db.execute('CREATE INDEX IF NOT EXISTS idx_products_name ON products(name COLLATE NOCASE)');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_products_category ON products(category)');
        }
        if (oldV < 6) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS parked_carts (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT NOT NULL,
              items TEXT NOT NULL,
              total REAL NOT NULL,
              items_count INTEGER NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
        }
        if (oldV < 7) {
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN customer_id INTEGER DEFAULT NULL');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN customer_name TEXT DEFAULT NULL');
          } catch (_) {}
          await db.execute('''
            CREATE TABLE IF NOT EXISTS customers (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              name TEXT UNIQUE NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS debt_payments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              customer_id INTEGER NOT NULL,
              amount REAL NOT NULL,
              created_at TEXT NOT NULL,
              FOREIGN KEY (customer_id) REFERENCES customers(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_debt_payments_customer ON debt_payments(customer_id)');
        }
        if (oldV < 8) {
          try {
            await db.execute("ALTER TABLE products ADD COLUMN sale_type TEXT NOT NULL DEFAULT 'unit'");
          } catch (_) {}
        }
        if (oldV < 9) {
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN customer_id INTEGER DEFAULT NULL');
          } catch (_) {}
          try {
            await db.execute('ALTER TABLE sales ADD COLUMN customer_name TEXT DEFAULT NULL');
          } catch (_) {}
        }
      },
    );
  }

  Future<List<Product>> getAllProducts() async {
    final db = await database;
    final maps = await db.query('products', orderBy: 'name COLLATE NOCASE ASC');
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<List<Product>> searchProducts(String q) async {
    if (q.isEmpty) return getAllProducts();
    final db = await database;
    final escaped = q.replaceAll('%', r'\%').replaceAll('_', r'\_');
    final maps = await db.query(
      'products',
      where: 'name LIKE ? ESCAPE \'\\\' OR barcode LIKE ? ESCAPE \'\\\'',
      whereArgs: ['%$escaped%', '%$escaped%'],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: 200,
    );
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'barcode = ?',
      whereArgs: [barcode],
      limit: 1,
    );
    if (maps.isEmpty) {
      return null;
    }
    return Product.fromMap(maps.first);
  }

  Future<int> insertProduct(Product product) async {
    final db = await database;
    return db.insert('products', product.toMap());
  }

  Future<void> updateProduct(Product product) async {
    final db = await database;
    await db.update('products', product.toMap(), where: 'id = ?', whereArgs: [product.id]);
  }

  Future<void> deleteProduct(int id) async {
    final db = await database;
    await db.delete('products', where: 'id = ?', whereArgs: [id]);
  }

  Future<int> deductStock(int productId, double qty) {
    return deductStockOn(database, productId, qty).then((_) => 1);
  }

  Future<int> deductStockOn(Future<sqlite.Database> dbFuture, int productId, double qty) async {
    final db = await dbFuture;
    return deductStockExec(db, productId, qty);
  }

  Future<int> deductStockExec(sqlite.DatabaseExecutor exec, int productId, double qty) async {
    final r = await exec.rawUpdate(
      'UPDATE products SET stock = stock - ? WHERE id = ? AND stock >= ?',
      [qty, productId, qty],
    );
    if (r == 0) {
      throw InsufficientStockException(requested: qty);
    }
    return r;
  }

  Future<int> restoreStock(int productId, double qty) async {
    return restoreStockOn(await database, productId, qty);
  }

  Future<int> restoreStockOn(sqlite.DatabaseExecutor exec, int productId, double qty) async {
    return exec.rawUpdate(
      'UPDATE products SET stock = stock + ? WHERE id = ?',
      [qty, productId],
    );
  }

  Future<int> saveSale(double total, double totalProfit, List<SaleItem> items) async {
    return saveSaleOn(await database, total, totalProfit, items);
  }

  Future<int> saveSaleOn(sqlite.DatabaseExecutor exec, double total, double totalProfit, List<SaleItem> items, {int? customerId, String? customerName}) async {
    return exec.insert('sales', {
      'total': total,
      'total_profit': totalProfit,
      'items_count': items.length,
      'items': jsonEncode(items.map((i) => i.toMap()).toList()),
      'created_at': DateTime.now().toIso8601String(),
      'customer_id': ?customerId,
      if (customerName != null && customerName.isNotEmpty) 'customer_name': customerName,
    });
  }

  Future<List<Map<String, dynamic>>> getAllSales() async {
    final db = await database;
    return db.query('sales', orderBy: 'created_at DESC');
  }

  Future<double> getTodaySalesTotal() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final r = await (await database).rawQuery(
      'SELECT COALESCE(SUM(total), 0) as total FROM sales WHERE created_at >= ?',
      [startOfDay],
    );
    return (r.first['total'] as num).toDouble();
  }

  Future<int> getTodaySalesCount() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final r = await (await database).rawQuery(
      'SELECT COUNT(*) as count FROM sales WHERE created_at >= ?',
      [startOfDay],
    );
    return r.first['count'] as int;
  }

  Future<void> updateSale(int id, double total, double totalProfit, List<SaleItem> items) async {
    await updateSaleOn(await database, id, total, totalProfit, items);
  }

  Future<void> updateSaleOn(sqlite.DatabaseExecutor exec, int id, double total, double totalProfit, List<SaleItem> items) async {
    final affected = await exec.update(
      'sales',
      {
        'total': total,
        'total_profit': totalProfit,
        'items_count': items.length,
        'items': jsonEncode(items.map((i) => i.toMap()).toList()),
      },
      where: 'id = ?',
      whereArgs: [id],
    );
    if (affected == 0) {
      throw Exception('لم يتم العثور على الفاتورة رقم $id');
    }
  }

  Future<void> deleteSale(int id) async {
    await deleteSaleOn(await database, id);
  }

  Future<void> deleteSaleOn(sqlite.DatabaseExecutor exec, int id) async {
    await exec.delete('sales', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalSalesAllTime() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total), 0) + COALESCE((SELECT SUM(total_sales) FROM archived_totals), 0) as t FROM sales'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<double> getTotalProfitAllTime() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total_profit), 0) + COALESCE((SELECT SUM(total_profit) FROM archived_totals), 0) as t FROM sales'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<double> getCurrentSalesTotal() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total), 0) as t FROM sales'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<double> getCurrentProfitTotal() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total_profit), 0) as t FROM sales'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<double> getArchivedSalesTotal() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total_sales), 0) as t FROM archived_totals'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<double> getArchivedProfitTotal() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total_profit), 0) as t FROM archived_totals'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<List<Map<String, dynamic>>> getArchiveHistory() async {
    final db = await database;
    return db.query('archived_totals',
        columns: ['id', 'total_sales', 'total_profit', 'archived_at'],
        orderBy: 'archived_at DESC');
  }

  Future<int> countSales() async {
    final r = await (await database).rawQuery('SELECT COUNT(*) as c FROM sales');
    return r.first['c'] as int;
  }

  Future<List<Map<String, dynamic>>> getAllProductsRaw() async {
    final db = await database;
    return db.query('products', orderBy: 'name COLLATE NOCASE ASC');
  }

  Future<List<Map<String, dynamic>>> getAllSalesRaw() async {
    final db = await database;
    return db.query('sales', orderBy: 'created_at DESC');
  }

  Future<int> archiveSales() async {
    final db = await database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as c FROM sales');
    final count = countResult.first['c'] as int;
    if (count == 0) return 0;
    final totals = await db.rawQuery(
        'SELECT COALESCE(SUM(total), 0) as ts, COALESCE(SUM(total_profit), 0) as tp FROM sales'
    );
    final totalSales = (totals.first['ts'] as num).toDouble();
    final totalProfit = (totals.first['tp'] as num).toDouble();
    await db.transaction((txn) async {
      await txn.insert('archived_totals', {
        'total_sales': totalSales,
        'total_profit': totalProfit,
        'archived_at': DateTime.now().toIso8601String(),
      });
      await txn.delete('sales');
    });
    return count;
  }



  Future<void> insertSaleFromBackup(Map<String, dynamic> sale) async {
    final db = await database;
    await db.insert('sales', {
      'total': sale['total'],
      'total_profit': sale['total_profit'],
      'items_count': sale['items_count'],
      'items': sale['items'],
      'created_at': sale['created_at'],
      if (sale['customer_id'] != null) 'customer_id': sale['customer_id'],
      if (sale['customer_name'] != null) 'customer_name': sale['customer_name'],
    });
  }

  Future<void> insertArchivedTotal(double totalSales, double totalProfit) async {
    final db = await database;
    await db.insert('archived_totals', {
      'total_sales': totalSales,
      'total_profit': totalProfit,
      'archived_at': DateTime.now().toIso8601String(),
    });
  }

  Future<void> parkCart(String name, List<SaleItem> items) async {
    final db = await database;
    final total = items.fold(0.0, (s, i) => s + i.subtotal);
    await db.insert('parked_carts', {
      'name': name,
      'items': jsonEncode(items.map((i) => i.toMap()).toList()),
      'total': total,
      'items_count': items.length,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int> getParkedCartCount() async {
    final r = await (await database).rawQuery('SELECT COUNT(*) as c FROM parked_carts');
    return r.first['c'] as int;
  }

  Future<List<Map<String, dynamic>>> getParkedCarts() async {
    return (await database).query('parked_carts', orderBy: 'created_at DESC');
  }

  Future<Map<String, dynamic>?> getParkedCart(int id) async {
    final r = await (await database).query('parked_carts', where: 'id = ?', whereArgs: [id], limit: 1);
    return r.isEmpty ? null : r.first;
  }

  Future<void> deleteParkedCart(int id) async {
    await (await database).delete('parked_carts', where: 'id = ?', whereArgs: [id]);
  }

  Future<void> deleteOldestParkedCart() async {
    final r = await (await database).rawQuery(
      'SELECT id FROM parked_carts ORDER BY created_at ASC LIMIT 1'
    );
    if (r.isNotEmpty) {
      await deleteParkedCart(r.first['id'] as int);
    }
  }

  Future<List<Customer>> searchCustomers(String query) async {
    final db = await database;
    if (query.isEmpty) return [];
    final escaped = query.replaceAll('%', r'\%').replaceAll('_', r'\_');
    final maps = await db.query(
      'customers',
      where: 'name LIKE ? ESCAPE \'\\\'',
      whereArgs: ['%$escaped%'],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: 20,
    );
    return maps.map((m) => Customer.fromMap(m)).toList();
  }

  Future<List<Customer>> getAllCustomers() async {
    final db = await database;
    final maps = await db.query('customers', orderBy: 'name COLLATE NOCASE ASC');
    return maps.map((m) => Customer.fromMap(m)).toList();
  }

  Future<int> insertCustomer(String name) async {
    final db = await database;
    return db.insert('customers', {
      'name': name,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<int?> getCustomerIdByName(String name) async {
    final db = await database;
    final maps = await db.query(
      'customers',
      where: 'name = ?',
      whereArgs: [name],
      limit: 1,
    );
    return maps.isEmpty ? null : maps.first['id'] as int;
  }

  Future<int> upsertCustomer(String name) async {
    final existing = await getCustomerIdByName(name);
    if (existing != null) return existing;
    return insertCustomer(name);
  }

  Future<List<Map<String, dynamic>>> getCustomersWithDebts() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        c.id,
        c.name,
        COALESCE(SUM(s.total), 0) AS total_debt,
        COALESCE((
          SELECT SUM(dp.amount) FROM debt_payments dp WHERE dp.customer_id = c.id
        ), 0) AS total_paid
      FROM customers c
      LEFT JOIN sales s ON s.customer_id = c.id
      GROUP BY c.id
      ORDER BY total_debt - total_paid DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getCustomerSales(int customerId) async {
    final db = await database;
    return db.query(
      'sales',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> insertDebtPayment(int customerId, double amount) async {
    final db = await database;
    await db.insert('debt_payments', {
      'customer_id': customerId,
      'amount': amount,
      'created_at': DateTime.now().toIso8601String(),
    });
  }

  Future<List<Map<String, dynamic>>> getCustomerPayments(int customerId) async {
    final db = await database;
    return db.query(
      'debt_payments',
      where: 'customer_id = ?',
      whereArgs: [customerId],
      orderBy: 'created_at DESC',
    );
  }

  Future<void> updateDebtPayment(int id, double amount) async {
    final db = await database;
    await db.update(
      'debt_payments',
      {'amount': amount, 'created_at': DateTime.now().toIso8601String()},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteDebtPayment(int id) async {
    final db = await database;
    await db.delete('debt_payments', where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalDebtsAllTime() async {
    final r = await (await database).rawQuery(
      'SELECT COALESCE(SUM(total), 0) AS t FROM sales WHERE customer_id IS NOT NULL'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<double> getTotalPaidAllTime() async {
    final r = await (await database).rawQuery(
      'SELECT COALESCE(SUM(amount), 0) AS t FROM debt_payments'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<List<Map<String, dynamic>>> getAllDebtSales() async {
    final db = await database;
    return db.rawQuery('''
      SELECT s.*, c.name AS customer_name
      FROM sales s
      LEFT JOIN customers c ON c.id = s.customer_id
      WHERE s.customer_id IS NOT NULL
      ORDER BY s.created_at DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getAllDebtPaymentsWithCustomer() async {
    final db = await database;
    return db.rawQuery('''
      SELECT dp.*, c.name AS customer_name
      FROM debt_payments dp
      LEFT JOIN customers c ON c.id = dp.customer_id
      ORDER BY dp.created_at DESC
    ''');
  }

  Future<void> insertDebtPaymentWithDate(int customerId, double amount, String createdAt) async {
    final db = await database;
    await db.insert('debt_payments', {
      'customer_id': customerId,
      'amount': amount,
      'created_at': createdAt,
    });
  }


}

class InsufficientStockException implements Exception {
  final int productId;
  final double requested;
  const InsufficientStockException({this.productId = 0, this.requested = 0});

  @override
  String toString() => 'InsufficientStockException(product=$productId, requested=$requested)';
}
