import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';

class StatisticsDialog extends StatefulWidget {
  const StatisticsDialog({super.key});

  @override
  State<StatisticsDialog> createState() => _StatisticsDialogState();
}

class _StatisticsDialogState extends State<StatisticsDialog> {
  static const _rowH = 40.0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POSProvider>().loadStats();
    });
  }

  Widget _statRow(IconData icon, Color iconColor, String label, String value,
      TextStyle? valueStyle) {
    final theme = Theme.of(context);
    return SizedBox(
      height: _rowH,
      child: Row(
        children: [
          Icon(icon, size: 20, color: iconColor),
          const SizedBox(width: 12),
          Expanded(
            child: Text(label, style: theme.textTheme.titleSmall),
          ),
          Text(value, style: valueStyle ?? theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, Widget body) {
    final theme = Theme.of(context);
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
            const SizedBox(height: 8),
            body,
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFmt = DateFormat('yyyy/MM/dd HH:mm');
    return Dialog.fullscreen(
      child: Consumer<POSProvider>(
        builder: (context, p, _) {
          final archivedSalesStr =
              '${p.archivedSales.toStringAsFixed(2)} $kCurrencySymbol';
          final archivedProfitStr =
              '${p.archivedProfit.toStringAsFixed(2)} $kCurrencySymbol';

          return Scaffold(
            appBar: AppBar(
              title: const Text('الإحصائيات المالية'),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  _sectionCard(
                    'المبيعات الحالية',
                    Column(
                      children: [
                        _statRow(
                          Icons.trending_up,
                          theme.colorScheme.primary,
                          'إجمالي المبيعات',
                          '${p.currentSales.toStringAsFixed(2)} $kCurrencySymbol',
                          null,
                        ),
                        const SizedBox(height: 4),
                        _statRow(
                          Icons.trending_up,
                          Colors.green,
                          'إجمالي الأرباح',
                          '${p.currentProfit.toStringAsFixed(2)} $kCurrencySymbol',
                          null,
                        ),
                      ],
                    ),
                  ),
                  _sectionCard(
                    'المبيعات المؤرشفة',
                    Column(
                      children: [
                        _statRow(
                          Icons.archive,
                          theme.colorScheme.primary,
                          'إجمالي المبيعات',
                          archivedSalesStr,
                          null,
                        ),
                        const SizedBox(height: 4),
                        _statRow(
                          Icons.archive,
                          Colors.green,
                          'إجمالي الأرباح',
                          archivedProfitStr,
                          null,
                        ),
                        if (p.archiveHistory.isNotEmpty) ...[
                          const Divider(height: 20),
                          SizedBox(
                            height: (p.archiveHistory.length * _rowH)
                                .clamp(0, 160),
                            child: ListView.separated(
                              itemCount: p.archiveHistory.length,
                              separatorBuilder: (_, _) =>
                                  const Divider(height: 1),
                              itemBuilder: (context, i) {
                                final h = p.archiveHistory[i];
                                final date = dateFmt.format(
                                    DateTime.parse(h['archived_at'] as String));
                                final sales =
                                    '${(h['total_sales'] as num).toStringAsFixed(2)} $kCurrencySymbol';
                                final profit =
                                    '${(h['total_profit'] as num).toStringAsFixed(2)} $kCurrencySymbol';
                                return SizedBox(
                                  height: _rowH,
                                  child: Row(
                                    children: [
                                      Expanded(
                                        flex: 3,
                                        child: Text(date,
                                            style: theme.textTheme.bodySmall),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(sales,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(
                                                    fontWeight:
                                                        FontWeight.bold)),
                                      ),
                                      Expanded(
                                        flex: 2,
                                        child: Text(profit,
                                            style: theme.textTheme.bodySmall
                                                ?.copyWith(color: Colors.green)),
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                          ),
                        ] else
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text('لا توجد عمليات أرشفة',
                                style: theme.textTheme.bodySmall?.copyWith(
                                    color: theme.colorScheme.onSurface
                                        .withValues(alpha: 0.5))),
                          ),
                      ],
                    ),
                  ),
                  _sectionCard(
                    'المجموع الكلي',
                    Column(
                      children: [
                        _statRow(
                          Icons.trending_up,
                          theme.colorScheme.primary,
                          'إجمالي المبيعات',
                          '${p.totalSalesAllTime.toStringAsFixed(2)} $kCurrencySymbol',
                          null,
                        ),
                        const SizedBox(height: 4),
                        _statRow(
                          Icons.account_balance,
                          p.totalProfitAllTime >= 0 ? Colors.green : Colors.red,
                          'صافي الربح',
                          '${p.totalProfitAllTime.toStringAsFixed(2)} $kCurrencySymbol',
                          theme.textTheme.titleMedium?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: p.totalProfitAllTime >= 0
                                ? Colors.green
                                : Colors.red,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
