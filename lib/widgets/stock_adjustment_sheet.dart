import 'dart:async';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/product.dart';
import '../models/adjustment_entry.dart';
import '../providers/pos_provider.dart';
import '../services/database_helper.dart';
import '../utils/notifications.dart';

class _AdjustmentItem {
  final int productId;
  final String productName;
  final double systemQty;
  final double costAtTime;
  final TextEditingController actualQtyCtrl;
  final String saleType;
  final int piecesPerCarton;

  _AdjustmentItem({
    required this.productId,
    required this.productName,
    required this.systemQty,
    required this.costAtTime,
    required double actualQty,
    this.saleType = 'unit',
    this.piecesPerCarton = 1,
  }) : actualQtyCtrl = TextEditingController(text: actualQty.toStringAsFixed(actualQty == actualQty.roundToDouble() ? 0 : 2));

  double get actualQty => double.tryParse(actualQtyCtrl.text) ?? systemQty;
  double get difference => actualQty - systemQty;

  String get qtyLabel {
    switch (saleType) {
      case 'kg': return 'الوزن (كغ)';
      case 'carton': return 'العدد (قطعة)';
      default: return 'الكمية';
    }
  }

  String get stockLabel {
    final s = systemQty == systemQty.roundToDouble()
        ? systemQty.toInt().toString()
        : systemQty.toStringAsFixed(2);
    switch (saleType) {
      case 'kg': return 'النظام: $s كغ';
      case 'carton':
        final cartons = systemQty / piecesPerCarton;
        final c = cartons == cartons.roundToDouble()
            ? cartons.toInt().toString()
            : cartons.toStringAsFixed(2);
        return 'النظام: $s قطعة ($c كرتونة)';
      default: return 'النظام: $s';
    }
  }

  void dispose() {
    actualQtyCtrl.dispose();
  }
}

class _HistoryDetailSheet extends StatelessWidget {
  final Map<String, dynamic> adjustment;
  final List<Map<String, dynamic>> items;
  final VoidCallback onReverse;

  const _HistoryDetailSheet({
    required this.adjustment,
    required this.items,
    required this.onReverse,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = kCurrencySymbol;
    final type = adjustment['type'] as String;
    final isLoss = type == 'loss';
    final totalValue = (adjustment['total_value'] as num).toDouble();
    final reason = adjustment['reason'] as String? ?? '';
    final createdAt = adjustment['created_at'] as String;
    final dateStr = _formatDate(createdAt);

    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Container(
                width: 36, height: 36,
                decoration: BoxDecoration(
                  color: isLoss ? Colors.red.shade50 : Colors.green.shade50,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  isLoss ? Icons.arrow_downward : Icons.arrow_upward,
                  color: isLoss ? Colors.red.shade600 : Colors.green.shade600,
                  size: 18,
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    isLoss ? 'تسوية فاقد / نقص' : 'تسوية زيادة',
                    style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                  ),
                  Text(dateStr, style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                ],
              ),
            ],
          ),
          if (reason.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerLowest,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.edit_note, size: 16, color: theme.colorScheme.onSurfaceVariant),
                  const SizedBox(width: 6),
                  Expanded(child: Text(reason, style: theme.textTheme.bodyMedium)),
                ],
              ),
            ),
          ],
          const SizedBox(height: 8),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerLowest,
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              children: [
                Text(
                  'القيمة: ${totalValue.abs().toStringAsFixed(2)} $currency',
                  style: TextStyle(
                    fontWeight: FontWeight.w700,
                    color: isLoss ? Colors.red.shade700 : Colors.green.shade700,
                  ),
                ),
                const Spacer(),
                Text('${items.length} منتج', style: theme.textTheme.bodySmall),
              ],
            ),
          ),
          const SizedBox(height: 12),
          Text('تفاصيل المنتجات', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
          const SizedBox(height: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 240),
            child: ListView.separated(
              shrinkWrap: true,
              itemCount: items.length,
              separatorBuilder: (_, __) => const Divider(height: 1),
              itemBuilder: (context, i) {
                final item = items[i];
                final name = item['product_name'] as String;
                final sysQty = (item['system_qty'] as num).toDouble();
                final actQty = (item['actual_qty'] as num).toDouble();
                final diff = actQty - sysQty;
                final cost = (item['cost_at_time'] as num).toDouble();
                final val = diff * cost;
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 6),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(name, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                      ),
                      Text('$sysQty → $actQty',
                        style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                      const SizedBox(width: 8),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: diff == 0 ? Colors.grey.shade100 : (diff > 0 ? Colors.green.shade50 : Colors.red.shade50),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(diff == diff.roundToDouble() ? 0 : 2)}',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                            color: diff == 0 ? Colors.grey : (diff > 0 ? Colors.green.shade700 : Colors.red.shade700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                      Text(
                        '${val.abs().toStringAsFixed(2)}',
                        style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            onPressed: () {
              Navigator.pop(context);
              onReverse();
            },
            icon: const Icon(Icons.undo, size: 18),
            label: const Text('عكس التسوية'),
            style: FilledButton.styleFrom(
              backgroundColor: Colors.orange.shade50,
              foregroundColor: Colors.orange.shade800,
              minimumSize: const Size.fromHeight(44),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('yyyy/MM/dd HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }
}

class StockAdjustmentSheet extends StatefulWidget {
  const StockAdjustmentSheet({super.key});

  @override
  State<StockAdjustmentSheet> createState() => _StockAdjustmentSheetState();
}

class _StockAdjustmentSheetState extends State<StockAdjustmentSheet> {
  final _searchCtrl = TextEditingController();
  final _reasonCtrl = TextEditingController();
  final _searchFieldKey = GlobalKey();
  String _type = 'loss';
  final List<_AdjustmentItem> _items = [];
  List<Product> _suggestions = [];
  OverlayEntry? _overlay;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _searchCtrl.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchCtrl.removeListener(_onSearchChanged);
    _searchCtrl.dispose();
    _reasonCtrl.dispose();
    _dismissOverlay();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  void _dismissOverlay() {
    _overlay?.remove();
    _overlay = null;
  }

  void _showOverlay() {
    _dismissOverlay();
    _overlay = OverlayEntry(
      builder: (_) {
        final renderBox = _searchFieldKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) return const SizedBox.shrink();
        final screenWidth = MediaQuery.of(context).size.width;
        final overlayWidth = screenWidth * 0.8;
        final pos = renderBox.localToGlobal(Offset.zero);
        final fieldWidth = renderBox.size.width;
        final left = pos.dx + (fieldWidth - overlayWidth) / 2;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: pos.dy + renderBox.size.height + 4,
              child: Material(
                elevation: 6,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(8),
                surfaceTintColor: Colors.transparent,
                child: Container(
                  width: overlayWidth,
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _suggestions.length,
                    itemBuilder: (context, i) {
                      final product = _suggestions[i];
                      final alreadyAdded = _items.any((item) => item.productId == product.id);
                      return InkWell(
                        onTap: alreadyAdded ? null : () => _addProduct(product),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            children: [
                              Icon(
                                alreadyAdded ? Icons.check_circle : Icons.shopping_bag_outlined,
                                size: 16,
                                color: alreadyAdded ? Colors.green : Theme.of(context).colorScheme.onSurfaceVariant,
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(product.name, style: TextStyle(fontSize: 13, color: alreadyAdded ? Colors.grey : null)),
                              ),
                              Text('(${product.barcode})', style: TextStyle(fontSize: 11, color: alreadyAdded ? Colors.grey : Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_overlay!);
  }

  void _onSearchChanged() {
    final text = _searchCtrl.text.trim();
    if (text.isNotEmpty) {
      DatabaseHelper().searchProducts(text).then((results) {
        if (mounted && _searchCtrl.text.trim() == text) {
          final isExactMatch = results.any((p) => p.name == text || p.barcode == text);
          if (results.isNotEmpty && !isExactMatch) {
            _suggestions = results;
            _showOverlay();
          } else {
            _suggestions = [];
            _dismissOverlay();
          }
          setState(() {});
        }
      });
    } else {
      _suggestions = [];
      _dismissOverlay();
      setState(() {});
    }
  }

  void _addProduct(Product product) {
    if (product.id == null) return;
    setState(() {
      _items.add(_AdjustmentItem(
        productId: product.id!,
        productName: product.name,
        systemQty: product.stock,
        costAtTime: product.isCarton && product.piecesPerCarton > 0
            ? product.purchasePrice / product.piecesPerCarton
            : product.purchasePrice,
        actualQty: product.stock,
        saleType: product.saleType,
        piecesPerCarton: product.piecesPerCarton,
      ));
      _searchCtrl.clear();
      _suggestions = [];
      _dismissOverlay();
    });
  }

  void _removeItem(int index) {
    setState(() {
      _items[index].dispose();
      _items.removeAt(index);
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) return;
    setState(() => _saving = true);
    final entries = <AdjustmentEntry>[];
    for (final item in _items) {
      if (item.difference == 0) continue;
      entries.add(AdjustmentEntry(
        productId: item.productId,
        productName: item.productName,
        systemQty: item.systemQty,
        actualQty: item.actualQty,
        costAtTime: item.costAtTime,
      ));
    }
    if (entries.isEmpty) {
      setState(() => _saving = false);
      showTopNotification(context, 'لم يتم تغيير أي كمية');
      return;
    }
    final reason = _reasonCtrl.text.trim();
    final err = await context.read<POSProvider>().createStockAdjustment(
      type: _type, reason: reason, entries: entries,
    );
    if (mounted) {
      setState(() => _saving = false);
      if (err != null) {
        showTopNotification(context, err);
      } else {
        if (!mounted) return;
        Navigator.pop(context, true);
      }
    }
  }

  Future<void> _openHistory() async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const _HistoryPage(),
      ),
    );
  }

  int get _lossCount => _items.where((i) => i.difference < 0).length;
  int get _gainCount => _items.where((i) => i.difference > 0).length;
  double get _totalLossValue {
    double v = 0;
    for (final i in _items) {
      if (i.difference < 0) v += i.difference.abs() * i.costAtTime;
    }
    return v;
  }
  double get _totalGainValue {
    double v = 0;
    for (final i in _items) {
      if (i.difference > 0) v += i.difference * i.costAtTime;
    }
    return v;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = kCurrencySymbol;
    return Padding(
      padding: EdgeInsets.only(
        left: 20, right: 20, top: 12,
        bottom: MediaQuery.of(context).viewInsets.bottom + 16,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Center(
            child: Container(
              width: 40, height: 4,
              decoration: BoxDecoration(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Text('تسوية المخزون', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              const Spacer(),
              if (_items.isNotEmpty)
                Text('${_items.length} منتج', style: theme.textTheme.labelMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              if (_items.isNotEmpty) const SizedBox(width: 8),
              IconButton(
                onPressed: _openHistory,
                icon: const Icon(Icons.history, size: 20),
                tooltip: 'سجل التسويات',
                style: IconButton.styleFrom(
                  backgroundColor: theme.colorScheme.surfaceContainerLow,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Row(
            children: [
              Expanded(
                child: ChoiceChip(
                  label: const Text('فاقد / نقص'),
                  selected: _type == 'loss',
                  onSelected: (_) => setState(() => _type = 'loss'),
                  selectedColor: Colors.red.shade100,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: ChoiceChip(
                  label: const Text('زيادة'),
                  selected: _type == 'gain',
                  onSelected: (_) => setState(() => _type = 'gain'),
                  selectedColor: Colors.green.shade100,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          SizedBox(
            height: 44,
            child: TextField(
              key: _searchFieldKey,
              controller: _searchCtrl,
              decoration: InputDecoration(
                hintText: 'ابحث عن منتج بالاسم أو الباركود...',
                prefixIcon: Icon(Icons.search, size: 20, color: theme.colorScheme.onSurfaceVariant),
                suffixIcon: _searchCtrl.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear, size: 18), onPressed: () => _searchCtrl.clear())
                    : null,
                filled: true,
                fillColor: theme.colorScheme.surfaceContainerLowest,
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
              ),
            ),
          ),
          if (_items.isNotEmpty) ...[
            const SizedBox(height: 8),
            Text('المنتجات المضافة', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
            const SizedBox(height: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 200),
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: _items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) {
                  final item = _items[i];
                  final diff = item.difference;
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          flex: 3,
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(item.productName, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600), maxLines: 1, overflow: TextOverflow.ellipsis),
                              const SizedBox(height: 2),
                              Text(item.stockLabel, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 80,
                          child: TextField(
                            controller: item.actualQtyCtrl,
                            keyboardType: const TextInputType.numberWithOptions(decimal: true),
                            textAlign: TextAlign.center,
                            decoration: InputDecoration(
                              isDense: true,
                              contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                              border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.colorScheme.outlineVariant)),
                              enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide(color: theme.colorScheme.outlineVariant)),
                            ),
                            style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                            onChanged: (_) => setState(() {}),
                          ),
                        ),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 60,
                          child: Text(
                            diff == 0 ? '--' : '${diff > 0 ? '+' : ''}${diff.toStringAsFixed(diff == diff.roundToDouble() ? 0 : 2)}',
                            style: theme.textTheme.bodySmall?.copyWith(
                              fontWeight: FontWeight.w700,
                              color: diff == 0 ? theme.colorScheme.onSurfaceVariant : (diff > 0 ? Colors.green.shade700 : Colors.red.shade700),
                            ),
                            textAlign: TextAlign.center,
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 28, height: 28,
                          child: IconButton(
                            onPressed: () => _removeItem(i),
                            icon: Icon(Icons.close, size: 14, color: Colors.red.shade400),
                            style: IconButton.styleFrom(
                              backgroundColor: Colors.red.shade50,
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                              padding: EdgeInsets.zero,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            if (_lossCount > 0 || _gainCount > 0) ...[
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Row(
                  children: [
                    if (_lossCount > 0) ...[
                      Icon(Icons.arrow_downward, size: 14, color: Colors.red.shade600),
                      const SizedBox(width: 4),
                      Text('خسارة: ${_totalLossValue.toStringAsFixed(2)} $currency', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.red.shade700)),
                      const SizedBox(width: 12),
                    ],
                    if (_gainCount > 0) ...[
                      Icon(Icons.arrow_upward, size: 14, color: Colors.green.shade600),
                      const SizedBox(width: 4),
                      Text('ربح: ${_totalGainValue.toStringAsFixed(2)} $currency', style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.green.shade700)),
                    ],
                  ],
                ),
              ),
            ],
          ],
          const SizedBox(height: 12),
          TextField(
            controller: _reasonCtrl,
            decoration: InputDecoration(
              hintText: 'سبب التسوية (اختياري)',
              prefixIcon: Icon(Icons.edit_note, size: 20, color: theme.colorScheme.onSurfaceVariant),
              filled: true,
              fillColor: theme.colorScheme.surfaceContainerLowest,
              border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
              contentPadding: const EdgeInsets.symmetric(vertical: 10),
            ),
          ),
          const SizedBox(height: 12),
          FilledButton.icon(
            onPressed: _items.isEmpty || _saving ? null : _save,
            icon: _saving
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                : const Icon(Icons.check_circle, size: 20),
            label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ التسوية'),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(48),
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
          ),
        ],
      ),
    );
  }
}

class _HistoryPage extends StatefulWidget {
  const _HistoryPage();

  @override
  State<_HistoryPage> createState() => _HistoryPageState();
}

class _HistoryPageState extends State<_HistoryPage> {
  List<Map<String, dynamic>> _history = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final h = await context.read<POSProvider>().getStockAdjustments();
    if (mounted) setState(() { _history = h; _loading = false; });
  }

  Future<void> _reverseAdjustment(Map<String, dynamic> adj) async {
    final id = adj['id'] as int;
    final items = await context.read<POSProvider>().getStockAdjustmentItems(id);
    if (!mounted) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('عكس التسوية'),
        content: Text('هل أنت متأكد من عكس تسوية ${adj['type'] == 'loss' ? 'الفاقد' : 'الزيادة'}؟\nسيتم إعادة المخزون لحالته السابقة.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('إلغاء')),
          FilledButton(onPressed: () => Navigator.pop(ctx, true), child: const Text('تأكيد العكس')),
        ],
      ),
    );
    if (ok != true) return;
    final err = await context.read<POSProvider>().reverseStockAdjustment(id, items);
    if (mounted) {
      if (err != null) {
        showTopNotification(context, err);
      } else {
        showTopNotification(context, 'تم عكس التسوية بنجاح');
        _load();
      }
    }
  }

  void _openDetail(Map<String, dynamic> adj) async {
    final items = await context.read<POSProvider>().getStockAdjustmentItems(adj['id'] as int);
    if (!mounted) return;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => _HistoryDetailSheet(
        adjustment: adj,
        items: items,
        onReverse: () => _reverseAdjustment(adj),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final currency = kCurrencySymbol;
    return Scaffold(
      backgroundColor: const Color(0xFFF1F5F9),
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        scrolledUnderElevation: 0.5,
        title: const Text('سجل التسويات', style: TextStyle(fontWeight: FontWeight.w700, fontSize: 18)),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.pop(context, _history.any((h) => h['_reversed'] == true)),
        ),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : _history.isEmpty
              ? Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.balance_outlined, size: 64, color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: 12),
                      Text('لا توجد تسويات سابقة', style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline)),
                    ],
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _history.length,
                  itemBuilder: (context, i) {
                    final adj = _history[i];
                    final isLoss = adj['type'] == 'loss';
                    final totalValue = (adj['total_value'] as num).toDouble();
                    final reason = adj['reason'] as String? ?? '';
                    final itemsCount = adj['items_count'] as int? ?? 0;
                    final createdAt = adj['created_at'] as String;
                    final dateStr = _formatDate(createdAt);

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: InkWell(
                        onTap: () => _openDetail(adj),
                        borderRadius: BorderRadius.circular(14),
                        child: Card(
                          margin: EdgeInsets.zero,
                          elevation: 0,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14),
                            side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          color: Colors.white,
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Row(
                              children: [
                                Container(
                                  width: 40, height: 40,
                                  decoration: BoxDecoration(
                                    color: isLoss ? Colors.red.shade50 : Colors.green.shade50,
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(
                                    isLoss ? Icons.arrow_downward : Icons.arrow_upward,
                                    color: isLoss ? Colors.red.shade600 : Colors.green.shade600,
                                    size: 18,
                                  ),
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Text(isLoss ? 'فاقد / نقص' : 'زيادة', style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w700)),
                                          const SizedBox(width: 8),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                            decoration: BoxDecoration(
                                              color: isLoss ? Colors.red.shade50 : Colors.green.shade50,
                                              borderRadius: BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              '${totalValue.abs().toStringAsFixed(1)} $currency',
                                              style: TextStyle(fontSize: 11, fontWeight: FontWeight.w700, color: isLoss ? Colors.red.shade700 : Colors.green.shade700),
                                            ),
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 2),
                                      Row(
                                        children: [
                                          Text(dateStr, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                          if (itemsCount > 0) ...[
                                            const SizedBox(width: 8),
                                            Text('$itemsCount منتج', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                          ],
                                          if (reason.isNotEmpty) ...[
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(reason, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant), maxLines: 1, overflow: TextOverflow.ellipsis),
                                            ),
                                          ],
                                        ],
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 4),
                                Icon(Icons.chevron_left, size: 20, color: theme.colorScheme.onSurfaceVariant),
                              ],
                            ),
                          ),
                        ),
                      ),
                    );
                  },
                ),
    );
  }

  String _formatDate(String iso) {
    try {
      final dt = DateTime.parse(iso);
      return DateFormat('yyyy/MM/dd HH:mm').format(dt);
    } catch (_) {
      return iso;
    }
  }
}
