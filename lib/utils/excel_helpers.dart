import 'dart:convert';
import 'dart:io';
import 'package:excel/excel.dart';
import '../constants.dart';
import '../models/product.dart';

Future<File> exportProductsToExcel(List<Product> products, String filePath) async {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'المنتجات');
  final sheet = excel['المنتجات'];

  sheet.appendRow([
    TextCellValue('الاسم'),
    TextCellValue('الباركود'),
    TextCellValue('السعر'),
    TextCellValue('سعر الشراء'),
    TextCellValue('المخزون'),
    TextCellValue('التصنيف'),
    TextCellValue('طريقة البيع'),
    TextCellValue('قطع لكل كرتونة'),
  ]);

  for (final p in products) {
    sheet.appendRow([
      TextCellValue(p.name),
      TextCellValue(p.barcode),
      DoubleCellValue(p.price),
      DoubleCellValue(p.purchasePrice),
      DoubleCellValue(p.stock),
      TextCellValue(p.category),
      TextCellValue(p.saleType),
      IntCellValue(p.piecesPerCarton),
    ]);
  }

  final bytes = excel.encode();
  if (bytes == null) throw Exception('Failed to encode Excel file');
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File> exportSalesToExcel(List<Map<String, dynamic>> sales, String filePath) async {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'العمليات');
  final sheet = excel['العمليات'];

  sheet.appendRow([
    TextCellValue('رقم الفاتورة'),
    TextCellValue('التاريخ'),
    TextCellValue('الإجمالي'),
    TextCellValue('صافي الربح'),
    TextCellValue('عدد المنتجات'),
    TextCellValue('المنتجات'),
  ]);

  for (final s in sales) {
    String itemsStr;
    try {
      final parsed = jsonDecode(s['items'] as String) as List;
      itemsStr = parsed.map((item) {
        final m = item as Map<String, dynamic>;
        return '${m['product_name']} (x${m['quantity']})';
      }).join(', ');
    } catch (_) {
      itemsStr = s['items'] as String;
    }
    sheet.appendRow([
      IntCellValue(s['id'] as int),
      TextCellValue(s['created_at'] as String),
      DoubleCellValue((s['total'] as num).toDouble()),
      DoubleCellValue((s['total_profit'] as num).toDouble()),
      IntCellValue(s['items_count'] as int),
      TextCellValue(itemsStr),
    ]);
  }

  final bytes = excel.encode();
  if (bytes == null) throw Exception('Failed to encode Excel file');
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File> exportSalesBackupToExcel(List<Map<String, dynamic>> sales, String filePath) async {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'نسخة_احتياطية');
  final sheet = excel['نسخة_احتياطية'];

  sheet.appendRow([
    TextCellValue('رقم الفاتورة'),
    TextCellValue('التاريخ'),
    TextCellValue('الإجمالي'),
    TextCellValue('صافي الربح'),
    TextCellValue('عدد المنتجات'),
    TextCellValue('عناصر_JSON'),
    TextCellValue('معرف_العميل'),
    TextCellValue('اسم_العميل'),
  ]);

  for (final s in sales) {
    sheet.appendRow([
      IntCellValue(s['id'] as int),
      TextCellValue(s['created_at'] as String),
      DoubleCellValue((s['total'] as num).toDouble()),
      DoubleCellValue((s['total_profit'] as num).toDouble()),
      IntCellValue(s['items_count'] as int),
      TextCellValue(s['items'] as String),
      TextCellValue(s['customer_id']?.toString() ?? ''),
      TextCellValue(s['customer_name'] as String? ?? ''),
    ]);
  }

  final bytes = excel.encode();
  if (bytes == null) throw Exception('Failed to encode Excel file');
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<File> exportStatsToExcel(Map<String, double> stats, String filePath) async {
  final excel = Excel.createExcel();
  excel.rename('Sheet1', 'التقارير_المالية');
  final sheet = excel['التقارير_المالية'];

  sheet.appendRow([TextCellValue('البيان'), TextCellValue('القيمة ($kCurrencySymbol)')]);
  sheet.appendRow([TextCellValue('إجمالي المبيعات'), DoubleCellValue(stats['totalSales'] ?? 0)]);
  sheet.appendRow([TextCellValue('إجمالي التكلفة'), DoubleCellValue(stats['totalCost'] ?? 0)]);
  sheet.appendRow([TextCellValue('صافي الربح'), DoubleCellValue(stats['totalProfit'] ?? 0)]);

  final bytes = excel.encode();
  if (bytes == null) throw Exception('Failed to encode Excel file');
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}

Future<List<Product>> importProductsFromExcel(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  if (bytes.length > 10 * 1024 * 1024) {
    throw Exception('حجم الملف كبير جداً (الحد الأقصى 10MB)');
  }
  final excel = Excel.decodeBytes(bytes);
  var sheet = excel.tables[excel.tables.keys.first];
  if (sheet == null || sheet.maxRows == 0) {
    for (final name in excel.tables.keys) {
      final s = excel.tables[name];
      if (s != null && s.maxRows > 0) { sheet = s; break; }
    }
  }
  if (sheet == null) throw Exception('لا يوجد جدول في ملف Excel');

  final products = <Product>[];
  final rows = sheet.rows;

  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length < 4) continue;
    try {
      final name = row[0]?.value?.toString().trim() ?? '';
      final barcode = row[1]?.value?.toString().trim() ?? '';
      final price = double.tryParse(row[2]?.value?.toString() ?? '0') ?? 0;
      final purchasePrice = row.length > 3 ? (double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0.0) : 0.0;
      final stock = row.length > 4 ? (double.tryParse(row[4]?.value?.toString() ?? '0') ?? 0.0) : 0.0;
      final category = row.length > 5 ? row[5]?.value?.toString().trim() ?? 'عام' : 'عام';
      final saleType = row.length > 6 ? (row[6]?.value?.toString().trim() ?? 'unit') : 'unit';
      final piecesPerCarton = row.length > 7 ? (int.tryParse(row[7]?.value?.toString() ?? '1') ?? 1) : 1;

      if (name.isEmpty || barcode.isEmpty || price <= 0) continue;
      if (price > 1e9 || purchasePrice < 0 || purchasePrice > 1e9) continue;
      if (stock < 0 || stock > 1e9) continue;
      if (name.length > 200 || barcode.length > 200) continue;

      products.add(Product(
        name: name,
        barcode: barcode,
        price: price,
        purchasePrice: purchasePrice,
        stock: stock,
        category: category,
        saleType: saleType,
        piecesPerCarton: piecesPerCarton,
      ));
    } catch (_) {
      continue;
    }
  }
  return products;
}

Future<List<Map<String, dynamic>>> importSalesFromExcel(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  if (bytes.length > 10 * 1024 * 1024) {
    throw Exception('حجم الملف كبير جداً (الحد الأقصى 10MB)');
  }
  final excel = Excel.decodeBytes(bytes);
  var sheet = excel.tables[excel.tables.keys.first];
  if (sheet == null || sheet.maxRows == 0) {
    for (final name in excel.tables.keys) {
      final s = excel.tables[name];
      if (s != null && s.maxRows > 0) { sheet = s; break; }
    }
  }
  if (sheet == null) throw Exception('لا يوجد جدول في ملف Excel');

  final sales = <Map<String, dynamic>>[];
  final rows = sheet.rows;

  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length < 6) continue;
    try {
      final itemsRaw = row[5]?.value?.toString() ?? '';
      List<dynamic>? parsedItems;
      try {
        final decoded = jsonDecode(itemsRaw);
        if (decoded is List) parsedItems = decoded;
      } catch (_) {}
      if (parsedItems == null || parsedItems.isEmpty) continue;

      final total = double.tryParse(row[2]?.value?.toString() ?? '0') ?? 0;
      final totalProfit = double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0;
      final itemsCount = int.tryParse(row[4]?.value?.toString() ?? '0') ?? 0;

      if (total < 0 || total > 1e9) continue;
      if (totalProfit < -1e9 || totalProfit > 1e9) continue;
      if (itemsCount < 0 || itemsCount > 10000) continue;
      if (itemsCount != parsedItems.length) continue;

      sales.add({
        'created_at': row[1]?.value?.toString() ?? '',
        'total': total,
        'total_profit': totalProfit,
        'items_count': itemsCount,
        'items': jsonEncode(parsedItems),
        if (row.length > 6 && (row[6]?.value?.toString() ?? '').isNotEmpty)
          'customer_id': int.tryParse(row[6]!.value.toString()),
        if (row.length > 7 && (row[7]?.value?.toString() ?? '').isNotEmpty)
          'customer_name': row[7]!.value.toString(),
      });
    } catch (_) {
      continue;
    }
  }
  return sales;
}

Future<File> exportDebtsToExcel(
  List<Map<String, dynamic>> debtSummary,
  List<Map<String, dynamic>> debtSales,
  List<Map<String, dynamic>> debtPayments,
  String filePath,
) async {
  final excel = Excel.createExcel();

  excel.rename('Sheet1', 'ملخص_الديون');
  final summarySheet = excel['ملخص_الديون'];
  summarySheet.appendRow([
    TextCellValue('اسم العميل'),
    TextCellValue('إجمالي الديون'),
    TextCellValue('المسدد'),
    TextCellValue('المتبقي'),
  ]);
  for (final d in debtSummary) {
    final name = d['name'] as String? ?? '';
    final totalDebt = (d['total_debt'] as num?)?.toDouble() ?? 0;
    final totalPaid = (d['total_paid'] as num?)?.toDouble() ?? 0;
    summarySheet.appendRow([
      TextCellValue(name),
      DoubleCellValue(totalDebt),
      DoubleCellValue(totalPaid),
      DoubleCellValue(totalDebt - totalPaid),
    ]);
  }

  final salesSheet = excel['فواتير_الديون'];
  salesSheet.appendRow([
    TextCellValue('رقم الفاتورة'),
    TextCellValue('التاريخ'),
    TextCellValue('الإجمالي'),
    TextCellValue('صافي الربح'),
    TextCellValue('عدد المنتجات'),
    TextCellValue('عناصر_JSON'),
    TextCellValue('اسم_العميل'),
  ]);
  for (final s in debtSales) {
    salesSheet.appendRow([
      IntCellValue(s['id'] as int),
      TextCellValue(s['created_at'] as String? ?? ''),
      DoubleCellValue((s['total'] as num?)?.toDouble() ?? 0),
      DoubleCellValue((s['total_profit'] as num?)?.toDouble() ?? 0),
      IntCellValue(s['items_count'] as int? ?? 0),
      TextCellValue(s['items'] as String? ?? ''),
      TextCellValue(s['customer_name'] as String? ?? ''),
    ]);
  }

  final paymentsSheet = excel['المدفوعات'];
  paymentsSheet.appendRow([
    TextCellValue('اسم_العميل'),
    TextCellValue('المبلغ'),
    TextCellValue('التاريخ'),
  ]);
  for (final p in debtPayments) {
    paymentsSheet.appendRow([
      TextCellValue(p['customer_name'] as String? ?? ''),
      DoubleCellValue((p['amount'] as num?)?.toDouble() ?? 0),
      TextCellValue(p['created_at'] as String? ?? ''),
    ]);
  }

  final bytes = excel.encode();
  if (bytes == null) throw Exception('Failed to encode Excel file');
  final file = File(filePath);
  await file.writeAsBytes(bytes, flush: true);
  return file;
}