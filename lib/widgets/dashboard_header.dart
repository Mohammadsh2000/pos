import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
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
import '../utils/notifications.dart';

final DateFormat _archiveTimestampFmt = DateFormat('yyyy_MM_dd_HHmm');

class DashboardHeader extends StatelessWidget {
  const DashboardHeader({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        return ClipRect(
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(sigmaX: 8, sigmaY: 8),
            child: Container(
              padding: EdgeInsetsDirectional.fromSTEB(
                16,
                MediaQuery.of(context).padding.top + 8,
                16,
                8,
              ),
              decoration: BoxDecoration(
                color: Colors.white.withValues(alpha: 0.7),
              ),
              child: Row(
                children: [
                  Text(
                    kStoreName,
                    style: const TextStyle(
                      fontSize: 22,
                      fontWeight: FontWeight.bold,
                      color: Color(0xFF0F172A),
                    ),
                  ),
                  const Spacer(),
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
                              padding: const EdgeInsets.symmetric(
                                horizontal: 4,
                                vertical: 1,
                              ),
                              decoration: BoxDecoration(
                                color: const Color(0xFFE63946),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              constraints: const BoxConstraints(minWidth: 16),
                              child: Text(
                                '${p.parkedCartCount}',
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 10,
                                  fontWeight: FontWeight.bold,
                                ),
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
                        builder: (ctx) => const ParkedCartsList(),
                      );
                    },
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    width: 48,
                    height: 48,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        PopupMenuButton<String>(
                          icon: const Icon(Icons.settings),
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
                            } else if (v == 'currency') {
                              _showCurrencyDialog(context, p);
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
                            const PopupMenuDivider(),
                            PopupMenuItem(
                              value: 'currency',
                              child: ListTile(
                                title: Text('تغيير العملة: ${p.currencySymbol}'),
                                leading: const Icon(Icons.monetization_on),
                                dense: true,
                              ),
                            ),
                          ],
                        ),
                        Positioned(
                          top: 4,
                          right: 4,
                          child: Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Color(0xFFE63946),
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _showCurrencyDialog(BuildContext context, POSProvider provider) {
    final ctrl = TextEditingController(text: provider.currencySymbol);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تغيير رمز العملة'),
        content: TextField(
          controller: ctrl,
          decoration: const InputDecoration(
            labelText: 'رمز العملة',
            hintText: 'مثال: ر.س, د.ك, ﷼',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, ctrl.text.trim()),
            child: const Text('حفظ'),
          ),
        ],
      ),
    ).then((v) {
      if (v == null || v.isEmpty || !context.mounted) return;
      provider.setCurrencySymbol(v as String);
    });
  }

  void showArchiveConfirm(BuildContext context, POSProvider provider) {
    final salesCount = provider.sales.length;
    if (salesCount == 0) {
      showTopNotification(context, 'لا توجد عمليات للأرشفة');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أرشفة وتوفير مساحة'),
        content: Text(
          'سيتم أرشفة $salesCount عملية مع إنشاء نسخة احتياطية Excel. هل تود المتابعة؟',
        ),
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
                showTopNotification(context, msg ?? 'تمت الأرشفة بنجاح.');
              } catch (e) {
                showTopNotification(context, 'فشلت الأرشفة: $e');
              }
            },
            child: const Text('تأكيد الأرشفة'),
          ),
        ],
      ),
    );
  }
}
