import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';
import '../widgets/customer_debt_detail_sheet.dart';

class DebtTab extends StatefulWidget {
  const DebtTab({super.key});

  @override
  State<DebtTab> createState() => _DebtTabState();
}

class _DebtTabState extends State<DebtTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POSProvider>().loadDebtData();
    });
  }

  void _showPaymentSheet(BuildContext context) {
    final nameCtrl = TextEditingController();
    final amountCtrl = TextEditingController();
    final formKey = GlobalKey<FormState>();
    int? selectedCustomerId;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.of(ctx).viewInsets.bottom,
            left: 16, right: 16, top: 16,
          ),
          child: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('تسديد دين', style: Theme.of(ctx).textTheme.titleMedium),
                const SizedBox(height: 16),
                _CustomerPaymentField(
                  controller: nameCtrl,
                  onSelected: (id) => selectedCustomerId = id,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: amountCtrl,
                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                  decoration: const InputDecoration(
                    labelText: 'المبلغ',
                    hintText: 'أدخل المبلغ المسدد',
                    prefixIcon: Icon(Icons.money),
                    border: OutlineInputBorder(),
                  ),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return 'أدخل المبلغ';
                    final amount = double.tryParse(v.trim());
                    if (amount == null || amount <= 0) return 'مبلغ غير صالح';
                    return null;
                  },
                ),
                const SizedBox(height: 16),
                SizedBox(
                  width: double.infinity,
                  child: FilledButton.icon(
                    onPressed: () async {
                      if (!formKey.currentState!.validate()) return;
                      if (selectedCustomerId == null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(
                          const SnackBar(content: Text('اختر العميل أولاً')),
                        );
                        return;
                      }
                      final amount = double.parse(amountCtrl.text.trim());
                      final p = context.read<POSProvider>();
                      final err = await p.recordDebtPayment(selectedCustomerId!, amount);
                      if (!ctx.mounted) return;
                      if (err != null) {
                        ScaffoldMessenger.of(ctx).showSnackBar(SnackBar(content: Text(err)));
                      } else {
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('تم تسجيل الدفعة بنجاح')),
                        );
                      }
                    },
                    icon: const Icon(Icons.check_circle),
                    label: const Text('تأكيد التسديد'),
                  ),
                ),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _onRefresh() async {
    await context.read<POSProvider>().loadDebtData();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: _SummaryCard(
                      label: 'إجمالي الديون',
                      value: p.totalDebts,
                      color: theme.colorScheme.error,
                      icon: Icons.account_balance_wallet,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      label: 'المسدد',
                      value: p.totalPaid,
                      color: theme.colorScheme.primary,
                      icon: Icons.check_circle_outline,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: _SummaryCard(
                      label: 'المتبقي',
                      value: p.totalRemaining,
                      color: theme.colorScheme.error,
                      icon: Icons.warning_amber,
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              child: SizedBox(
                width: double.infinity,
                child: FilledButton.icon(
                  onPressed: () => _showPaymentSheet(context),
                  icon: const Icon(Icons.payments),
                  label: const Text('تسديد دين'),
                ),
              ),
            ),
            Expanded(
              child: p.debtCustomers.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.credit_card_off, size: 64,
                              color: theme.colorScheme.outline),
                          const SizedBox(height: 8),
                          Text(
                            'لا توجد ديون مسجلة',
                            style: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                          Text(
                            'عند إتمام فاتورة باسم عميل سيتم تسجيلها هنا',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.outline,
                            ),
                          ),
                        ],
                      ),
                    )
                  : RefreshIndicator(
                      onRefresh: _onRefresh,
                      child: ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: p.debtCustomers.length,
                        itemBuilder: (context, i) {
                          final d = p.debtCustomers[i];
                          final id = d['id'] as int;
                          final name = d['name'] as String;
                          final totalDebt = (d['total_debt'] as num).toDouble();
                          final totalPaid = (d['total_paid'] as num).toDouble();
                          final remaining = totalDebt - totalPaid;
                          return Card(
                            margin: const EdgeInsets.only(bottom: 8),
                            child: ListTile(
                              leading: CircleAvatar(
                                backgroundColor: remaining > 0
                                    ? theme.colorScheme.errorContainer
                                    : theme.colorScheme.primaryContainer,
                                child: Icon(
                                  remaining > 0
                                      ? Icons.person_off
                                      : Icons.check_circle,
                                  color: remaining > 0
                                      ? theme.colorScheme.onErrorContainer
                                      : theme.colorScheme.onPrimaryContainer,
                                  size: 20,
                                ),
                              ),
                              title: Text(name,
                                  style: const TextStyle(fontWeight: FontWeight.bold)),
                              subtitle: Text(
                                totalPaid > 0
                                    ? 'إجمالي: ${totalDebt.toStringAsFixed(2)} | مسدد: ${totalPaid.toStringAsFixed(2)}'
                                    : 'إجمالي: ${totalDebt.toStringAsFixed(2)} ر.س',
                              ),
                              trailing: Column(
                                mainAxisAlignment: MainAxisAlignment.center,
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  Text(
                                    '${remaining.toStringAsFixed(2)} ر.س',
                                    style: theme.textTheme.bodyMedium?.copyWith(
                                      fontWeight: FontWeight.bold,
                                      color: remaining > 0
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary,
                                    ),
                                  ),
                                  Text(
                                    remaining > 0 ? 'متبقي' : 'مسدد بالكامل',
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: remaining > 0
                                          ? theme.colorScheme.error
                                          : theme.colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                              onTap: () {
                                showModalBottomSheet(
                                  context: context,
                                  isScrollControlled: true,
                                  builder: (_) => CustomerDebtDetailSheet(
                                    customerId: id,
                                    customerName: name,
                                  ),
                                );
                              },
                            ),
                          );
                        },
                      ),
                    ),
            ),
          ],
        );
      },
    );
  }
}

class _SummaryCard extends StatelessWidget {
  final String label;
  final double value;
  final Color color;
  final IconData icon;

  const _SummaryCard({
    required this.label,
    required this.value,
    required this.color,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Text(label, style: theme.textTheme.bodySmall?.copyWith(color: color)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            value.toStringAsFixed(2),
            style: theme.textTheme.titleMedium?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

class _CustomerPaymentField extends StatefulWidget {
  final TextEditingController controller;
  final ValueChanged<int> onSelected;

  const _CustomerPaymentField({
    required this.controller,
    required this.onSelected,
  });

  @override
  State<_CustomerPaymentField> createState() => _CustomerPaymentFieldState();
}

class _CustomerPaymentFieldState extends State<_CustomerPaymentField> {
  List<Map<String, dynamic>> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      final p = context.read<POSProvider>();
      p.searchCustomers(text).then((_) {
        if (mounted) {
          final customers = p.customerSuggestions;
          final debtCustomers = p.debtCustomers;
          setState(() {
            _suggestions = customers.map((c) {
              final debt = debtCustomers.cast<Map<String, dynamic>?>().firstWhere(
                (d) => d != null && d['id'] == c.id,
                orElse: () => null,
              );
              return {
                'id': c.id,
                'name': c.name,
                'remaining': debt != null
                    ? (debt['total_debt'] as num).toDouble() -
                        (debt['total_paid'] as num).toDouble()
                    : 0.0,
              };
            }).toList();
            _showSuggestions = _suggestions.isNotEmpty;
          });
        }
      });
    } else {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          decoration: const InputDecoration(
            labelText: 'اختر العميل',
            hintText: 'ابحث عن اسم العميل',
            prefixIcon: Icon(Icons.search),
            border: OutlineInputBorder(),
          ),
        ),
        if (_showSuggestions)
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: _suggestions.length,
              itemBuilder: (context, i) {
                final item = _suggestions[i];
                final remaining = (item['remaining'] as num).toDouble();
                return ListTile(
                  dense: true,
                  title: Text(item['name'] as String),
                  subtitle: Text(
                    'المتبقي: ${remaining.toStringAsFixed(2)} ر.س',
                    style: TextStyle(
                      color: remaining > 0
                          ? Theme.of(context).colorScheme.error
                          : Theme.of(context).colorScheme.primary,
                      fontSize: 12,
                    ),
                  ),
                  leading: const Icon(Icons.person_outline, size: 18),
                  onTap: () {
                    widget.controller.text = item['name'] as String;
                    widget.onSelected(item['id'] as int);
                    setState(() => _showSuggestions = false);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}