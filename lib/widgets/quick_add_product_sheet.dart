import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/product.dart';
import '../providers/pos_provider.dart';
import '../services/feedback_service.dart';
import '../utils/notifications.dart';

class QuickAddProductSheet extends StatefulWidget {
  final String barcode;

  const QuickAddProductSheet({super.key, required this.barcode});

  @override
  State<QuickAddProductSheet> createState() => _QuickAddProductSheetState();
}

class _QuickAddProductSheetState extends State<QuickAddProductSheet> {
  final _formKey = GlobalKey<FormState>();
  final _nameCtrl = TextEditingController();
  final _priceCtrl = TextEditingController();
  final _purchasePriceCtrl = TextEditingController();
  final _discountPercentCtrl = TextEditingController();
  final _stockCtrl = TextEditingController(text: '1');
  final _piecesPerCartonCtrl = TextEditingController(text: '1');
  final _cartonPriceCtrl = TextEditingController();
  final _secondaryBarcodeCtrl = TextEditingController();
  String _cat = 'عام';
  String _saleType = 'unit';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _discountPercentCtrl.dispose();
    _stockCtrl.dispose();
    _piecesPerCartonCtrl.dispose();
    _cartonPriceCtrl.dispose();
    _secondaryBarcodeCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndAdd() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);

    final provider = context.read<POSProvider>();
    final feedback = FeedbackService.instance;
    final discountPercent = (double.tryParse(_discountPercentCtrl.text) ?? 0.0).clamp(0.0, 100.0);
    final cartonPrice = double.tryParse(_cartonPriceCtrl.text) ?? 0;
    final piecesPerCarton = int.tryParse(_piecesPerCartonCtrl.text) ?? 1;
    final isCartonType = _saleType == 'carton';
    double stock = double.tryParse(_stockCtrl.text) ?? 0;
    if (isCartonType) {
      if (stock < 1) stock = 1;
      stock = stock * piecesPerCarton;
    }
    final product = Product(
      name: _nameCtrl.text.trim(),
      barcode: widget.barcode,
      price: double.parse(_priceCtrl.text),
      purchasePrice: double.tryParse(_purchasePriceCtrl.text) ?? 0,
      stock: stock,
      category: _cat,
      saleType: _saleType,
      discountPercent: discountPercent,
      piecesPerCarton: piecesPerCarton,
      cartonPrice: cartonPrice,
      secondaryBarcode: _secondaryBarcodeCtrl.text.trim(),
    );
    final err = await provider.addProduct(product);
    if (!mounted) {
      return;
    }
    if (err != null) {
      setState(() => _saving = false);
      showTopNotification(context, err);
      return;
    }
    final addedToCart = provider.addToCartWithQuantity(product, 1, asCarton: isCartonType);
    if (addedToCart) {
      feedback.play(ScanSound.success);
      showSuccessNotification(context, 'تم حفظ ${product.name} وإضافته للفاتورة');
    } else {
      feedback.play(ScanSound.warning);
      showTopNotification(context, 'تم حفظ ${product.name} لكن تعذّر إضافته للفاتورة، تأكد من المخزون');
    }
    if (mounted) {
      Navigator.pop(context, product);
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
        child: Form(
          key: _formKey,
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Text('منتج جديد', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('الباركود: ${widget.barcode}', style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 12),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم المنتج', border: OutlineInputBorder()),
              autofocus: true,
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'الاسم مطلوب';
                }
                return null;
              },
            ),
            if (_saleType == 'carton') ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _cartonPriceCtrl,
                decoration: const InputDecoration(labelText: 'سعر بيع الكرتونة', border: OutlineInputBorder()),
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'سعر الكرتونة مطلوب';
                  }
                  if (double.tryParse(v) == null || double.parse(v) <= 0) {
                    return 'سعر غير صالح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _purchasePriceCtrl,
                decoration: const InputDecoration(labelText: 'سعر شراء الكرتونة', border: OutlineInputBorder()),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceCtrl,
                decoration: const InputDecoration(labelText: 'سعر الحبة (قطعة)', border: OutlineInputBorder()),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _piecesPerCartonCtrl,
                decoration: const InputDecoration(labelText: 'عدد القطع في الكرتونة', border: OutlineInputBorder()),
                keyboardType: TextInputType.number,
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _secondaryBarcodeCtrl,
                decoration: const InputDecoration(labelText: 'باركود الحبة', border: OutlineInputBorder()),
              ),
            ] else ...[
              const SizedBox(height: 12),
              TextFormField(
                controller: _priceCtrl,
                decoration: const InputDecoration(labelText: 'السعر', border: OutlineInputBorder()),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
                validator: (v) {
                  if (v == null || v.isEmpty) {
                    return 'السعر مطلوب';
                  }
                  if (double.tryParse(v) == null || double.parse(v) <= 0) {
                    return 'سعر غير صالح';
                  }
                  return null;
                },
              ),
              const SizedBox(height: 12),
              TextFormField(
                controller: _purchasePriceCtrl,
                decoration: const InputDecoration(labelText: 'سعر الشراء', border: OutlineInputBorder()),
                keyboardType: TextInputType.numberWithOptions(decimal: true),
              ),
            ],
            const SizedBox(height: 12),
            TextFormField(
              controller: _stockCtrl,
              decoration: InputDecoration(labelText: _saleType == 'carton' ? 'الكمية في المخزون (كرتونة)' : 'الكمية في المخزون', border: const OutlineInputBorder()),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _discountPercentCtrl,
              decoration: const InputDecoration(labelText: 'خصم %', border: OutlineInputBorder()),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _cat,
              decoration: const InputDecoration(labelText: 'التصنيف', border: OutlineInputBorder()),
              items: kCategories
                  .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                  .toList(),
              onChanged: (v) {
                setState(() {
                  _cat = v!;
                });
              },
            ),
            const SizedBox(height: 12),
            DropdownButtonFormField<String>(
              initialValue: _saleType,
              decoration: const InputDecoration(labelText: 'طريقة البيع', border: OutlineInputBorder()),
              items: const [
                DropdownMenuItem(value: 'unit', child: Text('بالعدد')),
                DropdownMenuItem(value: 'kg', child: Text('بالكيلو')),
                DropdownMenuItem(value: 'carton', child: Text('بالكرتونة')),
              ],
              onChanged: (v) {
                setState(() => _saleType = v!);
              },
            ),
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _saveAndAdd,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                    )
                  : const Text('حفظ وإضافة للفاتورة'),
            ),
          ],
        ),     // Column
      ),      // SingleChildScrollView
      ),     // ConstrainedBox
      ),    // Form
    );     // Padding
  }
}
