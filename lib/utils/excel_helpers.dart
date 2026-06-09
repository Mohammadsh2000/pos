import 'dart:io';
import 'package:excel/excel.dart';
import '../models/product.dart';

Future<File> exportProductsToExcel(List<Product> products, String filePath) async {
  final excel = Excel.createExcel();
  final sheet = excel['المنتجات'];

  sheet.appendRow([
    TextCellValue('الاسم'),
    TextCellValue('الباركود'),
    TextCellValue('السعر'),
    TextCellValue('سعر الشراء'),
    IntCellValue(0),
    TextCellValue('التصنيف'),
  ]);

  for (final p in products) {
    sheet.appendRow([
      TextCellValue(p.name),
      TextCellValue(p.barcode),
      DoubleCellValue(p.price),
      DoubleCellValue(p.purchasePrice),
      IntCellValue(p.stock),
      TextCellValue(p.category),
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
  final sheet = excel['العمليات'];

  sheet.appendRow([
    TextCellValue('رقم الفاتورة'),
    TextCellValue('التاريخ'),
    TextCellValue('الإجمالي'),
    TextCellValue('صافي الربح'),
    IntCellValue(0),
    TextCellValue('المنتجات'),
  ]);

  for (final s in sales) {
    final items = (s['items'] as String).split('; ').join(', ');
    sheet.appendRow([
      IntCellValue(s['id'] as int),
      TextCellValue(s['created_at'] as String),
      DoubleCellValue((s['total'] as num).toDouble()),
      DoubleCellValue((s['total_profit'] as num).toDouble()),
      IntCellValue(s['items_count'] as int),
      TextCellValue(items),
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
  final sheet = excel['نسخة_احتياطية'];

  sheet.appendRow([
    TextCellValue('رقم الفاتورة'),
    TextCellValue('التاريخ'),
    TextCellValue('الإجمالي'),
    TextCellValue('صافي الربح'),
    IntCellValue(0),
    TextCellValue('عناصر_JSON'),
  ]);

  for (final s in sales) {
    sheet.appendRow([
      IntCellValue(s['id'] as int),
      TextCellValue(s['created_at'] as String),
      DoubleCellValue((s['total'] as num).toDouble()),
      DoubleCellValue((s['total_profit'] as num).toDouble()),
      IntCellValue(s['items_count'] as int),
      TextCellValue(s['items'] as String),
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
  final sheet = excel['التقارير_المالية'];

  sheet.appendRow([TextCellValue('البيان'), TextCellValue('القيمة (ر.س)')]);
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
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables[excel.tables.keys.first];
  if (sheet == null) throw Exception('No sheet found in Excel file');

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
      final stock = row.length > 4 ? (int.tryParse(row[4]?.value?.toString() ?? '0') ?? 0) : 0;
      final category = row.length > 5 ? row[5]?.value?.toString().trim() ?? 'عام' : 'عام';

      if (name.isEmpty || barcode.isEmpty || price <= 0) continue;

      products.add(Product(
        name: name,
        barcode: barcode,
        price: price,
        purchasePrice: purchasePrice,
        stock: stock,
        category: category,
      ));
    } catch (_) {
      continue;
    }
  }
  return products;
}

Future<List<Map<String, dynamic>>> importSalesFromExcel(String filePath) async {
  final bytes = await File(filePath).readAsBytes();
  final excel = Excel.decodeBytes(bytes);
  final sheet = excel.tables[excel.tables.keys.first];
  if (sheet == null) throw Exception('No sheet found in Excel file');

  final sales = <Map<String, dynamic>>[];
  final rows = sheet.rows;

  for (int i = 1; i < rows.length; i++) {
    final row = rows[i];
    if (row.length < 6) continue;
    try {
      sales.add({
        'id': int.tryParse(row[0]?.value?.toString() ?? '0') ?? 0,
        'created_at': row[1]?.value?.toString() ?? '',
        'total': double.tryParse(row[2]?.value?.toString() ?? '0') ?? 0,
        'total_profit': double.tryParse(row[3]?.value?.toString() ?? '0') ?? 0,
        'items_count': int.tryParse(row[4]?.value?.toString() ?? '0') ?? 0,
        'items': row[5]?.value?.toString() ?? '',
      });
    } catch (_) {
      continue;
    }
  }
  return sales;
}