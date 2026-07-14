import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../utils/notifications.dart';
import 'purchase_invoice_preview_screen.dart';

final DateFormat _dateFmt = DateFormat('dd/MM/yyyy', 'en');
final DateFormat _timeFmt = DateFormat('HH:mm', 'en');

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

  Future<void> _print(int purchaseId) async {
    final purchase = _purchases.firstWhere((p) => p['id'] == purchaseId);
    final items = await context.read<POSProvider>().getPurchaseItems(purchaseId);
    if (!mounted) return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PurchaseInvoicePreviewScreen(purchase: purchase, items: items),
      ),
    );
  }

  Future<void> _reverse(int purchaseId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('تراجع عن فاتورة الشراء'),
        content: const Text('هل أنت متأكد من التراجع عن هذه الفاتورة؟ سيتم إرجاع المخزون والتكاليف إلى حالتها السابقة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تراجع'),
            style: FilledButton.styleFrom(backgroundColor: Colors.red.shade700),
          ),
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

  double get _totalCost => _purchases.fold(0.0, (s, p) => s + (p['total'] as num).toDouble());

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('سجل فواتير الشراء', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            if (!_loading && _purchases.isNotEmpty)
              Text(
                '${_purchases.length} فاتورة | إجمالي ${_totalCost.toStringAsFixed(3)} $kCurrencySymbol',
                style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
              ),
          ],
        ),
        centerTitle: false,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back_rounded),
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
                      Container(
                        width: 80, height: 80,
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary.withValues(alpha: 0.08),
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Icon(Icons.receipt_long_outlined, size: 40, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                      ),
                      const SizedBox(height: 16),
                      Text('لا توجد فواتير شراء', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(height: 4),
                      Text('عند إضافة فاتورة شراء ستظهر هنا', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                    ],
                  ),
                )
              : RefreshIndicator(
                  onRefresh: _load,
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
                    itemCount: _purchases.length,
                    itemBuilder: (context, i) => _buildPurchaseCard(theme, _purchases[i]),
                  ),
                ),
    );
  }

  Widget _buildPurchaseCard(ThemeData theme, Map<String, dynamic> purchase) {
    final id = purchase['id'] as int;
    final total = (purchase['total'] as num).toDouble();
    final itemsCount = (purchase['items_count'] as num).toInt();
    final merchantName = purchase['merchant_name'] as String?;
    final dt = DateTime.parse(purchase['created_at'] as String);
    final expanded = _expanded.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.4)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            InkWell(
              onTap: () => setState(() {
                if (expanded) { _expanded.remove(id); } else { _expanded.add(id); }
              }),
              borderRadius: expanded ? null : BorderRadius.circular(16),
              child: Container(
                padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                decoration: BoxDecoration(
                  border: expanded ? Border(bottom: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3))) : null,
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44, height: 44,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: [theme.colorScheme.primary.withValues(alpha: 0.7), theme.colorScheme.primary],
                          begin: Alignment.topLeft, end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Center(
                        child: Text(
                          '#$id',
                          style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w800, color: Colors.white, height: 1.1),
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
                              Icon(Icons.calendar_today, size: 13, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(_dateFmt.format(dt), style: theme.textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 12)),
                              const SizedBox(width: 10),
                              Icon(Icons.access_time, size: 13, color: theme.colorScheme.onSurfaceVariant),
                              const SizedBox(width: 4),
                              Text(_timeFmt.format(dt), style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant, fontSize: 11)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Row(
                            children: [
                              _Tag(
                                icon: Icons.inventory_2,
                                label: '$itemsCount منتج',
                                color: Colors.green.shade600,
                              ),
                              if (merchantName != null && merchantName.trim().isNotEmpty) ...[
                                const SizedBox(width: 8),
                                _Tag(
                                  icon: Icons.store_outlined,
                                  label: merchantName,
                                  color: Colors.blue.shade600,
                                ),
                              ],
                            ],
                          ),
                        ],
                      ),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('${total.toStringAsFixed(3)} $kCurrencySymbol',
                          style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 4),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.08),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(expanded ? 'طيّ' : 'تفاصيل',
                                style: TextStyle(fontSize: 11, color: theme.colorScheme.primary, fontWeight: FontWeight.w600),
                              ),
                              Icon(
                                expanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                                size: 16, color: theme.colorScheme.primary,
                              ),
                            ],
                          ),
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
                  if (!snap.hasData) return const Padding(padding: EdgeInsets.all(24), child: Center(child: CircularProgressIndicator(strokeWidth: 2)));
                  final items = snap.data!;
                  return _buildExpandedContent(theme, id, items, total);
                },
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildExpandedContent(ThemeData theme, int id, List<Map<String, dynamic>> items, double total) {
    double totalQty = 0;

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 28, height: 28,
                decoration: BoxDecoration(
                  color: theme.colorScheme.primary.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(Icons.shopping_bag_outlined, size: 16, color: theme.colorScheme.primary),
              ),
              const SizedBox(width: 8),
              Text('المنتجات', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
              const Spacer(),
              Text('${items.length} صنف', style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant)),
            ],
          ),
          const SizedBox(height: 10),
          Container(
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(12),
            ),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: Column(
                children: [
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    color: Colors.grey.shade800,
                    child: Row(
                      children: [
                        const Expanded(flex: 3, child: Text('المنتج', style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                        const SizedBox(width: 48, child: Text('الكمية', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                        const Expanded(flex: 2, child: Text('التكلفة', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                        const Expanded(flex: 2, child: Text('الإجمالي', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w600))),
                      ],
                    ),
                  ),
                  ...List.generate(items.length, (i) {
                    final item = items[i];
                    final qty = (item['quantity'] as num).toDouble();
                    final cost = (item['cost'] as num).toDouble();
                    final subtotal = (item['subtotal'] as num).toDouble();
                    totalQty += qty;
                    return Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                      color: i.isOdd ? Colors.grey.shade50 : Colors.white,
                      child: Row(
                        children: [
                          Expanded(flex: 3, child: Text(item['product_name'] as String, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w500))),
                          SizedBox(
                            width: 48,
                            child: Text('${_fmt(qty)}', textAlign: TextAlign.center, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                          ),
                          Expanded(flex: 2, child: Text('${_fmt(cost)} $kCurrencySymbol', textAlign: TextAlign.center, style: TextStyle(fontSize: 11, color: Colors.grey.shade600))),
                          Expanded(flex: 2, child: Text('${_fmt(subtotal)} $kCurrencySymbol', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold))),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.green.shade50, Colors.green.shade100.withValues(alpha: 0.5)],
                begin: Alignment.centerRight, end: Alignment.centerLeft,
              ),
              border: Border.all(color: Colors.green.shade200.withValues(alpha: 0.5)),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(
              children: [
                Container(
                  width: 32, height: 32,
                  decoration: BoxDecoration(
                    color: Colors.green.shade200.withValues(alpha: 0.5),
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Icon(Icons.receipt_long, size: 16, color: Colors.green.shade700),
                ),
                const SizedBox(width: 10),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('المجموع الكلي', style: TextStyle(fontSize: 11, color: Colors.green.shade700, fontWeight: FontWeight.w600)),
                    Text('${_fmt(totalQty)} قطعة', style: TextStyle(fontSize: 10, color: Colors.green.shade600)),
                  ],
                ),
                const Spacer(),
                Text('${_fmt(total)} $kCurrencySymbol',
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green.shade800),
                ),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _print(id),
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('طباعة'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: theme.colorScheme.primary,
                    side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  onPressed: () => _reverse(id),
                  icon: const Icon(Icons.undo_rounded, size: 18),
                  label: const Text('تراجع'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: Colors.red.shade700,
                    side: BorderSide(color: Colors.red.shade200),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _fmt(num v) => v == v.roundToDouble() ? v.toInt().toString() : v.toStringAsFixed(3);
}

class _Tag extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;

  const _Tag({required this.icon, required this.label, required this.color});

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: color),
        const SizedBox(width: 3),
        Text(label,
          style: TextStyle(fontSize: 12, color: color, fontWeight: FontWeight.w600),
        ),
      ],
    );
  }
}
