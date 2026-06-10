import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants.dart';
import '../models/product.dart';
import '../providers/pos_provider.dart';

class _ProductScanOverlayPainter extends CustomPainter {
  final Rect scanRect;
  _ProductScanOverlayPainter({required this.scanRect});

  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..fillType = PathFillType.evenOdd
      ..addRect(Rect.fromLTWH(0, 0, size.width, size.height))
      ..addRRect(RRect.fromRectAndRadius(scanRect, const Radius.circular(8)));
    canvas.drawPath(path, Paint()..color = Colors.black45);

    final paint = Paint()
      ..color = Colors.greenAccent
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke;

    const bl = 20.0;
    canvas.drawLine(scanRect.topLeft, Offset(scanRect.left + bl, scanRect.top), paint);
    canvas.drawLine(scanRect.topLeft, Offset(scanRect.left, scanRect.top + bl), paint);
    canvas.drawLine(scanRect.topRight, Offset(scanRect.right - bl, scanRect.top), paint);
    canvas.drawLine(scanRect.topRight, Offset(scanRect.right, scanRect.top + bl), paint);
    canvas.drawLine(scanRect.bottomLeft, Offset(scanRect.left + bl, scanRect.bottom), paint);
    canvas.drawLine(scanRect.bottomLeft, Offset(scanRect.left, scanRect.bottom - bl), paint);
    canvas.drawLine(scanRect.bottomRight, Offset(scanRect.right - bl, scanRect.bottom), paint);
    canvas.drawLine(scanRect.bottomRight, Offset(scanRect.right, scanRect.bottom - bl), paint);
  }

  @override
  bool shouldRepaint(covariant _ProductScanOverlayPainter oldDelegate) => scanRect != oldDelegate.scanRect;
}

class ProductFormSheet extends StatefulWidget {
  final Product? product;

  const ProductFormSheet({super.key, this.product});

  @override
  State<ProductFormSheet> createState() => _ProductFormSheetState();
}

class _ProductFormSheetState extends State<ProductFormSheet> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameCtrl;
  late final TextEditingController _barcodeCtrl;
  late final TextEditingController _priceCtrl;
  late final TextEditingController _purchasePriceCtrl;
  late final TextEditingController _stockCtrl;
  late String _cat;
  late String _saleType;
  final MobileScannerController _barcodeScanCtrl = MobileScannerController(
    autoStart: false,
    torchEnabled: false,
  );
  bool _isScanningBarcode = false;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product?.name ?? '');
    _barcodeCtrl = TextEditingController(text: widget.product?.barcode ?? '');
    _priceCtrl = TextEditingController(text: widget.product?.price.toString() ?? '');
    _purchasePriceCtrl = TextEditingController(text: widget.product?.purchasePrice.toString() ?? '0');
    _stockCtrl = TextEditingController(text: (widget.product?.stock).toString());
    _cat = widget.product?.category ?? 'عام';
    _saleType = widget.product?.saleType ?? 'unit';
    _barcodeScanCtrl.startArguments.addListener(_onCameraStarted);
  }

  void _onCameraStarted() {
    if (_barcodeScanCtrl.startArguments.value != null) {
      _barcodeScanCtrl.hasTorchState.value = true;
      _barcodeScanCtrl.startArguments.removeListener(_onCameraStarted);
    }
  }

  @override
  void dispose() {
    _nameCtrl.dispose();
    _barcodeCtrl.dispose();
    _priceCtrl.dispose();
    _purchasePriceCtrl.dispose();
    _stockCtrl.dispose();
    _barcodeScanCtrl.startArguments.removeListener(_onCameraStarted);
    _barcodeScanCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    final availableHeight = MediaQuery.of(context).size.height - bottomInset;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 16, 16, bottomInset + 16),
      child: Form(
        key: _formKey,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: availableHeight),
          child: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
            Text(
              _editing ? 'تعديل المنتج' : 'إضافة منتج',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _nameCtrl,
              decoration: const InputDecoration(labelText: 'اسم المنتج', border: OutlineInputBorder()),
              validator: (v) {
                if (v == null || v.trim().isEmpty) {
                  return 'الاسم مطلوب';
                }
                return null;
              },
            ),
            const SizedBox(height: 12),
            if (_isScanningBarcode)
              SizedBox(
                height: 150,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final scanWidth = constraints.maxWidth * 0.7;
                      final scanHeight = constraints.maxHeight * 0.4;
                      final scanLeft = (constraints.maxWidth - scanWidth) / 2;
                      final scanTop = (constraints.maxHeight - scanHeight) / 2;
                      final scanRect = Rect.fromLTWH(scanLeft, scanTop, scanWidth, scanHeight);

                          return Stack(
                            children: [
                              MobileScanner(
                                controller: _barcodeScanCtrl,
                                scanWindow: scanRect,
                                onDetect: (c) {
                                  final b = c.barcodes.firstOrNull;
                                  if (b?.rawValue != null) {
                                    _barcodeCtrl.text = b!.rawValue!;
                                    setState(() {
                                      _isScanningBarcode = false;
                                    });
                                    _barcodeScanCtrl.stop();
                                  }
                                },
                              ),
                              Positioned.fill(
                                child: CustomPaint(
                                  painter: _ProductScanOverlayPainter(scanRect: scanRect),
                                ),
                              ),
                              Positioned(
                                top: 4,
                                left: 4,
                                child: ValueListenableBuilder<TorchState>(
                                  valueListenable: _barcodeScanCtrl.torchState,
                                  builder: (context, state, _) {
                                    final isOn = state == TorchState.on;
                                    return IconButton(
                                      icon: Icon(
                                        isOn ? Icons.flash_on : Icons.flash_off,
                                        color: Colors.white,
                                        size: 20,
                                      ),
                                      onPressed: () => _barcodeScanCtrl.toggleTorch(),
                                      style: IconButton.styleFrom(
                                        backgroundColor: Colors.black38,
                                        padding: const EdgeInsets.all(6),
                                        minimumSize: const Size(32, 32),
                                      ),
                                    );
                                  },
                                ),
                              ),
                              Positioned(
                                top: 4,
                                right: 4,
                                child: IconButton(
                                  icon: const Icon(Icons.close, color: Colors.white),
                                  onPressed: () {
                                    setState(() {
                                      _isScanningBarcode = false;
                                    });
                                    _barcodeScanCtrl.stop();
                                  },
                                ),
                              ),
                            ],
                          );
                    },
                  ),
                ),
              )
            else
              TextFormField(
                controller: _barcodeCtrl,
                decoration: const InputDecoration(
                  labelText: 'الباركود',
                  border: OutlineInputBorder(),
                  suffixIcon: Icon(Icons.qr_code_scanner),
                ),
                validator: (v) {
                  if (v == null || v.trim().isEmpty) {
                    return 'الباركود مطلوب';
                  }
                  return null;
                },
              ),
            const SizedBox(height: 4),
            if (_isScanningBarcode)
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isScanningBarcode = false;
                  });
                  _barcodeScanCtrl.stop();
                },
                icon: const Icon(Icons.edit, size: 18),
                label: const Text('إدخال يدوي'),
              )
            else
              TextButton.icon(
                onPressed: () {
                  setState(() {
                    _isScanningBarcode = true;
                  });
                  _barcodeScanCtrl.start();
                },
                icon: const Icon(Icons.qr_code_scanner, size: 18),
                label: Text(_editing ? 'تغيير الباركود بالمسح' : 'مسح الباركود'),
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
            const SizedBox(height: 16),
            FilledButton(
              onPressed: () async {
                if (!_formKey.currentState!.validate()) {
                  return;
                }
                final provider = context.read<POSProvider>();
                final product = Product(
                  id: widget.product?.id,
                  name: _nameCtrl.text.trim(),
                  barcode: _barcodeCtrl.text.trim(),
                  price: double.parse(_priceCtrl.text),
                  purchasePrice: double.tryParse(_purchasePriceCtrl.text) ?? 0,
                  stock: double.tryParse(_stockCtrl.text) ?? 0,
                  category: _cat,
                  saleType: _saleType,
                );
                final err = _editing
                    ? await provider.updateProduct(product)
                    : await provider.addProduct(product);
                if (!context.mounted) {
                  return;
                }
                if (err != null) {
                  if (!context.mounted) return;
                  await showDialog(
                    context: context,
                    builder: (ctx) => AlertDialog(
                      title: const Text('خطأ'),
                      content: Text(err),
                      actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('حسناً'))],
                    ),
                  );
                  return;
                }
                if (!context.mounted) {
                  return;
                }
                Navigator.pop(context);
              },
              child: Text(_editing ? 'حفظ التعديلات' : 'إضافة المنتج'),
            ),
            ],  // Column children
          ),    // Column
        ),     // SingleChildScrollView
        ),    // ConstrainedBox
      ),     // Form
    );      // Padding
  }
}
