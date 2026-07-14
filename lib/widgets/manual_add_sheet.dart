import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../services/database_helper.dart';
import '../services/feedback_service.dart';
import '../utils/notifications.dart';

class ManualAddSheet extends StatefulWidget {
  const ManualAddSheet({super.key});

  @override
  State<ManualAddSheet> createState() => _ManualAddSheetState();
}

class _ManualAddSheetState extends State<ManualAddSheet> {
  final _searchCtrl = TextEditingController();
  final _qtyCtrl = TextEditingController(text: '1');
  final _priceCtrl = TextEditingController();
  final _manualBarcodeCtrl = TextEditingController();
  Product? _selectedProduct;
  List<Product> _suggestions = [];
  Timer? _debounce;
  bool _isUpdating = false;
  bool _sellAsCarton = false;
  double _desiredQty = 1.0;

  @override
  void initState() {
    super.initState();
    _qtyCtrl.addListener(_onQtyChanged);
    _priceCtrl.addListener(_onPriceChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    _qtyCtrl.dispose();
    _priceCtrl.dispose();
    _manualBarcodeCtrl.dispose();
    super.dispose();
  }

  double get _unitPrice {
    if (_selectedProduct == null) return 0;
    return _sellAsCarton
        ? _selectedProduct!.cartonDiscountedPrice
        : _selectedProduct!.discountedPrice;
  }

  void _onQtyChanged() {
    if (_isUpdating || _selectedProduct == null) return;
    _isUpdating = true;
    final qty = double.tryParse(_qtyCtrl.text);
    if (qty != null && qty > 0) {
      _desiredQty = qty;
      _priceCtrl.text = (qty * _unitPrice).toStringAsFixed(2);
    }
    _isUpdating = false;
  }

  void _onPriceChanged() {
    if (_isUpdating || _selectedProduct == null) return;
    _isUpdating = true;
    final price = double.tryParse(_priceCtrl.text);
    if (price != null && price > 0) {
      final unitPrice = _unitPrice;
      if (unitPrice > 0) {
        double qty = price / unitPrice;
        if (!_selectedProduct!.isKg && !_sellAsCarton && !_selectedProduct!.isCarton) {
          qty = qty.roundToDouble();
          if (qty < 1) qty = 1;
        }
        _desiredQty = qty;
        _qtyCtrl.text = (_selectedProduct!.isKg || _sellAsCarton)
            ? qty.toStringAsFixed(3)
            : qty.toInt().toString();
      }
    }
    _isUpdating = false;
  }

  void _resetToProduct(Product prod, {bool defaultCarton = false}) {
    _isUpdating = true;
    setState(() {
      _selectedProduct = prod;
      _sellAsCarton = defaultCarton || prod.isCarton;
      _searchCtrl.text = prod.name;
      _suggestions = [];
      _desiredQty = 1.0;
    });
    _qtyCtrl.text = '1';
    _priceCtrl.text = _unitPrice.toStringAsFixed(2);
    _isUpdating = false;
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
                p.barcode.contains(q) ||
                p.secondaryBarcode.contains(q))
            .take(10)
            .toList();
      });
    });
  }

  void _tryAddToCart() {
    final p = context.read<POSProvider>();
    if (_selectedProduct == null) return;
    final qty = _desiredQty;
    final feedback = FeedbackService.instance;
    final added = p.addToCartWithQuantity(_selectedProduct!, qty, asCarton: _sellAsCarton);
    if (added) {
      feedback.play(ScanSound.success);
      Navigator.pop(context);
    } else {
      feedback.play(ScanSound.warning);
      showTopNotification(
        context,
        p.cart.isNotEmpty
            ? 'الكمية المطلوبة أكبر من المخزون المتاح (${_selectedProduct!.stock.toStringAsFixed(2)})'
            : 'تعذّر إضافة ${_selectedProduct!.name} للسلة',
      );
    }
  }

  Future<void> _addByBarcode() async {
    final code = _manualBarcodeCtrl.text.trim();
    if (code.isEmpty) {
      return;
    }
    final provider = context.read<POSProvider>();
    final feedback = FeedbackService.instance;
    var product = provider.findProductByBarcode(code) ??
        await DatabaseHelper().getProductByBarcode(code);
    if (!mounted) {
      return;
    }
    if (product == null) {
      feedback.play(ScanSound.unknown);
      showTopNotification(context, 'المنتج غير موجود');
      return;
    }
    final qty = _desiredQty;
    final isCartonBarcode = code == product.barcode;
    final asCarton = isCartonBarcode || (product.isCarton && code != product.secondaryBarcode);
    final added = provider.addToCartWithQuantity(product, qty, asCarton: asCarton);
    if (added) {
      feedback.play(ScanSound.success);
      Navigator.pop(context);
    } else {
      feedback.play(ScanSound.warning);
      showTopNotification(
        context,
        'المخزون غير كافٍ لـ ${product.name} (${product.stock.toStringAsFixed(2)} متاح)',
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
                        subtitle: Text(
                          prod.discountPercent > 0
                              ? '${prod.discountedPrice.toStringAsFixed(2)} $kCurrencySymbol (-${prod.discountPercent.toInt()}%) | المخزون: ${prod.stock.toStringAsFixed(2)} | ${prod.isCarton ? 'كرتونة' : (prod.isKg ? 'كجم' : 'عدد')}'
                              : '${prod.price.toStringAsFixed(2)} $kCurrencySymbol | المخزون: ${prod.stock.toStringAsFixed(2)} | ${prod.isCarton ? 'كرتونة' : (prod.isKg ? 'كجم' : 'عدد')}',
                        ),
                        onTap: () => _resetToProduct(prod),
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
                            if (_selectedProduct!.discountPercent > 0)
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                decoration: BoxDecoration(
                                  color: Colors.red.shade50,
                                  borderRadius: BorderRadius.circular(4),
                                  border: Border.all(color: Colors.red.shade200),
                                ),
                                child: Text(
                                  '-${_selectedProduct!.discountPercent.toInt()}%',
                                  style: TextStyle(fontSize: 10, color: Colors.red[700], fontWeight: FontWeight.bold),
                                ),
                              ),
                          ],
                        ),
                        if (_selectedProduct!.hasCartonSale) ...[
                          const SizedBox(height: 8),
                          SegmentedButton<bool>(
                            segments: const [
                              ButtonSegment(value: false, label: Text('قطعة')),
                              ButtonSegment(value: true, label: Text('كرتونة')),
                            ],
                            selected: {_sellAsCarton},
                            onSelectionChanged: (v) {
                              setState(() => _sellAsCarton = v.first);
                              _isUpdating = true;
                              _priceCtrl.text = (_desiredQty * _unitPrice).toStringAsFixed(2);
                              _isUpdating = false;
                            },
                            style: ButtonStyle(
                              visualDensity: VisualDensity.compact,
                              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            ),
                          ),
                        ],
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Text(
                              _sellAsCarton
                                  ? '${_selectedProduct!.cartonDiscountedPrice.toStringAsFixed(2)} $kCurrencySymbol/كرتونة'
                                  : '${_selectedProduct!.discountedPrice.toStringAsFixed(2)} $kCurrencySymbol/${_selectedProduct!.isKg ? 'كجم' : 'حبة'}',
                              style: TextStyle(
                                color: Colors.orange[700],
                                fontWeight: FontWeight.bold,
                                fontSize: 16,
                              ),
                            ),
                            if (_sellAsCarton && _selectedProduct!.piecesPerCarton > 0)
                              Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: Text(
                                  '(${_selectedProduct!.piecesPerCarton} قطع/كرتونة)',
                                  style: TextStyle(color: Colors.grey[600], fontSize: 12),
                                ),
                              ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                controller: _qtyCtrl,
                                keyboardType: (_selectedProduct!.isKg || _sellAsCarton)
                                    ? const TextInputType.numberWithOptions(decimal: true)
                                    : TextInputType.number,
                                decoration: InputDecoration(
                                  labelText: _sellAsCarton ? 'عدد الكراتين' : (_selectedProduct!.isKg ? 'الوزن (كجم)' : 'الكمية'),
                                  border: OutlineInputBorder(),
                                  isDense: true,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: TextField(
                                controller: _priceCtrl,
                                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                                decoration: const InputDecoration(
                                  labelText: 'السعر الإجمالي',
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
