import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/pos_provider.dart';

class StatisticsDialog extends StatefulWidget {
  const StatisticsDialog({super.key});

  @override
  State<StatisticsDialog> createState() => _StatisticsDialogState();
}

class _StatisticsDialogState extends State<StatisticsDialog> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POSProvider>().loadStats();
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog.fullscreen(
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: Consumer<POSProvider>(
          builder: (context, p, _) {
            return Scaffold(
              appBar: AppBar(
                title: const Text('الإحصائيات المالية'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  children: [
                    Card(
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          children: [
                            Row(
                              children: [
                                Icon(Icons.trending_up, color: theme.colorScheme.primary),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text('إجمالي المبيعات', style: theme.textTheme.titleSmall),
                                ),
                                Text(
                                  '${p.totalSalesAllTime.toStringAsFixed(2)} ر.س',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Icon(Icons.trending_down, color: Colors.orange),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text('إجمالي التكلفة', style: theme.textTheme.titleSmall),
                                ),
                                Text(
                                  '${p.totalCostAllTime.toStringAsFixed(2)} ر.س',
                                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                                ),
                              ],
                            ),
                            const Divider(height: 24),
                            Row(
                              children: [
                                Icon(Icons.account_balance, color: p.totalProfitAllTime >= 0 ? Colors.green : Colors.red),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text('صافي الربح', style: theme.textTheme.titleSmall),
                                ),
                                Text(
                                  '${p.totalProfitAllTime.toStringAsFixed(2)} ر.س',
                                  style: theme.textTheme.titleMedium?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: p.totalProfitAllTime >= 0 ? Colors.green : Colors.red,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
