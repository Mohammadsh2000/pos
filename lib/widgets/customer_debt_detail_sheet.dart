import 'dart:convert';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import 'sale_detail_sheet.dart';
import '../utils/notifications.dart';

final DateFormat _dateFmt = DateFormat('yyyy/MM/dd');
final DateFormat _timeFmt = DateFormat('HH:mm');

class CustomerDebtDetailSheet extends StatefulWidget {
  final int customerId;
  final String customerName;

  const CustomerDebtDetailSheet({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  @override
  State<CustomerDebtDetailSheet> createState() =>
      _CustomerDebtDetailSheetState();
}

class _CustomerDebtDetailSheetState extends State<CustomerDebtDetailSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;
  int? _editingPaymentId;
  late TextEditingController _editCtrl;
  int? _deletingPaymentId;
  late String _customerName;
  int _lastDebtVersion = 0;

  @override
  void initState() {
    super.initState();
    _customerName = widget.customerName;
    _editCtrl = TextEditingController();
    _lastDebtVersion = context.read<POSProvider>().debtVersion;
    _loadData();
  }

  @override
  void dispose() {
    _editCtrl.dispose();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
  }

  Future<void> _loadData() async {
    final p = context.read<POSProvider>();
    final data = await p.getCustomerSales(widget.customerId);
    if (mounted)
      setState(() {
        _data = data;
        _loading = false;
        if (data != null) {
          final name = data['name'] as String?;
          if (name != null && name.isNotEmpty) _customerName = name;
        }
      });
  }

  double _totalDebt(List<Map<String, dynamic>> sales) {
    return sales.fold(0.0, (s, sale) => s + (sale['total'] as num).toDouble());
  }

  double _totalPaid(List<Map<String, dynamic>> payments) {
    return payments.fold(0.0, (s, p) => s + (p['amount'] as num).toDouble());
  }

  @override
  Widget build(BuildContext context) {
    final v = context.select<POSProvider, int>((p) => p.debtVersion);
    if (_data != null && v != _lastDebtVersion) {
      _lastDebtVersion = v;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _loadData();
      });
    }
    final theme = Theme.of(context);
    return SafeArea(
      top: true,
      bottom: false,
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 8),
            _buildHandle(theme),
            const SizedBox(height: 8),
            _buildHeader(theme),
            const SizedBox(height: 16),
            if (_loading)
              const Expanded(child: Center(child: CircularProgressIndicator()))
            else if (_data == null)
              const Expanded(child: Center(child: Text('تعذّر تحميل البيانات')))
            else ...[
              _buildSummary(theme),
              const SizedBox(height: 16),
              Expanded(child: _buildTabContent(theme)),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  Widget _buildHandle(ThemeData theme) {
    return Center(
      child: Container(
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader(ThemeData theme) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Row(
        children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              _customerName.isNotEmpty
                  ? _customerName[0].toUpperCase()
                  : '?',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 18,
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: GestureDetector(
              onTap: () => _editCustomer(theme),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _customerName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (_data != null && _data!['phone'] != null && (_data!['phone'] as String).isNotEmpty)
                    Text(
                      _data!['phone'] as String,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                ],
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined, size: 20),
            onPressed: () => _editCustomer(theme),
            tooltip: 'تعديل البيانات',
          ),
          IconButton(
            icon: Icon(Icons.delete_outline, size: 20, color: Colors.red.shade400),
            onPressed: () => _deleteCustomer(theme),
            tooltip: 'حذف العميل',
          ),
          IconButton(
            icon: const Icon(Icons.close_rounded),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Future<void> _deleteCustomer(ThemeData theme) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('حذف العميل'),
          content: const Text('سيتم حذف العميل وبيانات ديونه. المبيعات السابقة ستبقى محفوظة.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: TextButton.styleFrom(foregroundColor: Colors.red),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (ok != true || !mounted) return;
    final p = context.read<POSProvider>();
    final err = await p.deleteCustomer(widget.customerId);
    if (!mounted) return;
    if (err != null) {
      showTopNotification(context, err);
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _editCustomer(ThemeData theme) async {
    final nameCtrl = TextEditingController(text: _customerName);
    final phoneCtrl = TextEditingController(text: _data?['phone'] as String? ?? '');
    final formKey = GlobalKey<FormState>();

    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
          title: const Text('تعديل بيانات العميل'),
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
                    labelText: 'رقم الجوال',
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
              child: const Text('حفظ'),
            ),
          ],
        ),
      ),
    );

    if (result == null || result.isEmpty) return;
    final p = context.read<POSProvider>();
    final err = await p.updateCustomer(widget.customerId, result, phone: phoneCtrl.text.trim());
    if (mounted) {
      if (err != null) {
        showTopNotification(context, err);
      } else {
        _customerName = result;
        _loadData();
      }
    }
  }

  Widget _buildSummary(ThemeData theme) {
    final sales = (_data!['sales'] as List).cast<Map<String, dynamic>>();
    final payments = (_data!['payments'] as List).cast<Map<String, dynamic>>();
    final totalDebt = _totalDebt(sales);
    final totalPaid = _totalPaid(payments);
    final remaining = totalDebt - totalPaid;
    final paidPercent = totalDebt > 0
        ? (totalPaid / totalDebt).clamp(0.0, 1.0)
        : 0.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
        ),
        padding: const EdgeInsets.all(16),
        child: Column(
          children: [
            Row(
              children: [
                _Metric(
                  label: 'إجمالي الدين',
                  value: '${totalDebt.toStringAsFixed(2)} $kCurrencySymbol',
                  color: theme.colorScheme.onSurface,
                ),
                const SizedBox(width: 8),
                _Metric(
                  label: 'المسدد',
                  value: '${totalPaid.toStringAsFixed(2)} $kCurrencySymbol',
                  color: Colors.green.shade700,
                ),
                const SizedBox(width: 8),
                _Metric(
                  label: 'المتبقي',
                  value: '${remaining.toStringAsFixed(2)} $kCurrencySymbol',
                  color: remaining > 0
                      ? theme.colorScheme.error
                      : theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
            const SizedBox(height: 12),
            ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: paidPercent,
                minHeight: 6,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                valueColor: AlwaysStoppedAnimation<Color>(
                  paidPercent >= 0.5
                      ? Colors.green
                      : paidPercent >= 0.25
                      ? Colors.orange
                      : theme.colorScheme.error,
                ),
              ),
            ),
            const SizedBox(height: 4),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: Text(
                '${(paidPercent * 100).toStringAsFixed(0)}% مسدد',
                style: theme.textTheme.labelSmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabContent(ThemeData theme) {
    final sales = (_data!['sales'] as List).cast<Map<String, dynamic>>();
    final payments = (_data!['payments'] as List).cast<Map<String, dynamic>>();

    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          TabBar(
            tabs: [
              Tab(text: 'الفواتير (${sales.length})'),
              Tab(text: 'المدفوعات (${payments.length})'),
            ],
            labelStyle: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
            ),
            indicatorSize: TabBarIndicatorSize.tab,
          ),
          Expanded(
            child: TabBarView(
              children: [
                _buildSalesList(theme, sales),
                _buildPaymentsList(theme, payments),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSalesList(ThemeData theme, List<Map<String, dynamic>> sales) {
    if (sales.isEmpty) {
      return Center(
        child: Text(
          'لا توجد فواتير',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    return ListView.builder(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
      itemCount: sales.length,
      itemBuilder: (context, i) {
        final sale = sales[i];
        final items = jsonDecode(sale['items'] as String) as List;
        final saleDate = DateTime.parse(sale['created_at'] as String);
        final total = (sale['total'] as num).toDouble();
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: theme.colorScheme.surface,
            borderRadius: BorderRadius.circular(14),
            child: InkWell(
              borderRadius: BorderRadius.circular(14),
              onTap: () {
                showModalBottomSheet(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => SaleDetailSheet(sale: sale, onPrint: null),
                ).then((_) {
                  if (mounted) _loadData();
                });
              },
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: theme.colorScheme.outlineVariant.withValues(
                      alpha: 0.5,
                    ),
                  ),
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 12,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: Colors.blue.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '#${sale['id']}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: Colors.blue.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Icon(
                                  Icons.shopping_bag_outlined,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  '${items.length} منتج',
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Icon(
                                  Icons.access_time,
                                  size: 14,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Text(
                                  _timeFmt.format(saleDate),
                                  style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 4),
                            Text(
                              _dateFmt.format(saleDate),
                              style: theme.textTheme.bodyMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          '$total $kCurrencySymbol',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                            color: Colors.green.shade700,
                          ),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        Icons.chevron_left,
                        color: theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentsList(
    ThemeData theme,
    List<Map<String, dynamic>> payments,
  ) {
    if (payments.isEmpty) {
      return Center(
        child: Text(
          'لا توجد دفعات',
          style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
        ),
      );
    }
    final p = context.read<POSProvider>();
    return Column(
      children: [
        if (payments.length > 1)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: SizedBox(
              width: double.infinity,
              child: OutlinedButton.icon(
                icon: const Icon(Icons.merge, size: 18),
                label: const Text('دمج الدفعات'),
                onPressed: () => _confirmConsolidate(p),
              ),
            ),
          ),
        Expanded(
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            itemCount: payments.length,
            itemBuilder: (context, i) {
              final payment = payments[i];
              final id = payment['id'] as int;
              final payDate = DateTime.parse(payment['created_at'] as String);
              final amount = (payment['amount'] as num).toDouble();
              final isEditing = _editingPaymentId == id;
              final isDeleting = _deletingPaymentId == id;

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 14,
                      vertical: 10,
                    ),
                    child: AnimatedSwitcher(
                      duration: const Duration(milliseconds: 200),
                      child: isEditing
                          ? _buildEditRow(p, id, amount, theme)
                          : isDeleting
                          ? _buildDeleteRow(p, id, theme)
                          : _buildPaymentRow(payDate, amount, id, theme, p),
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _confirmConsolidate(POSProvider p) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('دمج الدفعات'),
        content: const Text(
          'سيتم دمج جميع الدفعات في دفعة واحدة بقيمة إجمالية. هل أنت متأكد؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final err = await p.consolidatePayments(widget.customerId);
    if (mounted) {
      if (err != null) {
        showTopNotification(context, err);
      }
      _loadData();
    }
  }

  Widget _buildPaymentRow(
    DateTime payDate,
    double amount,
    int id,
    ThemeData theme,
    POSProvider p,
  ) {
    return Row(
      key: ValueKey('payment_$id'),
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: Colors.green.shade50,
          child: Icon(
            Icons.account_balance_wallet_outlined,
            size: 18,
            color: Colors.green.shade700,
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${amount.toStringAsFixed(2)} $kCurrencySymbol',
                style: theme.textTheme.bodyMedium?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                '${_dateFmt.format(payDate)} ${_timeFmt.format(payDate)}',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.edit_outlined,
              size: 18,
              color: theme.colorScheme.primary,
            ),
            onPressed: () {
              _editCtrl.text = amount.toStringAsFixed(2);
              setState(() => _editingPaymentId = id);
            },
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.delete_outline,
              size: 18,
              color: theme.colorScheme.error,
            ),
            onPressed: () => setState(() => _deletingPaymentId = id),
          ),
        ),
      ],
    );
  }

  Widget _buildEditRow(POSProvider p, int id, double current, ThemeData theme) {
    return Row(
      key: const ValueKey('edit'),
      children: [
        CircleAvatar(
          radius: 16,
          backgroundColor: Colors.amber.shade50,
          child: Icon(Icons.edit, size: 16, color: Colors.amber.shade700),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: 100,
          height: 36,
          child: TextField(
            controller: _editCtrl,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            style: theme.textTheme.bodyMedium?.copyWith(
              fontWeight: FontWeight.w600,
            ),
            decoration: InputDecoration(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 8,
                vertical: 4,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(8),
              ),
              isDense: true,
            ),
            autofocus: true,
          ),
        ),
        const Spacer(),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(Icons.check, size: 18, color: Colors.green.shade700),
            onPressed: () async {
              final amount = double.tryParse(_editCtrl.text);
              if (amount == null || amount <= 0) return;
              setState(() => _editingPaymentId = null);
              final err = await p.updateDebtPayment(id, amount);
              if (mounted) {
                if (err != null) {
                  showTopNotification(context, err);
                }
                _loadData();
              }
            },
          ),
        ),
        const SizedBox(width: 4),
        SizedBox(
          width: 32,
          height: 32,
          child: IconButton(
            padding: EdgeInsets.zero,
            icon: Icon(
              Icons.close,
              size: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            onPressed: () => setState(() => _editingPaymentId = null),
          ),
        ),
      ],
    );
  }

  Widget _buildDeleteRow(POSProvider p, int id, ThemeData theme) {
    return Row(
      key: const ValueKey('delete'),
      children: [
        Icon(Icons.warning_rounded, size: 18, color: theme.colorScheme.error),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            'حذف هذه الدفعة؟',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            foregroundColor: theme.colorScheme.error,
          ),
          onPressed: () async {
            setState(() => _deletingPaymentId = null);
            final err = await p.deleteDebtPayment(id);
            if (mounted) {
              if (err != null) {
                showTopNotification(context, err);
              }
              _loadData();
            }
          },
          child: const Text(
            'حذف',
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
        ),
        TextButton(
          style: TextButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            minimumSize: Size.zero,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          onPressed: () => setState(() => _deletingPaymentId = null),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }
}

class _Metric extends StatelessWidget {
  final String label;
  final String value;
  final Color color;

  const _Metric({
    required this.label,
    required this.value,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(
            label,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 4),
          Text(
            value,
            style: theme.textTheme.titleSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
