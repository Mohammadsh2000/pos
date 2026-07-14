import 'dart:io';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../utils/excel_helpers.dart';
import '../screens/login_screen.dart';
import 'statistics_dialog.dart';
import 'data_management_sheet.dart';
import '../utils/notifications.dart';
import '../services/auth_service.dart';

final DateFormat _archiveTimestampFmt = DateFormat('yyyy_MM_dd_HHmm');

class SettingsSheet extends StatelessWidget {
  const SettingsSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final p = context.read<POSProvider>();
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
      ),
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        children: [
          Row(
            children: [
              Expanded(
                child: Text('الإعدادات', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ),
              IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
                visualDensity: VisualDensity.compact,
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text('إدارة المتجر والبيانات', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 16),
          _SettingsTile(
            icon: Icons.bar_chart_rounded,
            title: 'الإحصائيات المالية',
            subtitle: 'عرض المبيعات والأرباح',
            color: const Color(0xFF7C3AED),
            onTap: () {
              Navigator.pop(context);
              showDialog(context: context, useSafeArea: false, builder: (_) => const StatisticsDialog());
            },
          ),
          _SettingsTile(
            icon: Icons.storage_rounded,
            title: 'إدارة البيانات',
            subtitle: 'تصدير واستيراد Excel',
            color: const Color(0xFF0891B2),
            onTap: () {
              Navigator.pop(context);
              showModalBottomSheet(context: context, isScrollControlled: true, builder: (_) => const DataManagementSheet());
            },
          ),
          _SettingsTile(
            icon: Icons.archive_rounded,
            title: 'أرشفة السجل',
            subtitle: 'أرشفة العمليات مع نسخة Excel',
            color: const Color(0xFFF97316),
            onTap: () {
              Navigator.pop(context);
              _showArchiveConfirm(context, p);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          Text('المتجر', style: theme.textTheme.labelLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          _SettingsTile(
            icon: Icons.store_rounded,
            title: 'معلومات المتجر',
            subtitle: kStoreName,
            color: const Color(0xFF0F172A),
            onTap: () {
              Navigator.pop(context);
              _showStoreInfoDialog(context, p);
            },
          ),
          _SettingsTile(
            icon: Icons.monetization_on_rounded,
            title: 'رمز العملة',
            subtitle: p.currencySymbol,
            color: const Color(0xFF16A34A),
            onTap: () {
              Navigator.pop(context);
              _showCurrencyDialog(context, p);
            },
          ),
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Divider(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          _SettingsTile(
            icon: Icons.logout_rounded,
            title: 'تسجيل الخروج',
            subtitle: 'إنهاء الجلسة الحالية',
            color: const Color(0xFFDC2626),
            onTap: () => _logout(context),
          ),
        ],
      ),
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
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, ctrl.text.trim()), child: const Text('حفظ')),
        ],
      ),
    ).then((v) {
      if (v == null || v.isEmpty || !context.mounted) return;
      provider.setCurrencySymbol(v as String);
    });
  }

  void _showStoreInfoDialog(BuildContext context, POSProvider provider) {
    final nameCtrl = TextEditingController(text: kStoreName);
    final addressCtrl = TextEditingController(text: kStoreAddress);
    final phoneCtrl = TextEditingController(text: kStorePhone);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('معلومات المتجر'),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          TextField(controller: nameCtrl, decoration: const InputDecoration(labelText: 'اسم المتجر', border: OutlineInputBorder()), autofocus: true),
          const SizedBox(height: 12),
          TextField(controller: addressCtrl, decoration: const InputDecoration(labelText: 'العنوان', border: OutlineInputBorder())),
          const SizedBox(height: 12),
          TextField(controller: phoneCtrl, decoration: const InputDecoration(labelText: 'رقم الهاتف', border: OutlineInputBorder()), keyboardType: TextInputType.phone),
        ]),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () {
            final name = nameCtrl.text.trim();
            if (name.isEmpty) return;
            provider.setStoreInfo(name, addressCtrl.text.trim(), phoneCtrl.text.trim());
            Navigator.pop(ctx);
          }, child: const Text('حفظ')),
        ],
      ),
    );
  }

  Future<void> _logout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تسجيل الخروج'),
        content: const Text('هل أنت متأكد من تسجيل الخروج؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), style: FilledButton.styleFrom(backgroundColor: Colors.red), child: const Text('تسجيل الخروج')),
        ],
      ),
    );
    if (confirmed == true) {
      final prefs = await SharedPreferences.getInstance();
      await prefs.remove('isLoggedIn');
      await prefs.remove('uid');
      await AuthService.instance.signOut();
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pushAndRemoveUntil(
          MaterialPageRoute(builder: (_) => const LoginScreen()),
          (_) => false,
        );
      }
    }
  }

  void _showArchiveConfirm(BuildContext context, POSProvider provider) {
    final salesCount = provider.sales.length;
    if (salesCount == 0) {
      showTopNotification(context, 'لا توجد عمليات للأرشفة');
      return;
    }
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('أرشفة السجل'),
        content: Text('سيتم أرشفة $salesCount عملية مع إنشاء نسخة احتياطية Excel. هل تود المتابعة؟'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('إلغاء')),
          FilledButton(onPressed: () async {
            Navigator.pop(ctx);
            try {
              final timestamp = _archiveTimestampFmt.format(DateTime.now());
              final salesData = await provider.getAllSalesRaw();
              final tempDir = await getTemporaryDirectory();
              final tempPath = '${tempDir.path}/temp_archive_$timestamp.xlsx';
              try {
                await exportSalesBackupToExcel(salesData, tempPath);
                final bytes = await File(tempPath).readAsBytes();
                final savedPath = await FilePicker.saveFile(dialogTitle: 'حفظ النسخة الاحتياطية', fileName: 'Archive_$timestamp.xlsx', bytes: bytes);
                if (savedPath == null) return;
              } finally {
                final f = File(tempPath);
                if (await f.exists()) await f.delete();
              }
              await provider.updateBackupDate();
              final msg = await provider.archiveSales();
              showSuccessNotification(context, msg ?? 'تمت الأرشفة بنجاح.');
            } catch (e) {
              showTopNotification(context, 'فشلت الأرشفة: $e');
            }
          }, child: const Text('تأكيد الأرشفة')),
        ],
      ),
    );
  }
}

class _SettingsTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final Color color;
  final VoidCallback onTap;

  const _SettingsTile({
    required this.icon,
    required this.title,
    required this.subtitle,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 6),
      elevation: 0,
      color: theme.colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                  ],
                ),
              ),
              Icon(Icons.chevron_left, size: 20, color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.5)),
            ],
          ),
        ),
      ),
    );
  }
}
