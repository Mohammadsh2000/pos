import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:file_picker/file_picker.dart' as fp;
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../widgets/customer_debt_detail_sheet.dart';
import '../widgets/pay_debt_sheet.dart';
import '../utils/notifications.dart';

class DebtTab extends StatefulWidget {
  const DebtTab({super.key});

  @override
  State<DebtTab> createState() => _DebtTabState();
}

class _DebtTabState extends State<DebtTab> {
  final _searchCtrl = TextEditingController();
  String _searchQuery = '';
  bool _isExporting = false;
  static final DateFormat _fileFmt = DateFormat('yyyy_MM_dd_HHmmss');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POSProvider>().loadDebtData();
    });
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<Map<String, dynamic>> _filtered(List<Map<String, dynamic>> customers) {
    if (_searchQuery.isEmpty) return customers;
    return customers.where((c) {
      final name = (c['name'] as String).toLowerCase();
      return name.contains(_searchQuery);
    }).toList();
  }

  Future<void> _exportDebts() async {
    if (_isExporting) return;
    setState(() => _isExporting = true);
    try {
      final provider = context.read<POSProvider>();
      final tempDir = await getTemporaryDirectory();
      final ts = _fileFmt.format(DateTime.now());
      final tempPath = p.join(tempDir.path, 'temp_debts_$ts.xlsx');
      try {
        await provider.exportDebts(tempPath);
        final bytes = await File(tempPath).readAsBytes();
        if (!mounted) return;
        await fp.FilePicker.saveFile(
          dialogTitle: 'حفظ ملف الديون',
          fileName: 'Debts_Export_$ts.xlsx',
          bytes: bytes,
        );
        if (!mounted) return;
        showTopNotification(context, 'تم تصدير الديون بنجاح');
      } finally {
        final f = File(tempPath);
        if (await f.exists()) await f.delete();
      }
    } catch (e) {
      if (!mounted) return;
      showTopNotification(context, 'فشل التصدير: $e');
    } finally {
      if (mounted) setState(() => _isExporting = false);
    }
  }

  Future<void> _onRefresh() async {
    await context.read<POSProvider>().loadDebtData();
  }

  void _openPaySheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const PayDebtSheet(),
    );
  }

  Future<void> _addCustomer() async {
    final nameCtrl = TextEditingController();
    final phoneCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('إضافة عميل جديد'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: 'اسم العميل',
                    prefixIcon: Icon(Icons.person_outline, size: 20),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'الاسم مطلوب' : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneCtrl,
                  keyboardType: TextInputType.phone,
                  decoration: const InputDecoration(
                    labelText: 'رقم الجوال (اختياري)',
                    prefixIcon: Icon(Icons.phone_outlined, size: 20),
                    border: OutlineInputBorder(),
                  ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () {
                if (formKey.currentState!.validate()) {
                  Navigator.pop(ctx, nameCtrl.text.trim());
                }
              },
              child: const Text('إضافة'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty) return;
    final p = context.read<POSProvider>();
    final err = await p.addCustomer(result, phone: phoneCtrl.text.trim());
    if (mounted) {
      if (err != null) {
        showTopNotification(context, err);
      }
    }
  }

  void _openDetail(Map<String, dynamic> customer) async {
    final id = customer['id'] as int;
    final name = customer['name'] as String;
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => CustomerDebtDetailSheet(customerId: id, customerName: name),
    );
    if (mounted) context.read<POSProvider>().loadDebtData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        final customers = _filtered(p.debtCustomers);
        return Column(
          children: [
            _DebtSummary(
              totalDebts: p.totalDebts,
              totalPaid: p.totalPaid,
              totalRemaining: p.totalRemaining,
              theme: theme,
            ),
            _ActionBar(
              searchCtrl: _searchCtrl,
              searchQuery: _searchQuery,
              isExporting: _isExporting,
              onExport: _exportDebts,
              onPay: _openPaySheet,
              onAddCustomer: _addCustomer,
              theme: theme,
            ),
            Expanded(
              child: _buildBody(theme, p, customers),
            ),
          ],
        );
      },
    );
  }

  Widget _buildBody(ThemeData theme, POSProvider p, List<Map<String, dynamic>> customers) {
    if (p.debtCustomers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.credit_card_off_outlined, size: 72, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 12),
            Text('لا توجد ديون مسجلة', style: theme.textTheme.titleMedium?.copyWith(color: theme.colorScheme.outline)),
            const SizedBox(height: 4),
            Text('عند إتمام فاتورة باسم عميل ستظهر هنا', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }
    if (customers.isEmpty) {
      return Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_off, size: 48, color: theme.colorScheme.outlineVariant),
            const SizedBox(height: 8),
            Text('لا توجد نتائج للبحث', style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.outline)),
          ],
        ),
      );
    }
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView.builder(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
        itemCount: customers.length,
        itemBuilder: (context, i) => _CustomerCard(
          data: customers[i],
          theme: theme,
          onTap: () => _openDetail(customers[i]),
        ),
      ),
    );
  }
}

class _DebtSummary extends StatelessWidget {
  final double totalDebts;
  final double totalPaid;
  final double totalRemaining;
  final ThemeData theme;

  const _DebtSummary({
    required this.totalDebts,
    required this.totalPaid,
    required this.totalRemaining,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [theme.colorScheme.surface, theme.colorScheme.surfaceContainerLow],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
          ),
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 8),
        child: Row(
          children: [
            _SummaryItem(
              icon: Icons.account_balance_outlined,
              label: 'إجمالي الديون',
              value: totalDebts,
              color: theme.colorScheme.onSurface,
              theme: theme,
            ),
            _SummaryDivider(theme: theme),
            _SummaryItem(
              icon: Icons.check_circle_outline,
              label: 'المسدد',
              value: totalPaid,
              color: Colors.green.shade700,
              theme: theme,
            ),
            _SummaryDivider(theme: theme),
            _SummaryItem(
              icon: Icons.warning_amber_outlined,
              label: 'المتبقي',
              value: totalRemaining,
              color: totalRemaining > 0 ? theme.colorScheme.error : theme.colorScheme.onSurfaceVariant,
              theme: theme,
            ),
          ],
        ),
      ),
    );
  }
}

class _SummaryItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final double value;
  final Color color;
  final ThemeData theme;

  const _SummaryItem({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 18, color: color.withValues(alpha: 0.7)),
          const SizedBox(height: 4),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
          const SizedBox(height: 4),
          Text(
            '${value.toStringAsFixed(2)} $kCurrencySymbol',
            style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}

class _SummaryDivider extends StatelessWidget {
  final ThemeData theme;
  const _SummaryDivider({required this.theme});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 40,
      child: VerticalDivider(
        color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        thickness: 1,
        width: 1,
      ),
    );
  }
}

class _ActionBar extends StatelessWidget {
  final TextEditingController searchCtrl;
  final String searchQuery;
  final bool isExporting;
  final VoidCallback onExport;
  final VoidCallback onPay;
  final VoidCallback onAddCustomer;
  final ThemeData theme;

  const _ActionBar({
    required this.searchCtrl,
    required this.searchQuery,
    required this.isExporting,
    required this.onExport,
    required this.onPay,
    required this.onAddCustomer,
    required this.theme,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 0),
      child: Column(
        children: [
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 44,
                  child: TextField(
                    controller: searchCtrl,
                    decoration: InputDecoration(
                      hintText: 'بحث عن عميل...',
                      hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
                      prefixIcon: Icon(Icons.search, color: theme.colorScheme.onSurfaceVariant, size: 20),
                      suffixIcon: searchQuery.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.clear, size: 18),
                              onPressed: () => searchCtrl.clear(),
                            )
                          : null,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerLowest,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(12),
                        borderSide: BorderSide.none,
                      ),
                      contentPadding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Container(
                height: 44, width: 44,
                decoration: BoxDecoration(
                  color: Colors.green.shade50,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: IconButton(
                  onPressed: isExporting ? null : onExport,
                  icon: isExporting
                      ? SizedBox(
                          width: 20, height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2, color: Colors.green.shade700),
                        )
                      : Icon(Icons.file_upload_outlined, color: Colors.green.shade700, size: 20),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: SizedBox(
                  height: 46,
                  child: FilledButton.icon(
                    onPressed: onPay,
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      backgroundColor: theme.colorScheme.primary,
                    ),
                    icon: const Icon(Icons.account_balance_wallet_outlined, size: 20),
                    label: const Text('تسديد دين'),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              SizedBox(
                height: 46,
                child: OutlinedButton.icon(
                  onPressed: onAddCustomer,
                  style: OutlinedButton.styleFrom(
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  ),
                  icon: const Icon(Icons.person_add_outlined, size: 20),
                  label: const Text('إضافة عميل'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _CustomerCard extends StatelessWidget {
  final Map<String, dynamic> data;
  final ThemeData theme;
  final VoidCallback onTap;

  const _CustomerCard({
    required this.data,
    required this.theme,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final name = data['name'] as String;
    final totalDebt = (data['total_debt'] as num).toDouble();
    final totalPaid = (data['total_paid'] as num).toDouble();
    final remaining = totalDebt - totalPaid;
    final lastDate = data['last_date'] as String? ?? '';
    final isSettled = remaining <= 0;

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Material(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        elevation: 0,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
            ),
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 20,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    name.isNotEmpty ? name[0].toUpperCase() : '?',
                    style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(name, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 2),
                      Text(
                        lastDate.isNotEmpty ? DateFormat('yyyy/MM/dd').format(DateTime.parse(lastDate)) : 'لا توجد حركات',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      '${remaining.toStringAsFixed(2)} $kCurrencySymbol',
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: isSettled ? Colors.green : theme.colorScheme.error,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                        color: isSettled ? Colors.green.shade50 : Colors.red.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        isSettled ? 'مسدد بالكامل' : 'غير مسدد',
                        style: TextStyle(
                          fontSize: 10, fontWeight: FontWeight.w600,
                          color: isSettled ? Colors.green.shade700 : Colors.red.shade700,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(width: 4),
                Icon(Icons.chevron_left, color: theme.colorScheme.onSurfaceVariant, size: 20),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
