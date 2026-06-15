import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../utils/notifications.dart';

final DateFormat _dateFmt = DateFormat('dd/MM/yyyy', 'en');
final DateFormat _timeFmt = DateFormat('HH:mm:ss', 'en');

class PurchaseHistoryScreen extends StatefulWidget {
  const PurchaseHistoryScreen({super.key});

  @override
  State<PurchaseHistoryScreen> createState() => _PurchaseHistoryScreenState();
}

class _PurchaseHistoryScreenState extends State<PurchaseHistoryScreen> {
  List<Map<String, dynamic>> _purchases = [];
  final Set<int> _expanded = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final p = await context.read<POSProvider>().getAllPurchases();
    if (mounted) setState(() { _purchases = p; _loading = false; });
  }

  Future<void> _reverse(int purchaseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تراجع عن فاتورة الشراء'),
        content: const Text('هل أنت متأكد من التراجع عن هذه الفاتورة؟ سيتم إرجاع المخزون والتكاليف إلى حالتها السابقة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تراجع')),
        ],
      ),
    );
    if (confirmed != true) return;

    final ok = await context.read<POSProvider>().reversePurchase(purchaseId);
    if (!mounted) return;
    if (ok) {
      showSuccessNotification(context, 'تم التراجع عن الفاتورة بنجاح');
      _load();
    } else {
      showTopNotification(context, 'فشل التراجع عن الفاتورة');
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: const Text('سجل الشراء'),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () => Navigator.pop(context),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _purchases.isEmpty
              ? Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.receipt_long_outlined, size: 64, color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: 8),
                      Text('لا توجد فواتير شراء', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.fromLTRB(12, 8, 12, 24),
                  itemCount: _purchases.length,
                  itemBuilder: (context, i) => _buildPurchaseCard(theme, _purchases[i]),
                ),
    );
  }

  Widget _buildPurchaseCard(ThemeData theme, Map<String, dynamic> purchase) {
    final id = purchase['id'] as int;
    final total = (purchase['total'] as num).toDouble();
    final itemsCount = (purchase['items_count'] as num).toInt();
    final dt = DateTime.parse(purchase['created_at'] as String);
    final expanded = _expanded.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Card(
        margin: EdgeInsets.zero,
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        color: theme.colorScheme.surface,
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() {
                if (expanded) { _expanded.remove(id); } else { _expanded.add(id); }
              }),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 14),
                decoration: BoxDecoration(
                  border: expanded ? Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3))) : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 40, height: 40,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [Colors.green.shade400, Colors.green.shade700],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(10),
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '#$id',
                        style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.calendar_today, size: 12, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(_dateFmt.format(dt), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
                              const SizedBox(width: 10),
                              Icon(Icons.access_time, size: 12, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(_timeFmt.format(dt), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 4),
                          Row(
                            children: [
                              Icon(Icons.inventory_2, size: 13, color: Colors.green.shade600),
                              const SizedBox(width: 4),
                              Text('$itemsCount منتج', style: theme.textTheme.labelSmall?.copyWith(color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${total.toStringAsFixed(3)} $kCurrencySymbol',
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        const SizedBox(height: 2),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(expanded ? 'طيّ' : 'تفاصيل', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 10)),
                            const SizedBox(width: 2),
                            Icon(expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, size: 16, color: theme.colorScheme.onSurfaceVariant),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ),
            if (expanded) ...[
              FutureBuilder<List<Map<String, dynamic>>>(
                future: context.read<POSProvider>().getPurchaseItems(id),
                builder: (context, snap) {
                  if (!snap.hasData) return const Padding(padding: EdgeInsets.all(20), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                  final items = snap.data!;
                  double totalQty = 0;
                  return Column(
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
                        child: Row(
                          children: [
                            Text('المنتجات', style: theme.textTheme.labelMedium?.copyWith(fontWeight: FontWeight.w600, color: theme.colorScheme.onSurfaceVariant)),
                            const Spacer(),
                            Text('الكمية', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            const SizedBox(width: 32),
                            Text('الإجمالي', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 4),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
                        child: Column(
                          children: items.map((item) {
                            final qty = (item['quantity'] as num).toDouble();
                            totalQty += qty;
                            return Padding(
                              padding: const EdgeInsets.symmetric(vertical: 4),
                              child: Row(
                                children: [
                                  Expanded(
                                    child: Text(item['product_name'] as String, style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w500)),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                    decoration: BoxDecoration(
                                      color: Colors.green.shade50,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text('x${_fmt(qty)}', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                                  ),
                                  const SizedBox(width: 12),
                                  SizedBox(
                                    width: 72,
                                    child: Text('${_fmt(item['subtotal'] as num)} $kCurrencySymbol',
                                      style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
                                      textAlign: TextAlign.right,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          }).toList(),
                        ),
                      ),
                      Container(
                        margin: const EdgeInsets.symmetric(horizontal: 14),
                        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 12),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.receipt_long, size: 14, color: Colors.green.shade700),
                            const SizedBox(width: 6),
                            Text('المجموع', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade800)),
                            const Spacer(),
                            Text('${_fmt(totalQty)} قطعة', style: TextStyle(fontSize: 11, color: Colors.green.shade600)),
                            const SizedBox(width: 12),
                            Text('${_fmt(total)} $kCurrencySymbol', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade800)),
                          ],
                        ),
                      ),
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
                        child: SizedBox(
                          width: double.infinity,
                          height: 40,
                          child: OutlinedButton.icon(
                            onPressed: () => _reverse(id),
                            icon: const Icon(Icons.undo_rounded, size: 18),
                            label: const Text('تراجع عن الفاتورة'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: Colors.red.shade700,
                              side: BorderSide(color: Colors.red.shade200),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);
}
