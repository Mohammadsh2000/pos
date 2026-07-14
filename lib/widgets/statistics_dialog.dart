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
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POSProvider>().loadStats();
    });
  }

  Widget _statCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(icon, size: 20, color: color),
              ),
              const SizedBox(width: 8),
              Text(label,
                style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey[600],
                    fontWeight: FontWeight.w500),
              ),
            ],
          ),
          const SizedBox(height: 6),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(value,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                  color: color),
            ),
          ),
        ],
      ),
    );
  }

  Widget _sectionHeader(String title, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [color.withValues(alpha: 0.12), color.withValues(alpha: 0.04)],
          begin: Alignment.centerRight,
          end: Alignment.centerLeft,
        ),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 8),
          Text(title,
              style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                  color: color)),
        ],
      ),
    );
  }

  Widget _sectionCard(String title, IconData icon, Color color, Widget body) {
    return Container(
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.04),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        children: [
          _sectionHeader(title, icon, color),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
            child: body,
          ),
        ],
      ),
    );
  }

  Widget _archiveHistoryList(List<Map<String, dynamic>> history, ThemeData theme) {
    if (history.isEmpty) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Text('لا توجد عمليات أرشفة',
            style: TextStyle(
                fontSize: 13, color: Colors.grey[400])),
      );
    }
    final dateFmt = DateFormat('yyyy/MM/dd HH:mm');
    final itemHeight = 36.0;
    final maxVisible = 5;
    final bool overflow = history.length > maxVisible;
    final visible = overflow ? history.sublist(0, maxVisible) : history;
    return Column(
      children: [
        SizedBox(
          height: (visible.length * itemHeight).clamp(0, itemHeight * maxVisible),
          child: ListView.separated(
            physics: const NeverScrollableScrollPhysics(),
            itemCount: visible.length,
            separatorBuilder: (_, _) => const SizedBox(height: 1),
            itemBuilder: (context, i) {
              final h = visible[i];
              final date = dateFmt.format(DateTime.parse(h['archived_at'] as String));
              final sales = '${(h['total_sales'] as num).toStringAsFixed(0)} $kCurrencySymbol';
              final profit = '${(h['total_profit'] as num).toStringAsFixed(0)} $kCurrencySymbol';
              return SizedBox(
                height: itemHeight,
                child: Row(
                  children: [
                    Icon(Icons.history, size: 13, color: Colors.grey[400]),
                    const SizedBox(width: 6),
                    Expanded(flex: 3, child: Text(date, style: TextStyle(fontSize: 12, color: Colors.grey[600]))),
                    Expanded(flex: 2, child: Text(sales, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey[700]))),
                    Expanded(flex: 2, child: Text(profit, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green[600]))),
                  ],
                ),
              );
            },
          ),
        ),
        if (overflow)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Text('+${history.length - maxVisible} عمليات أرشفة سابقة',
                style: TextStyle(fontSize: 12, color: Colors.grey[500])),
          ),
      ],
    );
  }

  Widget _totalSummary(double totalSales, double totalProfit, double totalCost, String currency) {
    final profitColor = totalProfit >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626);
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [const Color(0xFF7C3AED).withValues(alpha: 0.1), const Color(0xFF8B5CF6).withValues(alpha: 0.05)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: const Color(0xFF7C3AED).withValues(alpha: 0.15)),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('إجمالي المبيعات', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text('$totalSales $currency',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFF1E293B))),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.grey[200]),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('صافي الربح', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text('$totalProfit $currency',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: profitColor)),
              ],
            ),
          ),
          Container(width: 1, height: 40, color: Colors.grey[200]),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('التكلفة', style: TextStyle(fontSize: 11, color: Colors.grey[600])),
                const SizedBox(height: 4),
                Text('$totalCost $currency',
                    style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: Color(0xFFF97316))),
              ],
            ),
          ),
        ],
      ),
    );
  }

  String _fmt(num v) => v.toStringAsFixed(2);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Dialog.fullscreen(
      child: Consumer<POSProvider>(
        builder: (context, p, _) {
          final currency = kCurrencySymbol;
          return Scaffold(
            backgroundColor: const Color(0xFFF1F5F9),
            appBar: AppBar(
              backgroundColor: Colors.white,
              elevation: 0,
              scrolledUnderElevation: 0.5,
              title: const Text('الإحصائيات المالية',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
              leading: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => Navigator.pop(context),
              ),
              bottom: PreferredSize(
                preferredSize: const Size.fromHeight(1),
                child: Container(color: Colors.grey[200], height: 1),
              ),
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  _sectionCard('المبيعات الحالية', Icons.trending_up, const Color(0xFF7C3AED), Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _statCard('إجمالي المبيعات', '${_fmt(p.currentSales)} $currency', Icons.payments, const Color(0xFF7C3AED))),
                          const SizedBox(width: 10),
                          Expanded(child: _statCard('إجمالي الأرباح', '${_fmt(p.currentProfit)} $currency', Icons.savings, const Color(0xFF16A34A))),
                        ],
                      ),
                    ],
                  )),
                  _sectionCard('المبيعات المؤرشفة', Icons.archive, const Color(0xFFF97316), Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _statCard('إجمالي المبيعات', '${_fmt(p.archivedSales)} $currency', Icons.payments, const Color(0xFFF97316))),
                          const SizedBox(width: 10),
                          Expanded(child: _statCard('إجمالي الأرباح', '${_fmt(p.archivedProfit)} $currency', Icons.savings, const Color(0xFF16A34A))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      _archiveHistoryList(p.archiveHistory, theme),
                    ],
                  )),
                  _sectionCard('الإجمالي الكلي', Icons.account_balance, const Color(0xFF0F172A), Column(
                    children: [
                      _totalSummary(
                        double.parse(_fmt(p.totalSalesAllTime)),
                        double.parse(_fmt(p.totalProfitAllTime)),
                        double.parse(_fmt(p.totalCostAllTime)),
                        currency,
                      ),
                    ],
                  )),
                  if (p.totalAdjustmentLoss > 0)
                    _sectionCard('تسويات المخزون', Icons.balance, const Color(0xFFDC2626), Column(
                      children: [
                        Row(
                          children: [
                            Expanded(child: _statCard('خسائر التسوية', '${_fmt(p.totalAdjustmentLoss)} $currency', Icons.arrow_downward, const Color(0xFFDC2626))),
                            const SizedBox(width: 10),
                            Expanded(child: _statCard('صافي الربح', '${_fmt(p.netProfit)} $currency', Icons.savings, p.netProfit >= 0 ? const Color(0xFF16A34A) : const Color(0xFFDC2626))),
                          ],
                        ),
                      ],
                    )),
                  _sectionCard('معلومات عامة', Icons.info_outline, const Color(0xFF6B7280), Column(
                    children: [
                      Row(
                        children: [
                          Expanded(child: _statCard('عدد المنتجات', '${p.allProducts.length}', Icons.inventory_2, const Color(0xFF7C3AED))),
                          const SizedBox(width: 10),
                          Expanded(child: _statCard('عدد الفواتير', '${p.salesCount}', Icons.receipt_long, const Color(0xFF0891B2))),
                        ],
                      ),
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          Expanded(child: _statCard('إجمالي الديون', '${_fmt(p.totalDebts)} $currency', Icons.account_balance_wallet, const Color(0xFFDC2626))),
                          const SizedBox(width: 10),
                          Expanded(child: _statCard('المتبقي', '${_fmt(p.totalRemaining)} $currency', Icons.pending, const Color(0xFFF97316))),
                        ],
                      ),
                    ],
                  )),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
