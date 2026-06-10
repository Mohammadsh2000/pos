import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'dart:convert';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';

final DateFormat _dateFmt = DateFormat('yyyy/MM/dd HH:mm');

class CustomerDebtDetailSheet extends StatefulWidget {
  final int customerId;
  final String customerName;

  const CustomerDebtDetailSheet({
    super.key,
    required this.customerId,
    required this.customerName,
  });

  @override
  State<CustomerDebtDetailSheet> createState() => _CustomerDebtDetailSheetState();
}

class _CustomerDebtDetailSheetState extends State<CustomerDebtDetailSheet> {
  Map<String, dynamic>? _data;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    final p = context.read<POSProvider>();
    final data = await p.getCustomerSales(widget.customerId);
    if (mounted) {
      setState(() {
        _data = data;
        _loading = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Directionality(
      textDirection: ui.TextDirection.rtl,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  child: Text(widget.customerName[0]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    widget.customerName,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 8),
            if (_loading)
              const Center(child: CircularProgressIndicator())
            else if (_data == null)
              const Center(child: Text('تعذّر تحميل البيانات'))
            else ...[
              _buildSummary(theme),
              const SizedBox(height: 12),
              Text('الفواتير', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Expanded(
                child: _buildSalesList(theme),
              ),
              const SizedBox(height: 8),
              Text('سجل الدفعات', style: theme.textTheme.titleMedium),
              const SizedBox(height: 4),
              Expanded(
                child: _buildPaymentsList(theme),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSummary(ThemeData theme) {
    final sales = (_data!['sales'] as List)
        .cast<Map<String, dynamic>>();
    final payments = (_data!['payments'] as List)
        .cast<Map<String, dynamic>>();
    final totalDebt = sales.fold(0.0, (s, sale) => s + (sale['total'] as num).toDouble());
    final totalPaid = payments.fold(0.0, (s, p) => s + (p['amount'] as num).toDouble());
    final remaining = totalDebt - totalPaid;
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          _InfoChip(label: 'الفواتير', value: '${sales.length}'),
          const SizedBox(width: 8),
          _InfoChip(label: 'إجمالي الدين', value: '${totalDebt.toStringAsFixed(2)} ر.س'),
          const SizedBox(width: 8),
          _InfoChip(label: 'المسدد', value: '${totalPaid.toStringAsFixed(2)} ر.س'),
          const SizedBox(width: 8),
          _InfoChip(
            label: 'المتبقي',
            value: '${remaining.toStringAsFixed(2)} ر.س',
            color: remaining > 0 ? theme.colorScheme.error : theme.colorScheme.primary,
          ),
        ],
      ),
    );
  }

  Widget _buildSalesList(ThemeData theme) {
    final sales = (_data!['sales'] as List)
        .cast<Map<String, dynamic>>();
    if (sales.isEmpty) {
      return Center(
        child: Text('لا توجد فواتير', style: theme.textTheme.bodySmall),
      );
    }
    return ListView.builder(
      itemCount: sales.length,
      itemBuilder: (context, i) {
        final sale = sales[i];
        final items = jsonDecode(sale['items'] as String) as List;
        return Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            dense: true,
            leading: CircleAvatar(
              radius: 14,
              backgroundColor: theme.colorScheme.primaryContainer,
              child: Text('#${sale['id']}', style: const TextStyle(fontSize: 10)),
            ),
            title: Text(
              '${items.length} منتج | ${(sale['total'] as num).toDouble().toStringAsFixed(2)} ر.س',
              style: theme.textTheme.bodySmall,
            ),
            subtitle: Text(
              _dateFmt.format(DateTime.parse(sale['created_at'] as String)),
              style: theme.textTheme.bodySmall,
            ),
          ),
        );
      },
    );
  }

  Widget _buildPaymentsList(ThemeData theme) {
    final payments = (_data!['payments'] as List)
        .cast<Map<String, dynamic>>();
    if (payments.isEmpty) {
      return Center(
        child: Text('لا توجد دفعات', style: theme.textTheme.bodySmall),
      );
    }
    return ListView.builder(
      itemCount: payments.length,
      itemBuilder: (context, i) {
        final payment = payments[i];
        return Card(
          margin: const EdgeInsets.only(bottom: 4),
          child: ListTile(
            dense: true,
            leading: Icon(Icons.payments, color: theme.colorScheme.primary, size: 20),
            title: Text(
              '${(payment['amount'] as num).toDouble().toStringAsFixed(2)} ر.س',
              style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.bold),
            ),
            subtitle: Text(
              _dateFmt.format(DateTime.parse(payment['created_at'] as String)),
              style: theme.textTheme.bodySmall,
            ),
          ),
        );
      },
    );
  }
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  final Color? color;

  const _InfoChip({
    required this.label,
    required this.value,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Expanded(
      child: Column(
        children: [
          Text(value,
            style: theme.textTheme.bodySmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
            overflow: TextOverflow.ellipsis,
          ),
          Text(label, style: theme.textTheme.bodySmall?.copyWith(fontSize: 10)),
        ],
      ),
    );
  }
}