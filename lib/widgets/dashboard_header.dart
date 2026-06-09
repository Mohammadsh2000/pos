import 'dart:io';
import 'package:flutter/material.dart';
import 'dart:ui' as ui;
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../utils/excel_helpers.dart';
import '../screens/sale_tab.dart';
import 'statistics_dialog.dart';
import 'data_management_sheet.dart';

final DateFormat _archiveTimestampFmt = DateFormat('yyyy_MM_dd_HHmm');

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        return Container(
          padding: EdgeInsetsDirectional.fromSTEB(16, MediaQuery.of(context).padding.top + 12, 8, 8),
          decoration: BoxDecoration(
            color: Theme.of(context).colorScheme.primaryContainer,
          ),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  kStoreName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              IconButton(
                icon: Stack(
                  clipBehavior: Clip.none,
                  children: [
                    const Icon(Icons.history),
                    if (p.parkedCartCount > 0)
                      Positioned(
                        top: -4,
                        right: -10,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                          decoration: BoxDecoration(
                            color: Theme.of(context).colorScheme.error,
                            borderRadius: BorderRadius.circular(10),
                          ),
                          constraints: const BoxConstraints(minWidth: 16),
                          child: Text(
                            '${p.parkedCartCount}',
                            style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                  ],
                ),
                tooltip: 'الفواتير المعلقة',
                onPressed: () {
                  showModalBottomSheet(
                    context: context,
                    useSafeArea: true,
                    builder: (ctx) => Directionality(
                      textDirection: ui.TextDirection.rtl,
                      child: const ParkedCartsList(),
                    ),
                  );
                },
              ),
              PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (v) {
                  if (v == 'stats') {
                    showDialog(
                      context: context,
                      useSafeArea: false,
                      builder: (_) => const StatisticsDialog(),
                    );
                  } else if (v == 'data') {
                    showModalBottomSheet(
                      context: context,
                      isScrollControlled: true,
                      builder: (_) => const DataManagementSheet(),
                    );
                  } else if (v == 'archive') {
                    showArchiveConfirm(context, p);
                  }
                },
                itemBuilder: (_) => [
                  const PopupMenuItem(
                    value: 'stats',
                    child: ListTile(
                      title: Text('الإحصائيات المالية'),
                      leading: Icon(Icons.bar_chart),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'data',
                    child: ListTile(
                      title: Text('إدارة البيانات'),
                      leading: Icon(Icons.storage),
                      dense: true,
                    ),
                  ),
                  const PopupMenuItem(
                    value: 'archive',
                    child: ListTile(
                      title: Text('أرشفة وتوفير مساحة'),
                      leading: Icon(Icons.archive),
                      dense: true,
                    ),
                  ),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  void showArchiveConfirm(BuildContext context, POSProvider provider) {
    final messenger = ScaffoldMessenger.of(context);
    final salesCount = provider.sales.length;
    if (salesCount == 0) {
      messenger.showSnackBar(const SnackBar(content: Text('لا توجد عمليات للأرشفة')));
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('أرشفة وتوفير مساحة'),
          content: Text('سيتم أرشفة $salesCount عملية مع إنشاء نسخة احتياطية Excel. هل تود المتابعة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                Navigator.pop(ctx);
                try {
                  final timestamp = _archiveTimestampFmt.format(DateTime.now());
                  final salesData = await provider.getAllSalesRaw();
                  final tempDir = await getTemporaryDirectory();
                  final tempPath = '${tempDir.path}/temp_archive_$timestamp.xlsx';
                  try {
                    await exportSalesBackupToExcel(salesData, tempPath);
                    final bytes = await File(tempPath).readAsBytes();
                    final savedPath = await FilePicker.saveFile(
                      dialogTitle: 'حفظ النسخة الاحتياطية',
                      fileName: 'Archive_$timestamp.xlsx',
                      bytes: bytes,
                    );
                    if (savedPath == null) return;
                  } finally {
                    final f = File(tempPath);
                    if (await f.exists()) await f.delete();
                  }
                  await provider.updateBackupDate();
                  final msg = await provider.archiveSales();
                  messenger.showSnackBar(
                    SnackBar(content: Text(msg ?? 'تمت الأرشفة بنجاح.')),
                  );
                } catch (e) {
                  messenger.showSnackBar(SnackBar(content: Text('فشلت الأرشفة: $e')));
                }
              },
              child: const Text('تأكيد الأرشفة'),
            ),
          ],
        ),
      ),
    );
  }
}
