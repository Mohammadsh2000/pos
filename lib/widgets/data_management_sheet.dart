import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart' as fp;
import '../models/product.dart';
import '../providers/pos_provider.dart';
import '../utils/excel_helpers.dart';
import '../utils/notifications.dart';

class DataManagementSheet extends StatefulWidget {
  const DataManagementSheet({super.key});

  @override
  State<DataManagementSheet> createState() => _DataManagementSheetState();
}

class _DataManagementSheetState extends State<DataManagementSheet> {
  bool _isExporting = false;
  bool _isImporting = false;
  bool _isArchiving = false;

  static final DateFormat _archiveTimestampFmt = DateFormat('yyyy_MM_dd_HHmm');
  static final DateFormat _fileFmt = DateFormat('yyyy_MM_dd_HHmmss');

  Future<String?> _saveFileDialog(Uint8List bytes, String suggestedName) async {
    return fp.FilePicker.saveFile(
      dialogTitle: 'حفظ الملف',
      fileName: suggestedName,
      bytes: bytes,
    );
  }

  Future<void> _showExportDialog() async {
    bool products = true;
    bool sales = true;
    bool financial = false;

    final selected = await showDialog<Map<String, bool>>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تصدير البيانات'),
        content: StatefulBuilder(
          builder: (context, setInnerState) => Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'اختر البيانات المراد تصديرها:',
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              const SizedBox(height: 8),
              CheckboxListTile(
                title: const Text('قائمة المنتجات'),
                subtitle: const Text(
                  'الاسم، الباركود، السعر، التكلفة، المخزون',
                ),
                value: products,
                onChanged: (v) => setInnerState(() => products = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('سجل العمليات'),
                subtitle: const Text('الفواتير، التاريخ، المنتجات المباعة'),
                value: sales,
                onChanged: (v) => setInnerState(() => sales = v ?? true),
              ),
              CheckboxListTile(
                title: const Text('التقارير المالية'),
                subtitle: const Text('إجمالي المبيعات، الأرباح، صافي الفائدة'),
                value: financial,
                onChanged: (v) => setInnerState(() => financial = v ?? true),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, <String, bool>{
              'products': true,
              'sales': true,
              'financial': true,
            }),
            child: const Text('تصدير الكل'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, <String, bool>{
              'products': products,
              'sales': sales,
              'financial': financial,
            }),
            child: const Text('تصدير المحدد'),
          ),
        ],
      ),
    );

    if (selected == null || !mounted) return;
    setState(() => _isExporting = true);

    try {
      final provider = context.read<POSProvider>();
      await provider.loadStats();
      if (!mounted) return;
      final ts = _fileFmt.format(DateTime.now());
      final tempDir = await getTemporaryDirectory();

      int successCount = 0;
      int failCount = 0;

      if (selected['products'] == true) {
        final data = await provider.getAllProductsRaw();
        if (!mounted) return;
        final tempPath = p.join(tempDir.path, 'temp_prod_$ts.xlsx');
        try {
          await exportProductsToExcel(
            data.map((m) => Product.fromMap(m)).toList(),
            tempPath,
          );
          final bytes = await File(tempPath).readAsBytes();
          final saved = await _saveFileDialog(
            bytes,
            'Products_Export_$ts.xlsx',
          );
          if (saved != null) {
            successCount++;
          } else {
            failCount++;
          }
        } finally {
          final f = File(tempPath);
          if (await f.exists()) await f.delete();
        }
      }

      if (selected['sales'] == true) {
        final data = await provider.getAllSalesRaw();
        if (!mounted) return;
        final tempPath = p.join(tempDir.path, 'temp_sales_$ts.xlsx');
        try {
          await exportSalesToExcel(data, tempPath);
          final bytes = await File(tempPath).readAsBytes();
          final saved = await _saveFileDialog(bytes, 'Sales_Export_$ts.xlsx');
          if (saved != null) {
            successCount++;
          } else {
            failCount++;
          }
        } finally {
          final f = File(tempPath);
          if (await f.exists()) await f.delete();
        }
      }

      if (selected['financial'] == true) {
        if (!mounted) return;
        final proceed = showDialog<bool>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('تنبيه'),
            content: const Text(
              'هذا الملف يحتوي على بيانات مالية حساسة. يرجى التعامل معه بحذر.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('إلغاء'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('متابعة'),
              ),
            ],
          ),
        );
        final result = await proceed;
        if (result != true) {
          setState(() => _isExporting = false);
          return;
        }
        if (!mounted) return;
        final stats = <String, double>{
          'totalSales': provider.totalSalesAllTime,
          'totalCost': provider.totalCostAllTime,
          'totalProfit': provider.totalProfitAllTime,
        };
        final tempPath = p.join(tempDir.path, 'temp_fin_$ts.xlsx');
        try {
          await exportStatsToExcel(stats, tempPath);
          final bytes = await File(tempPath).readAsBytes();
          final saved = await _saveFileDialog(
            bytes,
            'Financial_Report_$ts.xlsx',
          );
          if (saved != null) {
            successCount++;
          } else {
            failCount++;
          }
        } finally {
          final f = File(tempPath);
          if (await f.exists()) await f.delete();
        }
      }

      if (!mounted) return;
      if (successCount > 0) {
        showTopNotification(context, 'تم حفظ $successCount ملف بنجاح');
      } else if (failCount > 0) {
        showTopNotification(context, 'لم يتم حفظ أي ملف');
      }
    } catch (e) {
      if (!mounted) return;
      showTopNotification(context, 'فشل التصدير: $e');
    } finally {
      if (mounted) {
        setState(() => _isExporting = false);
      }
    }
  }

  Future<void> _archive() async {
    final provider = context.read<POSProvider>();
    final salesData = await provider.getAllSalesRaw();
    if (salesData.isEmpty) {
      showTopNotification(context, 'لا توجد عمليات للأرشفة');
      return;
    }
    if (!context.mounted) return;
    final ctx = context;
    final confirmed = await showDialog<bool>(
      context: ctx,
      builder: (ctx) => AlertDialog(
        title: const Text('أرشفة وتوفير مساحة'),
        content: Text(
          'سيتم أرشفة ${salesData.length} عملية مع إنشاء نسخة احتياطية. هل تود المتابعة؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الأرشفة'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _isArchiving = true);
    try {
      final timestamp = _archiveTimestampFmt.format(DateTime.now());
      final tempDir = await getTemporaryDirectory();
      final tempPath = p.join(tempDir.path, 'temp_archive_$timestamp.xlsx');
      try {
        await exportSalesBackupToExcel(salesData, tempPath);
        final bytes = await File(tempPath).readAsBytes();
        final savedPath = await _saveFileDialog(
          bytes,
          'Archive_$timestamp.xlsx',
        );
        if (savedPath == null) {
          setState(() => _isArchiving = false);
          return;
        }
      } finally {
        final f = File(tempPath);
        if (await f.exists()) await f.delete();
      }
      await provider.updateBackupDate();
      if (!mounted) return;
      final msg = await provider.archiveSales();
      if (!mounted) return;
      showTopNotification(context, msg ?? 'تمت الأرشفة بنجاح.');
    } catch (e) {
      if (!mounted) return;
      showTopNotification(context, 'فشلت الأرشفة: $e');
    } finally {
      if (mounted) setState(() => _isArchiving = false);
    }
  }

  Future<void> _import() async {
    final importType = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('اختر نوع الاستيراد'),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'products'),
            child: const ListTile(
              leading: Icon(Icons.inventory_2),
              title: Text('منتجات'),
              subtitle: Text('استيراد قائمة منتجات من Excel'),
              dense: true,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'sales'),
            child: const ListTile(
              leading: Icon(Icons.receipt),
              title: Text('عمليات'),
              subtitle: Text('استيراد فواتير سابقة من Excel'),
              dense: true,
            ),
          ),
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, 'archive'),
            child: const ListTile(
              leading: Icon(Icons.restore),
              title: Text('ملف أرشفة'),
              subtitle: Text('استعادة الإحصائيات من نسخة احتياطية Excel'),
              dense: true,
            ),
          ),
        ],
      ),
    );
    if (importType == null || !mounted) return;

    final provider = context.read<POSProvider>();
    setState(() => _isImporting = true);
    try {
      final result = await fp.FilePicker.pickFiles(
        type: fp.FileType.custom,
        allowedExtensions: ['xlsx'],
      );
      if (!mounted) return;
      if (result == null || result.files.isEmpty) {
        setState(() => _isImporting = false);
        return;
      }
      String? filePath = result.files.single.path;
      if (filePath == null) {
        final bytes = result.files.single.bytes;
        if (bytes == null) {
          if (mounted) {
            showTopNotification(context, 'فشل الاستيراد: تعذر الوصول إلى الملف');
          }
          setState(() => _isImporting = false);
          return;
        }
        final tempDir = await getTemporaryDirectory();
        filePath = p.join(tempDir.path, 'import_temp.xlsx');
        await File(filePath).writeAsBytes(bytes, flush: true);
      }
      String? err;
      if (importType == 'products') {
        err = await provider.importProducts(filePath);
      } else if (importType == 'sales') {
        err = await provider.importSales(filePath);
      } else {
        err = await provider.importArchivedSales(filePath);
      }
      if (!mounted) return;
      if (err != null) {
        showTopNotification(context, err);
      } else {
        final msg = importType == 'products'
            ? 'تم استيراد المنتجات بنجاح'
            : importType == 'sales'
            ? 'تم استيراد العمليات بنجاح'
            : 'تمت استعادة الإحصائيات بنجاح';
        showSuccessNotification(context, msg);
        Navigator.pop(context);
      }
    } catch (e) {
      if (!mounted) return;
      showTopNotification(context, 'فشل الاستيراد: $e');
    } finally {
      if (mounted) setState(() => _isImporting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.fromLTRB(
        16,
        16,
        16,
        MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'إدارة البيانات',
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            onPressed: _isExporting ? null : _showExportDialog,
            icon: _isExporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_upload_outlined),
            label: Text(_isExporting ? 'جارٍ التصدير...' : 'تصدير البيانات'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _isImporting ? null : _import,
            icon: _isImporting
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.file_download_outlined),
            label: Text(_isImporting ? 'جارٍ الاستيراد...' : 'استيراد'),
          ),
          const SizedBox(height: 12),
          FilledButton.tonalIcon(
            onPressed: _isArchiving ? null : _archive,
            icon: _isArchiving
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Icon(Icons.archive_outlined),
            label: Text(
              _isArchiving ? 'جارٍ الأرشفة...' : 'أرشفة وتوفير مساحة',
            ),
          ),
          const SizedBox(height: 12),
          Text(
            'Excel (.xlsx)',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
              color: Theme.of(context).colorScheme.outline,
            ),
          ),
        ],
      ),
    );
  }
}
