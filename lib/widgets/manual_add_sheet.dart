import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/pos_provider.dart';
import '../services/database_helper.dart';
import '../services/feedback_service.dart';

class ManualAddSheet extends StatefulWidget {
  const ManualAddSheet({super.key});

  @override
  State<ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends State<ManualAddSheet> {
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _manualBarcodeCtrl = TextEditingController();
  Product? _selectedProduct;
  List<Product> _suggestions = [];
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _manualBarcodeCtrl.dispose();
    super.dispose();
  }

  void _onSearch(String q) {
    _debounce?.cancel();
    if (q.isEmpty) {
      setState(() => _suggestions = const []);
      return;
    }
    _debounce = Timer(const Duration(milliseconds: 200), () {
      if (!mounted) return;
      final qLower = q.toLowerCase();
      final allProds = context.read<POSProvider>().allProducts;
      setState(() {
        _suggestions = allProds
            .where((p) =>
                p.name.toLowerCase().contains(qLower) ||
                p.barcode.contains(q))
            .take(10)
            .toList();
      });
    });
  }

  void _tryAddToCart() {
    final p = context.read<POSProvider>();
    if (_selectedProduct == null) return;
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final messenger = ScaffoldMessenger.of(context);
    final feedback = FeedbackService.instance;
    final added = p.addToCartWithQuantity(_selectedProduct!, qty);
    if (added) {
      feedback.play(ScanSound.success);
      Navigator.pop(context);
    } else {
      feedback.play(ScanSound.warning);
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            p.cart.isNotEmpty
                ? 'الكمية المطلوبة أكبر من المخزون المتاح (${_selectedProduct!.stock})'
                : 'تعذّر إضافة ${_selectedProduct!.name} للسلة',
          ),
        ),
      );
    }
  }

  Future<void> _addByBarcode() async {
    final code = _manualBarcodeCtrl.text.trim();
    if (code.isEmpty) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<POSProvider>();
    final feedback = FeedbackService.instance;
    var product = provider.findProductByBarcode(code) ??
        await DatabaseHelper().getProductByBarcode(code);
    if (!mounted) {
      return;
    }
    if (product == null) {
      feedback.play(ScanSound.unknown);
      messenger.showSnackBar(const SnackBar(content: Text('المنتج غير موجود')));
      return;
    }
    final qty = int.tryParse(_qtyCtrl.text) ?? 1;
    final added = provider.addToCartWithQuantity(product, qty);
    if (added) {
      feedback.play(ScanSound.success);
      Navigator.pop(context);
    } else {
      feedback.play(ScanSound.warning);
      messenger.showSnackBar(
        SnackBar(content: Text('المخزون غير كافٍ لـ ${product.name} (${product.stock} متاح)')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = MediaQuery.of(context).size.height - bottomInset;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: availableHeight),
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('إضافة منتج للفاتورة', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 16),
              TextField(
                controller: _searchCtrl,
                decoration: const InputDecoration(
                  labelText: 'بحث بالاسم أو الباركود',
                  prefixIcon: Icon(Icons.search),
                  border: OutlineInputBorder(),
                ),
                onChanged: _onSearch,
              ),
              if (_suggestions.isNotEmpty) ...[
                const SizedBox(height: 4),
                SizedBox(
                  height: (_suggestions.length * 52.0).clamp(0, 200),
                  child: ListView.builder(
                    itemCount: _suggestions.length,
                    itemBuilder: (context, i) {
                      final prod = _suggestions[i];
                      final selected = _selectedProduct?.id == prod.id;
                      return ListTile(
                        dense: true,
                        selected: selected,
                        title: Text(prod.name),
                        subtitle: Text('${prod.price.toStringAsFixed(2)} ر.س | المخزون: ${prod.stock}'),
                        onTap: () {
                          setState(() {
                            _selectedProduct = prod;
                            _searchCtrl.text = prod.name;
                            _suggestions = [];
                          });
                        },
                      );
                    },
                  ),
                ),
              ],
              if (_selectedProduct != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(_selectedProduct!.name, style: Theme.of(context).textTheme.titleSmall),
                            Text('${_selectedProduct!.price.toStringAsFixed(2)} ر.س'),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            SizedBox(
                              width: 80,
                              child: TextField(
                                controller: _qtyCtrl,
                                keyboardType: TextInputType.number,
                                decoration: const InputDecoration(
                                  labelText: 'الكمية',
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 12),
                            FilledButton(
                              onPressed: _tryAddToCart,
                              child: const Text('إضافة للسلة'),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ],
              if (_selectedProduct == null) ...[
                const SizedBox(height: 16),
                Row(
                  children: [
                    const Expanded(child: Divider()),
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Text('أو', style: Theme.of(context).textTheme.bodySmall),
                    ),
                    const Expanded(child: Divider()),
                  ],
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _manualBarcodeCtrl,
                        decoration: const InputDecoration(
                          labelText: 'الباركود يدوياً',
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton(
                      onPressed: _addByBarcode,
                      child: const Text('إضافة'),
                    ),
                  ],
                ),
              ],
          ],     // Column children
        ),      // Column
      ),       // SingleChildScrollView
      ),      // ConstrainedBox
    );       // Padding
  }
}