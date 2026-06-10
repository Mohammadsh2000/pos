import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/product.dart';
import '../providers/pos_provider.dart';
import '../services/feedback_service.dart';

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
  final _stockCtrl = TextEditingController(text: '1');
  String _cat = 'عام';
  String _saleType = 'unit';
  bool _saving = false;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _priceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _stockCtrl.dispose();
    super.dispose();
  }

  Future<void> _saveAndAdd() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) {
      return;
    }
    setState(() => _saving = true);

    final messenger = ScaffoldMessenger.of(context);
    final provider = context.read<POSProvider>();
    final feedback = FeedbackService.instance;
    final product = Product(
      name: _nameCtrl.text.trim(),
      barcode: widget.barcode,
      price: double.parse(_priceCtrl.text),
      purchasePrice: double.tryParse(_purchasePriceCtrl.text) ?? 0,
      stock: double.tryParse(_stockCtrl.text) ?? 0,
      category: _cat,
      saleType: _saleType,
    );
    final err = await provider.addProduct(product);
    if (!mounted) {
      return;
    }
    if (err != null) {
      setState(() => _saving = false);
      messenger.showSnackBar(SnackBar(content: Text(err)));
      return;
    }
    final addedToCart = provider.addToCartWithQuantity(product, 1);
    if (addedToCart) {
      feedback.play(ScanSound.success);
      messenger.showSnackBar(
        SnackBar(content: Text('تم حفظ ${product.name} وإضافته للفاتورة')),
      );
    } else {
      feedback.play(ScanSound.warning);
      messenger.showSnackBar(
        SnackBar(content: Text('تم حفظ ${product.name} لكن تعذّر إضافته للفاتورة')),
      );
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
              controller: _stockCtrl,
              decoration: const InputDecoration(labelText: 'الكمية في المخزون', border: OutlineInputBorder()),
              keyboardType: TextInputType.numberWithOptions(decimal: true),
            ),
            const SizedBox(height: 12),
            TextFormField(
              controller: _purchasePriceCtrl,
              decoration: const InputDecoration(labelText: 'سعر الشراء', border: OutlineInputBorder()),
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
              ],
              onChanged: (v) {
                _saleType = v!;
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
