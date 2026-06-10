import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models/sale_item.dart';
import '../providers/pos_provider.dart';
import 'compact_icon_button.dart';

class SaleDetailSheet extends StatefulWidget {
  final Map<String, dynamic> sale;
  final VoidCallback? onPrint;

  const SaleDetailSheet({super.key, required this.sale, this.onPrint});

  @override
  State<SaleDetailSheet> createState() => _SaleDetailSheetState();
}

class _SaleDetailSheetState extends State<SaleDetailSheet> {
  late List<SaleItem> _items;
  bool _isEditing = false;

  @override
  void initState() {
    super.initState();
    _items = (jsonDecode(widget.sale['items']) as List)
        .map((e) => SaleItem.fromMap(e as Map<String, dynamic>))
        .toList();
  }

  double get _currentTotal => _items.fold(0.0, (s, i) => s + i.subtotal);
  double get _currentProfit => _items.fold(0.0, (s, i) => s + i.profit);

  Future<void> _save() async {
    final p = context.read<POSProvider>();
    final oldItems = (jsonDecode(widget.sale['items']) as List)
        .map((e) => SaleItem.fromMap(e as Map<String, dynamic>))
        .toList();
    final err = await p.updateSale(
      widget.sale['id'] as int,
      _currentTotal,
      _currentProfit,
      oldItems,
      _items,
    );
    if (!mounted) {
      return;
    }
    if (err != null) {
      await showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('خطأ'),
          content: Text(err),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
        ),
      );
    } else {
      Navigator.pop(context);
    }
  }

  Future<void> _voidSale() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الفاتورة'),
        content: const Text('سيتم إرجاع المنتجات للمخزون. هل أنت متأكد؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الإلغاء'),
          ),
        ],
      ),
    );
    if (!mounted) {
      return;
    }
    if (ok == true) {
      final p = context.read<POSProvider>();
      await p.voidSale(widget.sale['id'] as int, _items);
      if (!mounted) {
        return;
      }
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: EdgeInsets.fromLTRB(12, 12, 12, MediaQuery.of(context).viewInsets.bottom + 12),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'فاتورة #${widget.sale['id']}',
                  style: theme.textTheme.titleMedium,
                ),
              ),
              Text(
                DateFormat('yyyy/MM/dd HH:mm').format(
                  DateTime.parse(widget.sale['created_at'] as String),
                ),
                style: theme.textTheme.bodySmall,
              ),
              const SizedBox(width: 8),
              IconButton(
                constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                padding: EdgeInsets.zero,
                icon: Icon(_isEditing ? Icons.close : Icons.edit, size: 22),
                onPressed: () {
                  setState(() {
                    _isEditing = !_isEditing;
                  });
                },
              ),
            ],
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(flex: 3, child: Text('المنتج', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline))),
                      SizedBox(width: 48, child: Text('الكمية', style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline))),
                      Expanded(flex: 2, child: Text('المجموع', textAlign: TextAlign.end, style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.outline))),
                      if (_isEditing) const SizedBox(width: 28),
                    ],
                  ),
                  const Divider(height: 12),
                  SizedBox(
                    height: (_items.length * 44.0).clamp(0, 280),
                    child: ListView.builder(
                      itemCount: _items.length,
                      itemBuilder: (context, i) {
                        final item = _items[i];
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 4),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 3,
                                child: Text(item.productName, style: theme.textTheme.bodyMedium),
                              ),
                              SizedBox(
                                width: 48,
                                child: _isEditing
                                    ? TextFormField(
                                  initialValue: item.isKg ? item.quantity.toStringAsFixed(2) : item.quantity.toInt().toString(),
                                  keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                  textAlign: TextAlign.center,
                                  style: const TextStyle(fontSize: 14),
                                  decoration: const InputDecoration(
                                    isDense: true,
                                    contentPadding: EdgeInsets.symmetric(horizontal: 4, vertical: 6),
                                    border: OutlineInputBorder(),
                                  ),
                                  onChanged: (v) {
                                    final q = double.tryParse(v);
                                    if (q != null && q > 0) {
                                      if (!item.isKg && q != q.roundToDouble()) return;
                                      setState(() {
                                        _items[i].quantity = q;
                                      });
                                    }
                                  },
                                )
                                    : Center(
                                        child: Text(
                                          item.isKg
                                              ? item.quantity.toStringAsFixed(2)
                                              : (item.quantity == item.quantity.roundToDouble()
                                                  ? item.quantity.toInt().toString()
                                                  : item.quantity.toStringAsFixed(2)),
                                          style: const TextStyle(fontSize: 14),
                                        ),
                                      ),
                              ),
                              Expanded(
                                flex: 2,
                                child: Text(
                                  '${item.subtotal.toStringAsFixed(2)} $kCurrencySymbol',
                                  textAlign: TextAlign.end,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                              if (_isEditing)
                                CompactIconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                  onPressed: () {
                                    setState(() {
                                      _items.removeAt(i);
                                    });
                                  },
                                ),
                            ],
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('المجموع:', style: theme.textTheme.titleSmall),
              Text(
                '${_currentTotal.toStringAsFixed(2)} $kCurrencySymbol',
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.primary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          if (_isEditing)
            Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                FilledButton.icon(
                  onPressed: _save,
                  icon: const Icon(Icons.save, size: 20),
                  label: const Text('حفظ التعديلات'),
                ),
                const SizedBox(height: 8),
                OutlinedButton.icon(
                  onPressed: _voidSale,
                  style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                  icon: const Icon(Icons.cancel_outlined, size: 20),
                  label: const Text('إلغاء الفاتورة'),
                ),
              ],
            )
          else
            FilledButton.icon(
              onPressed: widget.onPrint,
              icon: const Icon(Icons.print, size: 20),
              label: const Text('طباعة'),
            ),
        ],
      ),
    );
  }
}
