import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../providers/pos_provider.dart';
import '../utils/invoice_pdf.dart';
import '../widgets/sale_detail_sheet.dart';

final DateFormat _historyDateFmt = DateFormat('yyyy/MM/dd HH:mm:ss');

class HistoryTab extends StatefulWidget {
  const HistoryTab({super.key});

  @override
  State<HistoryTab> createState() => _HistoryTabState();
}

class _HistoryTabState extends State<HistoryTab> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<POSProvider>().loadSales();
    });
  }

  void _showSaleDetail(Map<String, dynamic> sale) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SaleDetailSheet(
        sale: sale,
        onPrint: () => _printInvoice(sale),
      ),
    );
  }

  Future<void> _printInvoice(Map<String, dynamic> sale) async {
    await generateInvoicePdf(sale);
  }

  @override
  Widget build(BuildContext context) {
    return Selector<POSProvider, List<Map<String, dynamic>>>(
      selector: (_, p) => p.sales,
      builder: (context, sales, _) {
        if (sales.isEmpty) {
          return Center(
            child: Text(
              'لا توجد فواتير سابقة',
              style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          );
        }
        return RefreshIndicator(
          onRefresh: () => context.read<POSProvider>().loadSales(),
          child: ListView.builder(
            padding: const EdgeInsets.all(12),
            itemCount: sales.length,
            itemBuilder: (context, i) {
              final sale = sales[i];
              return Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text('#${sale['id']}', style: Theme.of(context).textTheme.bodySmall),
                  ),
                  title: Text('${sale['items_count']} منتجات | ${sale['total']} ر.س'),
                  subtitle: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        _historyDateFmt.format(
                          DateTime.parse(sale['created_at'] as String),
                        ),
                      ),
                      if (sale['customer_name'] != null &&
                          (sale['customer_name'] as String).isNotEmpty)
                        Text(
                          'عميل: ${sale['customer_name']}',
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: Theme.of(context).colorScheme.primary,
                          ),
                        ),
                    ],
                  ),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.print),
                        onPressed: () => _printInvoice(sale),
                      ),
                      IconButton(
                        icon: const Icon(Icons.chevron_left),
                        onPressed: () => _showSaleDetail(sale),
                      ),
                    ],
                  ),
                  onTap: () => _showSaleDetail(sale),
                ),
              );
            },
          ),
        );
      },
    );
  }
}
