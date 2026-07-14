import 'dart:convert';
import 'package:sqflite/sqflite.dart' as sqlite;
import 'package:path/path.dart' as p;
import '../models/product.dart';
import '../models/sale_item.dart';
import '../models/customer.dart';
import '../models/stock_in_entry.dart';
import '../models/adjustment_entry.dart';

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
      version: 18,
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
            sale_type TEXT NOT NULL DEFAULT 'unit',
            discount_percent REAL NOT NULL DEFAULT 0,
            pieces_per_carton INTEGER NOT NULL DEFAULT 1,
            carton_price REAL NOT NULL DEFAULT 0,
            secondary_barcode TEXT DEFAULT ''
          )
        ''');
        await db.execute('''
          CREATE TABLE sales (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total REAL NOT NULL,
            total_profit REAL NOT NULL DEFAULT 0,
            discount REAL NOT NULL DEFAULT 0,
            items_count INTEGER NOT NULL,
            items TEXT NOT NULL,
            created_at TEXT NOT NULL,
            customer_id INTEGER DEFAULT NULL,
            customer_name TEXT DEFAULT NULL,
            is_archived INTEGER NOT NULL DEFAULT 0
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
            phone TEXT NOT NULL DEFAULT '',
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
        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            total REAL NOT NULL,
            created_at TEXT NOT NULL,
            merchant_name TEXT DEFAULT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS purchase_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            purchase_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            quantity REAL NOT NULL,
            cost REAL NOT NULL,
            stock_before REAL NOT NULL,
            cost_before REAL NOT NULL,
            stock_after REAL NOT NULL,
            cost_after REAL NOT NULL,
            subtotal REAL NOT NULL,
            FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items(purchase_id)');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS stock_adjustments (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            type TEXT NOT NULL,
            reason TEXT NOT NULL DEFAULT '',
            total_value REAL NOT NULL DEFAULT 0,
            created_at TEXT NOT NULL
          )
        ''');
        await db.execute('''
          CREATE TABLE IF NOT EXISTS stock_adjustment_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            adjustment_id INTEGER NOT NULL,
            product_id INTEGER NOT NULL,
            product_name TEXT NOT NULL,
            system_qty REAL NOT NULL,
            actual_qty REAL NOT NULL,
            difference REAL NOT NULL,
            cost_at_time REAL NOT NULL,
            FOREIGN KEY (adjustment_id) REFERENCES stock_adjustments(id) ON DELETE CASCADE,
            FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
          )
        ''');
        await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_adjustment_items_adjustment ON stock_adjustment_items(adjustment_id)');
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
        if (oldV < 10) {
          try {
            await db.execute("ALTER TABLE customers ADD COLUMN phone TEXT NOT NULL DEFAULT ''");
          } catch (_) {}
        }
        if (oldV < 11) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS purchases (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              total REAL NOT NULL,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS purchase_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              purchase_id INTEGER NOT NULL,
              product_id INTEGER NOT NULL,
              product_name TEXT NOT NULL,
              quantity REAL NOT NULL,
              cost REAL NOT NULL,
              stock_before REAL NOT NULL,
              cost_before REAL NOT NULL,
              stock_after REAL NOT NULL,
              cost_after REAL NOT NULL,
              subtotal REAL NOT NULL,
              FOREIGN KEY (purchase_id) REFERENCES purchases(id) ON DELETE CASCADE,
              FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_purchase_items_purchase ON purchase_items(purchase_id)');
        }
        if (oldV < 12) {
          try {
            await db.execute("ALTER TABLE sales ADD COLUMN is_archived INTEGER NOT NULL DEFAULT 0");
          } catch (_) {}
        }
        if (oldV < 13) {
          try {
            await db.execute("ALTER TABLE sales ADD COLUMN discount REAL NOT NULL DEFAULT 0");
          } catch (_) {}
        }
        if (oldV < 14) {
          try {
            await db.execute("ALTER TABLE products ADD COLUMN discount_percent REAL NOT NULL DEFAULT 0");
          } catch (_) {}
        }
        if (oldV < 15) {
          try {
            await db.execute("ALTER TABLE products ADD COLUMN pieces_per_carton INTEGER NOT NULL DEFAULT 1");
          } catch (_) {}
        }
        if (oldV < 16) {
          try {
            await db.execute("ALTER TABLE purchases ADD COLUMN merchant_name TEXT DEFAULT NULL");
          } catch (_) {}
        }
        if (oldV < 17) {
          try {
            await db.execute("ALTER TABLE products ADD COLUMN carton_price REAL NOT NULL DEFAULT 0");
          } catch (_) {}
          try {
            await db.execute("ALTER TABLE products ADD COLUMN secondary_barcode TEXT DEFAULT ''");
          } catch (_) {}
        }
        if (oldV < 18) {
          await db.execute('''
            CREATE TABLE IF NOT EXISTS stock_adjustments (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              type TEXT NOT NULL,
              reason TEXT NOT NULL DEFAULT '',
              total_value REAL NOT NULL DEFAULT 0,
              created_at TEXT NOT NULL
            )
          ''');
          await db.execute('''
            CREATE TABLE IF NOT EXISTS stock_adjustment_items (
              id INTEGER PRIMARY KEY AUTOINCREMENT,
              adjustment_id INTEGER NOT NULL,
              product_id INTEGER NOT NULL,
              product_name TEXT NOT NULL,
              system_qty REAL NOT NULL,
              actual_qty REAL NOT NULL,
              difference REAL NOT NULL,
              cost_at_time REAL NOT NULL,
              FOREIGN KEY (adjustment_id) REFERENCES stock_adjustments(id) ON DELETE CASCADE,
              FOREIGN KEY (product_id) REFERENCES products(id) ON DELETE CASCADE
            )
          ''');
          await db.execute('CREATE INDEX IF NOT EXISTS idx_stock_adjustment_items_adjustment ON stock_adjustment_items(adjustment_id)');
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
      where: 'name LIKE ? ESCAPE \'\\\' OR barcode LIKE ? ESCAPE \'\\\' OR secondary_barcode LIKE ? ESCAPE \'\\\'',
      whereArgs: ['%$escaped%', '%$escaped%', '%$escaped%'],
      orderBy: 'name COLLATE NOCASE ASC',
      limit: 200,
    );
    return maps.map((m) => Product.fromMap(m)).toList();
  }

  Future<Product?> getProductByBarcode(String barcode) async {
    final db = await database;
    final maps = await db.query(
      'products',
      where: 'barcode = ? OR secondary_barcode = ?',
      whereArgs: [barcode, barcode],
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

  Future<int> saveSaleOn(sqlite.DatabaseExecutor exec, double total, double totalProfit, List<SaleItem> items, {int? customerId, String? customerName, double discount = 0}) async {
    return exec.insert('sales', {
      'total': total,
      'total_profit': totalProfit,
      'discount': discount,
      'items_count': items.length,
      'items': jsonEncode(items.map((i) => i.toMap()).toList()),
      'created_at': DateTime.now().toIso8601String(),
      if (customerId != null) 'customer_id': customerId,
      if (customerName != null && customerName.isNotEmpty) 'customer_name': customerName,
    });
  }

  Future<List<Map<String, dynamic>>> getAllSales() async {
    final db = await database;
    return db.query('sales', where: 'is_archived = 0', orderBy: 'created_at DESC');
  }

  Future<List<Map<String, dynamic>>> getDailySales() async {
    final r = await (await database).rawQuery(
      'SELECT DATE(created_at) as day, COALESCE(SUM(total), 0) as total, COALESCE(SUM(total_profit - discount), 0) as profit, COUNT(*) as count FROM sales WHERE is_archived = 0 GROUP BY DATE(created_at) ORDER BY day DESC'
    );
    return r;
  }

  Future<double> getTodaySalesTotal() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final r = await (await database).rawQuery(
      'SELECT COALESCE(SUM(total), 0) as total FROM sales WHERE is_archived = 0 AND created_at >= ?',
      [startOfDay],
    );
    return (r.first['total'] as num).toDouble();
  }

  Future<int> getTodaySalesCount() async {
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day).toIso8601String();
    final r = await (await database).rawQuery(
      'SELECT COUNT(*) as count FROM sales WHERE is_archived = 0 AND created_at >= ?',
      [startOfDay],
    );
    return r.first['count'] as int;
  }

  Future<void> updateSale(int id, double total, double totalProfit, List<SaleItem> items) async {
    await updateSaleOn(await database, id, total, totalProfit, items);
  }

  Future<void> updateSaleOn(sqlite.DatabaseExecutor exec, int id, double total, double totalProfit, List<SaleItem> items, {double discount = 0}) async {
    final affected = await exec.update(
      'sales',
      {
        'total': total,
        'total_profit': totalProfit,
        'discount': discount,
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

  Future<void> archiveSingleSale(int id) async {
    final db = await database;
    await db.update('sales', {'is_archived': 1}, where: 'id = ?', whereArgs: [id]);
  }

  Future<void> unarchiveSingleSale(int id) async {
    final db = await database;
    await db.update('sales', {'is_archived': 0}, where: 'id = ?', whereArgs: [id]);
  }

  Future<double> getTotalSalesAllTime() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total), 0) + COALESCE((SELECT SUM(total_sales) FROM archived_totals), 0) as t FROM sales'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<double> getTotalProfitAllTime() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total_profit - discount), 0) + COALESCE((SELECT SUM(total_profit) FROM archived_totals), 0) as t FROM sales'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<double> getCurrentSalesTotal() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total), 0) as t FROM sales WHERE is_archived = 0'
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<double> getCurrentProfitTotal() async {
    final r = await (await database).rawQuery(
        'SELECT COALESCE(SUM(total_profit - discount), 0) as t FROM sales WHERE is_archived = 0'
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
    final r = await (await database).rawQuery('SELECT COUNT(*) as c FROM sales WHERE is_archived = 0');
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

  Future<List<Map<String, dynamic>>> getArchivedSales() async {
    final db = await database;
    return db.query('sales', where: 'is_archived = 1', orderBy: 'created_at DESC');
  }

  Future<int> archiveSales() async {
    final db = await database;
    final countResult = await db.rawQuery('SELECT COUNT(*) as c FROM sales WHERE is_archived = 0');
    final count = countResult.first['c'] as int;
    if (count == 0) return 0;
    final totals = await db.rawQuery(
        'SELECT COALESCE(SUM(total), 0) as ts, COALESCE(SUM(total_profit - discount), 0) as tp FROM sales WHERE is_archived = 0'
    );
    final totalSales = (totals.first['ts'] as num).toDouble();
    final totalProfit = (totals.first['tp'] as num).toDouble();
    await db.transaction((txn) async {
      await txn.insert('archived_totals', {
        'total_sales': totalSales,
        'total_profit': totalProfit,
        'archived_at': DateTime.now().toIso8601String(),
      });
      await txn.update('sales', {'is_archived': 1}, where: 'is_archived = 0');
    });
    return count;
  }



  Future<void> insertSaleFromBackup(Map<String, dynamic> sale) async {
    final db = await database;
    final itemsRaw = sale['items'];
    if (itemsRaw is! String) throw Exception('items must be a string');
    try {
      final parsed = jsonDecode(itemsRaw);
      if (parsed is! List) throw Exception('items must be a JSON array');
    } catch (_) {
      throw Exception('items contains invalid JSON');
    }
    final total = (sale['total'] as num?)?.toDouble() ?? 0;
    final totalProfit = (sale['total_profit'] as num?)?.toDouble() ?? 0;
    final itemsCount = (sale['items_count'] as num?)?.toInt() ?? 0;
    if (total < 0 || total > 1e9) throw Exception('total out of range');
    if (totalProfit < -1e9 || totalProfit > 1e9) throw Exception('total_profit out of range');
    if (itemsCount < 0 || itemsCount > 10000) throw Exception('items_count out of range');
    await db.insert('sales', {
      'total': total,
      'total_profit': totalProfit,
      'discount': (sale['discount'] as num?)?.toDouble() ?? 0,
      'items_count': itemsCount,
      'items': itemsRaw,
      'created_at': sale['created_at'] ?? DateTime.now().toIso8601String(),
      'is_archived': (sale['is_archived'] as num?)?.toInt() ?? 0,
      if (sale['customer_id'] != null) 'customer_id': (sale['customer_id'] as num).toInt(),
      if (sale['customer_name'] != null) 'customer_name': sale['customer_name'].toString(),
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

  Future<int> insertCustomer(String name, {String phone = ''}) async {
    final db = await database;
    return db.insert('customers', {
      'name': name,
      'phone': phone,
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

  Future<Map<String, dynamic>?> getCustomer(int id) async {
    final db = await database;
    final maps = await db.query('customers', where: 'id = ?', whereArgs: [id], limit: 1);
    return maps.isEmpty ? null : maps.first;
  }

  Future<void> updateCustomer(int id, String name, {String phone = ''}) async {
    final db = await database;
    await db.update(
      'customers',
      {'name': name, 'phone': phone},
      where: 'id = ?',
      whereArgs: [id],
    );
  }

  Future<void> deleteCustomer(int id) async {
    final db = await database;
    await db.transaction((txn) async {
      await txn.update('sales', {'customer_id': null},
          where: 'customer_id = ?', whereArgs: [id]);
      await txn.delete('customers', where: 'id = ?', whereArgs: [id]);
    });
  }

  Future<List<Map<String, dynamic>>> getCustomersWithDebts() async {
    final db = await database;
    return db.rawQuery('''
      SELECT
        c.id,
        c.name,
        c.phone,
        COALESCE(SUM(s.total), 0) AS total_debt,
        COALESCE((
          SELECT SUM(dp.amount) FROM debt_payments dp WHERE dp.customer_id = c.id
        ), 0) AS total_paid,
        COALESCE((
          SELECT MAX(act.created_at) FROM (
            SELECT created_at FROM sales WHERE customer_id = c.id
            UNION ALL
            SELECT created_at FROM debt_payments WHERE customer_id = c.id
          ) act
        ), '') AS last_date
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

  Future<void> consolidateCustomerPayments(int customerId) async {
    final db = await database;
    await db.transaction((txn) async {
      final r = await txn.rawQuery(
        'SELECT COALESCE(SUM(amount), 0) AS total FROM debt_payments WHERE customer_id = ?',
        [customerId],
      );
      final total = (r.first['total'] as num).toDouble();
      await txn.delete('debt_payments', where: 'customer_id = ?', whereArgs: [customerId]);
      if (total > 0) {
        await txn.insert('debt_payments', {
          'customer_id': customerId,
          'amount': total,
          'created_at': DateTime.now().toIso8601String(),
        });
      }
    });
  }

  Future<void> createPurchase(List<StockInEntry> entries, {String? merchantName}) async {
    final db = await database;
    await db.transaction((txn) async {
      double total = 0;
      final now = DateTime.now().toIso8601String();
      final List<Map<String, dynamic>> items = [];

      for (final entry in entries) {
        final r = await txn.query('products', where: 'id = ?', whereArgs: [entry.productId], limit: 1);
        if (r.isEmpty) continue;
        final row = r.first;
        final stockBefore = (row['stock'] as num).toDouble();
        final costBefore = (row['purchase_price'] as num).toDouble();
        final saleType = (row['sale_type'] as String?) ?? 'unit';
        final piecesPerCarton = (row['pieces_per_carton'] as int?) ?? 1;
        final isCarton = saleType == 'carton';
        final qtyInPieces = isCarton ? entry.quantity * piecesPerCarton : entry.quantity;
        final stockAfter = stockBefore + qtyInPieces;
        final costPerPiece = isCarton && piecesPerCarton > 0 ? entry.cost / piecesPerCarton : entry.cost;
        final totalValue = stockBefore * costBefore + qtyInPieces * costPerPiece;
        final costAfter = double.parse((stockAfter > 0 ? totalValue / stockAfter : costPerPiece).toStringAsFixed(5));
        final subtotal = entry.quantity * entry.cost;
        total += subtotal;

        await txn.update(
          'products',
          {'stock': stockAfter, 'purchase_price': costAfter},
          where: 'id = ?',
          whereArgs: [entry.productId],
        );

        items.add({
          'product_id': entry.productId,
          'product_name': entry.productName,
          'quantity': entry.quantity,
          'cost': entry.cost,
          'stock_before': stockBefore,
          'cost_before': costBefore,
          'stock_after': stockAfter,
          'cost_after': costAfter,
          'subtotal': subtotal,
        });
      }

      if (items.isEmpty) return;

      final purchaseId = await txn.insert('purchases', {
        'total': total,
        'created_at': now,
        if (merchantName != null && merchantName.trim().isNotEmpty) 'merchant_name': merchantName.trim(),
      });

      for (final item in items) {
        await txn.insert('purchase_items', {
          'purchase_id': purchaseId,
          ...item,
        });
      }
    });
  }

  Future<List<String>> getDistinctMerchantNames() async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT DISTINCT merchant_name FROM purchases WHERE merchant_name IS NOT NULL AND merchant_name != '' ORDER BY merchant_name COLLATE NOCASE ASC"
    );
    return r.map((row) => row['merchant_name'] as String).toList();
  }

  Future<List<Map<String, dynamic>>> getAllPurchases() async {
    final db = await database;
    return db.rawQuery('''
      SELECT p.*, COALESCE(cnt.items_count, 0) AS items_count
      FROM purchases p
      LEFT JOIN (
        SELECT purchase_id, COUNT(*) AS items_count
        FROM purchase_items
        GROUP BY purchase_id
      ) cnt ON cnt.purchase_id = p.id
      ORDER BY p.created_at DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getPurchaseItems(int purchaseId) async {
    final db = await database;
    return db.query('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId]);
  }

  Future<void> reversePurchase(int purchaseId, List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final item in items) {
        final productId = item['product_id'] as int;
        final stockBefore = (item['stock_before'] as num).toDouble();
        final costBefore = (item['cost_before'] as num).toDouble();
        await txn.update(
          'products',
          {'stock': stockBefore, 'purchase_price': costBefore},
          where: 'id = ?',
          whereArgs: [productId],
        );
      }
      await txn.delete('purchase_items', where: 'purchase_id = ?', whereArgs: [purchaseId]);
      await txn.delete('purchases', where: 'id = ?', whereArgs: [purchaseId]);
    });
  }

  Future<void> createStockAdjustment({
    required String type,
    required String reason,
    required List<AdjustmentEntry> entries,
  }) async {
    final db = await database;
    await db.transaction((txn) async {
      double totalValue = 0;
      final now = DateTime.now().toIso8601String();
      final List<Map<String, dynamic>> items = [];

      for (final entry in entries) {
        if (entry.difference == 0) continue;
        final newStock = entry.systemQty + entry.difference;
        await txn.update(
          'products',
          {'stock': newStock},
          where: 'id = ?',
          whereArgs: [entry.productId],
        );
        totalValue += entry.financialValue;
        items.add(entry.toMap());
      }

      if (items.isEmpty) return;

      final adjustmentId = await txn.insert('stock_adjustments', {
        'type': type,
        'reason': reason,
        'total_value': totalValue,
        'created_at': now,
      });

      for (final item in items) {
        await txn.insert('stock_adjustment_items', {
          'adjustment_id': adjustmentId,
          ...item,
        });
      }
    });
  }

  Future<void> reverseStockAdjustment(int adjustmentId, List<Map<String, dynamic>> items) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final item in items) {
        final productId = item['product_id'] as int;
        final systemQty = (item['system_qty'] as num).toDouble();
        await txn.update(
          'products',
          {'stock': systemQty},
          where: 'id = ?',
          whereArgs: [productId],
        );
      }
      await txn.delete('stock_adjustment_items', where: 'adjustment_id = ?', whereArgs: [adjustmentId]);
      await txn.delete('stock_adjustments', where: 'id = ?', whereArgs: [adjustmentId]);
    });
  }

  Future<List<Map<String, dynamic>>> getStockAdjustments() async {
    final db = await database;
    return db.rawQuery('''
      SELECT sa.*, COALESCE(cnt.items_count, 0) AS items_count
      FROM stock_adjustments sa
      LEFT JOIN (
        SELECT adjustment_id, COUNT(*) AS items_count
        FROM stock_adjustment_items
        GROUP BY adjustment_id
      ) cnt ON cnt.adjustment_id = sa.id
      ORDER BY sa.created_at DESC
    ''');
  }

  Future<List<Map<String, dynamic>>> getStockAdjustmentItems(int adjustmentId) async {
    final db = await database;
    return db.query('stock_adjustment_items',
      where: 'adjustment_id = ?',
      whereArgs: [adjustmentId],
    );
  }

  Future<double> getTotalAdjustmentLoss() async {
    final db = await database;
    final r = await db.rawQuery(
      "SELECT COALESCE(SUM(ABS(total_value)), 0) as t FROM stock_adjustments WHERE type = 'loss'"
    );
    return (r.first['t'] as num).toDouble();
  }

  Future<String> getDbFilePath() async {
    return p.join(await sqlite.getDatabasesPath(), 'pos.db');
  }

  Future<sqlite.Database> openDbFromPath(String dbPath) async {
    return sqlite.openDatabase(dbPath);
  }

  Future<void> close() async {
    if (_db != null) {
      await _db!.close();
      _db = null;
      _initFuture = null;
    }
  }

  Future<Map<String, List<Map<String, dynamic>>>> exportAllTables() async {
    final db = await database;
    final tables = [
      'products',
      'sales',
      'customers',
      'debt_payments',
      'purchases',
      'purchase_items',
      'parked_carts',
      'archived_totals',
    ];
    final result = <String, List<Map<String, dynamic>>>{};
    for (final table in tables) {
      result[table] = await db.query(table);
    }
    return result;
  }

  Future<void> mergeFromBackup(Map<String, List<Map<String, dynamic>>> data) async {
    final db = await database;
    await db.transaction((txn) async {
      for (final row in (data['products'] ?? [])) {
        await txn.rawInsert(
          'INSERT OR IGNORE INTO products(name, barcode, price, purchase_price, stock, category, sale_type, discount_percent, pieces_per_carton) VALUES(?, ?, ?, ?, ?, ?, ?, ?, ?)',
          [
            row['name'],
            row['barcode'],
            row['price'],
            row['purchase_price'],
            row['stock'],
            row['category'] ?? '',
            row['sale_type'] ?? 'unit',
            row['discount_percent'] ?? 0,
            row['pieces_per_carton'] ?? 1,
          ],
        );
      }
      for (final row in (data['customers'] ?? [])) {
        await txn.rawInsert(
          'INSERT OR IGNORE INTO customers(name, phone, created_at) VALUES(?, ?, ?)',
          [row['name'], row['phone'] ?? '', row['created_at']],
        );
      }
      for (final row in (data['sales'] ?? [])) {
        final existing = await txn.query('sales', where: 'id = ?', whereArgs: [row['id']], limit: 1);
        if (existing.isEmpty) {
          await txn.insert('sales', Map<String, dynamic>.from(row));
        }
      }
      for (final row in (data['debt_payments'] ?? [])) {
        final existing = await txn.query('debt_payments', where: 'id = ?', whereArgs: [row['id']], limit: 1);
        if (existing.isEmpty) {
          await txn.insert('debt_payments', Map<String, dynamic>.from(row));
        }
      }
      for (final row in (data['purchases'] ?? [])) {
        final existing = await txn.query('purchases', where: 'id = ?', whereArgs: [row['id']], limit: 1);
        if (existing.isEmpty) {
          await txn.insert('purchases', Map<String, dynamic>.from(row));
        }
      }
      for (final row in (data['purchase_items'] ?? [])) {
        final existing = await txn.query('purchase_items', where: 'id = ?', whereArgs: [row['id']], limit: 1);
        if (existing.isEmpty) {
          await txn.insert('purchase_items', Map<String, dynamic>.from(row));
        }
      }
      for (final row in (data['parked_carts'] ?? [])) {
        final existing = await txn.query('parked_carts', where: 'id = ?', whereArgs: [row['id']], limit: 1);
        if (existing.isEmpty) {
          await txn.insert('parked_carts', Map<String, dynamic>.from(row));
        }
      }
      for (final row in (data['archived_totals'] ?? [])) {
        final existing = await txn.query('archived_totals', where: 'id = ?', whereArgs: [row['id']], limit: 1);
        if (existing.isEmpty) {
          await txn.insert('archived_totals', Map<String, dynamic>.from(row));
        }
      }
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
