import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/stock_in_entry.dart';
import '../providers/pos_provider.dart';
import '../services/database_helper.dart';
import '../utils/notifications.dart';

class _CartItem {
  final int productId;
  final String productName;
  final double currentStock;
  final double currentCost;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;

  _CartItem({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.currentCost,
    required double quantity,
    required double batchCost,
  })  : qtyCtrl = TextEditingController(text: quantity.toStringAsFixed(quantity == quantity.roundToDouble() ? 0 : 2)),
        costCtrl = TextEditingController(text: batchCost.toStringAsFixed(3));

  double get quantity => double.tryParse(qtyCtrl.text) ?? 0;
  double get batchCost => double.tryParse(costCtrl.text) ?? 0;
  double get subtotal => quantity * batchCost;
  double get newStock => currentStock + quantity;
  double get newCost {
    final totalValue = currentStock * currentCost + quantity * batchCost;
    final raw = newStock > 0 ? totalValue / newStock : batchCost;
    return double.parse(raw.toStringAsFixed(5));
  }

  void dispose() {
    qtyCtrl.dispose();
    costCtrl.dispose();
  }
}

class StockInSheet extends StatefulWidget {
  const StockInSheet({super.key});

  @override
  State<StockInSheet> createState() => _StockInSheetState();
}

class _StockInSheetState extends State<StockInSheet> {
  final _barcodeCtrl = TextEditingController();
  final _scannerCtrl = MobileScannerController(autoStart: false, torchEnabled: false);
  final List<_CartItem> _items = [];
  bool _saving = false;
  bool _scannerOn = false;

  @override
  void dispose() {
    _barcodeCtrl.dispose();
    _scannerCtrl.dispose();
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _onBarcode(String code) async {
    if (code.trim().isEmpty) return;
    final product = await DatabaseHelper().getProductByBarcode(code.trim());
    if (product == null || product.id == null) {
      if (mounted) {
        showTopNotification(context, 'المنتج غير معروف');
      }
      return;
    }
    setState(() {
      final existing = _items.where((i) => i.productId == product.id).firstOrNull;
      if (existing != null) {
        final newQty = existing.quantity + 1;
        existing.qtyCtrl.text = newQty.toStringAsFixed(newQty == newQty.roundToDouble() ? 0 : 2);
      } else {
        _items.add(_CartItem(
          productId: product.id!,
          productName: product.name,
          currentStock: product.stock,
          currentCost: product.purchasePrice,
          quantity: 1,
          batchCost: product.purchasePrice,
        ));
      }
      _barcodeCtrl.clear();
      if (_scannerOn) _toggleScanner();
    });
  }

  void _toggleScanner() {
    setState(() {
      _scannerOn = !_scannerOn;
      if (_scannerOn) {
        _scannerCtrl.start();
      } else {
        _scannerCtrl.stop();
      }
    });
  }

  Future<void> _save() async {
    if (_items.isEmpty) return;
    setState(() => _saving = true);
    final entries = <StockInEntry>[];
    for (final item in _items) {
      if (item.quantity <= 0 || item.batchCost <= 0) continue;
      entries.add(StockInEntry(
        productId: item.productId,
        productName: item.productName,
        quantity: item.quantity,
        cost: item.batchCost,
      ));
    }
    if (entries.isEmpty) {
      setState(() => _saving = false);
      return;
    }
    final err = await context.read<POSProvider>().createPurchase(entries);
    if (mounted) {
      setState(() => _saving = false);
      if (err != null) {
        showTopNotification(context, err);
      } else {
        if (_scannerOn) _scannerCtrl.stop();
        Navigator.pop(context, true);
      }
    }
  }

  double get _total => _items.fold(0.0, (s, i) => s + i.subtotal);
  bool get _hasInvalid => _items.any((i) => i.quantity <= 0 || i.batchCost <= 0);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return Container(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
      ),
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const SizedBox(height: 8),
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
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Icon(Icons.receipt_long, color: theme.colorScheme.primary),
                  const SizedBox(width: 8),
                  Text('فاتورة تزويد مخزون', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                  const Spacer(),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () {
                      if (_scannerOn) _scannerCtrl.stop();
                      Navigator.pop(context);
                    },
                  ),
                ],
            ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _barcodeCtrl,
                      decoration: InputDecoration(
                        hintText: 'امسح الباركود أو اكتبه',
                        prefixIcon: InkWell(
                          onTap: _toggleScanner,
                          borderRadius: BorderRadius.circular(12),
                          child: Padding(
                            padding: const EdgeInsets.all(12),
                            child: Icon(
                              Icons.qr_code_scanner,
                              size: 20,
                              color: _scannerOn ? theme.colorScheme.primary : null,
                            ),
                          ),
                        ),
                        suffixIcon: _barcodeCtrl.text.isNotEmpty
                            ? IconButton(
                                icon: const Icon(Icons.add_circle_outline, size: 20),
                                onPressed: () => _onBarcode(_barcodeCtrl.text),
                              )
                            : null,
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        contentPadding: const EdgeInsets.symmetric(vertical: 10),
                        filled: true,
                        fillColor: theme.colorScheme.surfaceContainerLowest,
                      ),
                      onSubmitted: _onBarcode,
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    height: 44, width: 44,
                    decoration: BoxDecoration(
                      color: _scannerOn ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerLowest,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: IconButton(
                      icon: Icon(
                        _scannerOn ? Icons.camera_alt : Icons.camera_alt_outlined,
                        color: _scannerOn ? Colors.white : theme.colorScheme.onSurfaceVariant,
                        size: 20,
                      ),
                      onPressed: _toggleScanner,
                    ),
                  ),
                ],
              ),
            ),
            if (_scannerOn) ...[
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: SizedBox(
                    height: 200,
                    child: LayoutBuilder(
                      builder: (context, constraints) {
                        final scanWidth = constraints.maxWidth * 0.7;
                        final scanHeight = constraints.maxHeight * 0.7;
                        final scanLeft = (constraints.maxWidth - scanWidth) / 2;
                        final scanTop = (constraints.maxHeight - scanHeight) / 2;
                        final scanRect = Rect.fromLTWH(scanLeft, scanTop, scanWidth, scanHeight);
                        return Stack(
                          children: [
                            Container(color: Colors.black87),
                            MobileScanner(
                              controller: _scannerCtrl,
                              scanWindow: scanRect,
                              onDetect: (c) {
                                final b = c.barcodes.firstOrNull;
                                if (b?.rawValue != null) {
                                  _onBarcode(b!.rawValue!);
                                }
                              },
                            ),
                            Positioned.fill(
                              child: CustomPaint(
                                painter: _ScanOverlayPainter(scanRect: scanRect),
                              ),
                            ),
                            Positioned(
                              top: 8, left: 8,
                              child: ValueListenableBuilder<TorchState>(
                                valueListenable: _scannerCtrl.torchState,
                                builder: (context, state, _) {
                                  final isOn = state == TorchState.on;
                                  return IconButton(
                                    icon: Icon(isOn ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 20),
                                    onPressed: () => _scannerCtrl.toggleTorch(),
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
                              top: 8, right: 8,
                              child: IconButton(
                                icon: const Icon(Icons.close, color: Colors.white, size: 20),
                                onPressed: () {
                                  _scannerCtrl.stop();
                                  setState(() => _scannerOn = false);
                                },
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black38,
                                  padding: const EdgeInsets.all(6),
                                  minimumSize: const Size(32, 32),
                                ),
                              ),
                            ),
                          ],
                        );
                      },
                    ),
              ),
            ),
            ),
            ],
            const SizedBox(height: 12),
            if (_items.isEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(
                  child: Column(
                    children: [
                      Icon(Icons.shopping_cart_outlined, size: 48, color: theme.colorScheme.outlineVariant),
                      const SizedBox(height: 8),
                      Text('أضف منتجات بالباركود', style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
                    ],
                  ),
                ),
              )
            else
              Flexible(
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 20),
                  shrinkWrap: true,
                  itemCount: _items.length,
                  itemBuilder: (context, i) {
                    final item = _items[i];
                    return _buildItemCard(theme, item, i);
                  },
                ),
              ),
            if (_items.isNotEmpty) ...[
              const Divider(),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                child: Row(
                  children: [
                    Text('الإجمالي:', style: theme.textTheme.titleSmall),
                    const Spacer(),
                    Text(
                      '${_total.toStringAsFixed(3)} $kCurrencySymbol',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
                child: SizedBox(
                  width: double.infinity,
                  height: 48,
                  child: FilledButton.icon(
                    onPressed: (_saving || _hasInvalid) ? null : _save,
                    icon: _saving
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                        : const Icon(Icons.save),
                    label: Text(_saving ? 'جارٍ الحفظ...' : 'حفظ فاتورة التزويد'),
                  ),
                ),
              ),
            ],
            const SizedBox(height: 8),
          ],
        ),
      ),
    ),
  );
  }

  Widget _buildItemCard(ThemeData theme, _CartItem item, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    alignment: Alignment.center,
                    child: Text(
                      item.productName.isNotEmpty ? item.productName[0].toUpperCase() : '?',
                      style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700, fontSize: 13),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(child: Text(item.productName, style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600))),
                  SizedBox(
                    width: 28, height: 28,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.delete_outline, size: 18, color: theme.colorScheme.error),
                      onPressed: () {
                        item.dispose();
                        setState(() => _items.removeAt(index));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  _InfoChip(label: 'المخزون', value: item.currentStock.toStringAsFixed(item.currentStock == item.currentStock.roundToDouble() ? 0 : 2)),
                  const SizedBox(width: 8),
                  _InfoChip(label: 'التكلفة', value: '${item.currentCost.toStringAsFixed(5)} $kCurrencySymbol'),
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: item.qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'الكمية',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: item.costCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: 'سعر الشروة',
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Column(
                      children: [
                        Text('المتوسط', style: TextStyle(fontSize: 9, color: Colors.green.shade700)),
                        Text(
                          item.newCost.toStringAsFixed(5),
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.green.shade700),
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
    );
  }
}

class _ScanOverlayPainter extends CustomPainter {
  final Rect scanRect;
  _ScanOverlayPainter({required this.scanRect});

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
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) => scanRect != oldDelegate.scanRect;
}

class _InfoChip extends StatelessWidget {
  final String label;
  final String value;
  const _InfoChip({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('$label: ', style: TextStyle(fontSize: 11, color: theme.colorScheme.onSurfaceVariant)),
          Text(value, style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: theme.colorScheme.onSurface)),
        ],
      ),
    );
  }
}
