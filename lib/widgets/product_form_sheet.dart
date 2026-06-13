import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../constants.dart';
import '../models/product.dart';
import '../providers/pos_provider.dart';
import '../utils/notifications.dart';

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
  bool _saving = false;

  bool get _editing => widget.product != null;

  @override
  void initState() {
    super.initState();
    _nameCtrl = TextEditingController(text: widget.product?.name ?? '');
    _barcodeCtrl = TextEditingController(text: widget.product?.barcode ?? '');
    _priceCtrl = TextEditingController(text: widget.product != null ? widget.product!.price.toString() : '');
    _purchasePriceCtrl = TextEditingController(text: widget.product != null ? widget.product!.purchasePrice.toString() : '');
    _stockCtrl = TextEditingController(text: widget.product != null ? widget.product!.stock.toString() : '');
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
    _barcodeScanCtrl.stop();
    _barcodeScanCtrl.dispose();
    super.dispose();
  }

  Widget _buildSectionCard({
    required String title,
    required IconData icon,
    required List<Widget> children,
    Color? iconColor,
  }) {
    final theme = Theme.of(context);
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 0),
            child: Row(
              children: [
                Icon(icon, size: 18, color: iconColor ?? theme.colorScheme.primary),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: theme.textTheme.labelLarge?.copyWith(
                    fontWeight: FontWeight.w700,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 20),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 0, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: children,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType? keyboardType,
    String? Function(String?)? validator,
    Widget? suffix,
    bool enabled = true,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        enabled: enabled,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          suffixIcon: suffix,
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        ),
        keyboardType: keyboardType,
        validator: validator,
      ),
    );
  }

  Widget _buildPriceField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    String? Function(String?)? validator,
  }) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TextFormField(
        controller: controller,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: Icon(icon, size: 20),
          suffixText: kCurrencySymbol,
          suffixStyle: TextStyle(
            fontWeight: FontWeight.w700,
            color: theme.colorScheme.onSurfaceVariant,
          ),
          filled: true,
          fillColor: theme.colorScheme.surfaceContainerLowest,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(12),
            borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
          ),
          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
        ),
        keyboardType: TextInputType.numberWithOptions(decimal: true),
        validator: validator,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return _KeyboardPadding(
      child: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    margin: const EdgeInsets.only(bottom: 12),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                Row(
                  children: [
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _editing ? Icons.edit : Icons.add,
                        color: theme.colorScheme.onPrimaryContainer,
                        size: 22,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _editing ? 'تعديل المنتج' : 'إضافة منتج',
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w800,
                            ),
                          ),
                          if (_editing && widget.product!.name.isNotEmpty)
                            Text(
                              widget.product!.name,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(Icons.close, size: 22, color: theme.colorScheme.onSurfaceVariant),
                      onPressed: () {
                        _barcodeScanCtrl.stop();
                        Navigator.pop(context);
                      },
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                        padding: const EdgeInsets.all(8),
                        minimumSize: const Size(36, 36),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                _buildSectionCard(
                  title: 'معلومات أساسية',
                  icon: Icons.info_outline,
                  children: [
                    _buildField(
                      controller: _nameCtrl,
                      label: 'اسم المنتج',
                      icon: Icons.shopping_bag_outlined,
                      validator: (v) {
                        if (v == null || v.trim().isEmpty) return 'الاسم مطلوب';
                        return null;
                      },
                    ),
                    if (_isScanningBarcode)
                      SizedBox(
                        height: 150,
                        child: ClipRRect(
                          borderRadius: BorderRadius.circular(12),
                          child: LayoutBuilder(
                            builder: (context, constraints) {
                              final scanWidth = constraints.maxWidth * 0.7;
                              final scanHeight = constraints.maxHeight * 0.7;
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
                                        setState(() => _isScanningBarcode = false);
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
                                    top: 4, left: 4,
                                    child: ValueListenableBuilder<TorchState>(
                                      valueListenable: _barcodeScanCtrl.torchState,
                                      builder: (context, state, _) {
                                        final isOn = state == TorchState.on;
                                        return IconButton(
                                          icon: Icon(isOn ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 20),
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
                                    top: 4, right: 4,
                                    child: IconButton(
                                      icon: const Icon(Icons.close, color: Colors.white),
                                      onPressed: () {
                                        setState(() => _isScanningBarcode = false);
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
                      _buildField(
                        controller: _barcodeCtrl,
                        label: 'الباركود',
                        icon: Icons.qr_code,
                        validator: (v) {
                          if (v == null || v.trim().isEmpty) return 'الباركود مطلوب';
                          return null;
                        },
                        suffix: IconButton(
                          icon: Icon(Icons.qr_code_scanner, size: 20, color: theme.colorScheme.primary),
                          onPressed: () {
                            setState(() => _isScanningBarcode = true);
                            _barcodeScanCtrl.start();
                          },
                        ),
                      ),
                    if (_isScanningBarcode)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton.icon(
                          onPressed: () {
                            setState(() => _isScanningBarcode = false);
                            _barcodeScanCtrl.stop();
                          },
                          icon: const Icon(Icons.edit, size: 16),
                          label: const Text('إدخال يدوي'),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                      ),
                  ],
                ),

                _buildSectionCard(
                  title: 'التسعير',
                  icon: Icons.attach_money,
                  iconColor: Colors.green.shade600,
                  children: [
                    _buildPriceField(
                      controller: _priceCtrl,
                      label: 'سعر البيع',
                      icon: Icons.attach_money,
                      validator: (v) {
                        if (v == null || v.isEmpty) return 'السعر مطلوب';
                        if (double.tryParse(v) == null || double.parse(v) <= 0) return 'سعر غير صالح';
                        return null;
                      },
                    ),
                    _buildPriceField(
                      controller: _purchasePriceCtrl,
                      label: 'سعر الشراء',
                      icon: Icons.shopping_cart_outlined,
                    ),
                    _ProfitMarginIndicator(
                      priceCtrl: _priceCtrl,
                      purchaseCtrl: _purchasePriceCtrl,
                    ),
                  ],
                ),

                _buildSectionCard(
                  title: 'المخزون',
                  icon: Icons.inventory_2_outlined,
                  children: [
                    _buildField(
                      controller: _stockCtrl,
                      label: 'الكمية في المخزون',
                      icon: Icons.inventory_2_outlined,
                      keyboardType: TextInputType.numberWithOptions(decimal: true),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(bottom: 10),
                      child: DropdownButtonFormField<String>(
                        initialValue: _saleType,
                        decoration: InputDecoration(
                          labelText: 'طريقة البيع',
                          prefixIcon: Icon(Icons.scale, size: 20),
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerLowest,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                        ),
                        items: const [
                          DropdownMenuItem(value: 'unit', child: Text('بالعدد')),
                          DropdownMenuItem(value: 'kg', child: Text('بالكيلو')),
                        ],
                        onChanged: (v) => _saleType = v!,
                      ),
                    ),
                    DropdownButtonFormField<String>(
                      initialValue: _cat,
                      decoration: InputDecoration(
                        labelText: 'التصنيف',
                        prefixIcon: Icon(Icons.category, size: 20),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerLowest,
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(12),
                          borderSide: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                        ),
                        contentPadding: const EdgeInsets.symmetric(vertical: 14, horizontal: 12),
                      ),
                      items: kCategories
                          .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                          .toList(),
                      onChanged: (v) => setState(() => _cat = v!),
                    ),
                  ],
                ),

                FilledButton(
                  onPressed: _saving ? null : _onSubmit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size(double.infinity, 50),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    backgroundColor: _editing ? theme.colorScheme.primary : null,
                  ),
                  child: _saving
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white),
                        )
                      : Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(_editing ? Icons.save : Icons.add_circle_outline, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              _editing ? 'حفظ التعديلات' : 'إضافة المنتج',
                              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                            ),
                          ],
                        ),
                ),
              ],
          ),
        ),
      ),
    );
  }

  Future<void> _onSubmit() async {
    if (_saving) return;
    if (!_formKey.currentState!.validate()) return;

    setState(() => _saving = true);

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

    if (!mounted) return;

    setState(() => _saving = false);

    if (err != null) {
      if (!mounted) return;
      showTopNotification(context, err);
      return;
    }

    if (!mounted) return;
    _barcodeScanCtrl.stop();
    Navigator.pop(context);
  }
}

class _KeyboardPadding extends StatelessWidget {
  final Widget child;
  const _KeyboardPadding({required this.child});

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.of(context).viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(16, 14, 16, bottom + 16),
      child: child,
    );
  }
}

class _ProfitMarginIndicator extends StatefulWidget {
  final TextEditingController priceCtrl;
  final TextEditingController purchaseCtrl;

  const _ProfitMarginIndicator({
    required this.priceCtrl,
    required this.purchaseCtrl,
  });

  @override
  State<_ProfitMarginIndicator> createState() => _ProfitMarginIndicatorState();
}

class _ProfitMarginIndicatorState extends State<_ProfitMarginIndicator> {
  double? _profit;
  double? _margin;

  @override
  void initState() {
    super.initState();
    widget.priceCtrl.addListener(_onChanged);
    widget.purchaseCtrl.addListener(_onChanged);
    _onChanged();
  }

  @override
  void didUpdateWidget(_ProfitMarginIndicator old) {
    super.didUpdateWidget(old);
    if (old.priceCtrl != widget.priceCtrl) {
      old.priceCtrl.removeListener(_onChanged);
      widget.priceCtrl.addListener(_onChanged);
    }
    if (old.purchaseCtrl != widget.purchaseCtrl) {
      old.purchaseCtrl.removeListener(_onChanged);
      widget.purchaseCtrl.addListener(_onChanged);
    }
    _onChanged();
  }

  @override
  void dispose() {
    widget.priceCtrl.removeListener(_onChanged);
    widget.purchaseCtrl.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final price = double.tryParse(widget.priceCtrl.text);
    final purchase = double.tryParse(widget.purchaseCtrl.text);
    if (price != null && purchase != null && price > 0 && purchase > 0) {
      final profit = price - purchase;
      final margin = (profit / price) * 100;
      if (_profit != profit || _margin != margin) {
        setState(() {
          _profit = profit;
          _margin = margin;
        });
      }
    } else {
      if (_profit != null || _margin != null) {
        setState(() {
          _profit = null;
          _margin = null;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_profit == null || _margin == null) {
      return const SizedBox.shrink();
    }
    final profit = _profit!;
    final margin = _margin!;
    final isProfit = profit > 0;
    return Container(
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: isProfit ? Colors.green.shade50 : Colors.red.shade50,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        children: [
          Icon(
            isProfit ? Icons.trending_up : Icons.trending_down,
            size: 18,
            color: isProfit ? Colors.green.shade600 : Colors.red.shade600,
          ),
          const SizedBox(width: 8),
          Text(
            isProfit
                ? 'ربح: ${profit.toStringAsFixed(5)} $kCurrencySymbol (${margin.toStringAsFixed(1)}%)'
                : 'خسارة: ${profit.abs().toStringAsFixed(5)} $kCurrencySymbol',
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w600,
              color: isProfit ? Colors.green.shade700 : Colors.red.shade700,
            ),
          ),
        ],
      ),
    );
  }
}
