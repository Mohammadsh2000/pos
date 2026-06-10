import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/pos_provider.dart';
import '../constants.dart';
import '../services/database_helper.dart';
import '../services/feedback_service.dart';
import '../utils/invoice_pdf.dart';
import '../widgets/compact_icon_button.dart';
import '../widgets/quick_add_product_sheet.dart';
import '../widgets/manual_add_sheet.dart';

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

    const bl = 24.0;
    canvas.drawLine(
      scanRect.topLeft,
      Offset(scanRect.left + bl, scanRect.top),
      paint,
    );
    canvas.drawLine(
      scanRect.topLeft,
      Offset(scanRect.left, scanRect.top + bl),
      paint,
    );
    canvas.drawLine(
      scanRect.topRight,
      Offset(scanRect.right - bl, scanRect.top),
      paint,
    );
    canvas.drawLine(
      scanRect.topRight,
      Offset(scanRect.right, scanRect.top + bl),
      paint,
    );
    canvas.drawLine(
      scanRect.bottomLeft,
      Offset(scanRect.left + bl, scanRect.bottom),
      paint,
    );
    canvas.drawLine(
      scanRect.bottomLeft,
      Offset(scanRect.left, scanRect.bottom - bl),
      paint,
    );
    canvas.drawLine(
      scanRect.bottomRight,
      Offset(scanRect.right - bl, scanRect.bottom),
      paint,
    );
    canvas.drawLine(
      scanRect.bottomRight,
      Offset(scanRect.right, scanRect.bottom - bl),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _ScanOverlayPainter oldDelegate) =>
      scanRect != oldDelegate.scanRect;
}

class _ScanOverlay extends StatelessWidget {
  final Rect scanRect;
  const _ScanOverlay({required this.scanRect});

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        Positioned.fill(
          child: CustomPaint(painter: _ScanOverlayPainter(scanRect: scanRect)),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 8,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text(
                'ضع الباركود داخل المستطيل',
                style: TextStyle(color: Colors.white, fontSize: 11),
              ),
            ),
          ),
        ),
      ],
    );
  }
}

class SaleTab extends StatefulWidget {
  final MobileScannerController scannerCtrl;

  const SaleTab({super.key, required this.scannerCtrl});

  @override
  State<SaleTab> createState() => _SaleTabState();
}

class _SaleTabState extends State<SaleTab> {
  bool _isCompletingSale = false;
  bool _isScanLocked = false;
  final Set<String> _inFlightBarcodes = <String>{};
  final _feedback = FeedbackService.instance;
  final _customerNameCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final p = context.read<POSProvider>();
      _customerNameCtrl.text = p.customerName;
    });
  }

  @override
  void dispose() {
    _inFlightBarcodes.clear();
    _customerNameCtrl.dispose();
    super.dispose();
  }

  Future<void> _onBarcode(String code) async {
    if (_isScanLocked) return;
    final p = context.read<POSProvider>();
    if (!p.canScanBarcode(code)) {
      return;
    }
    if (_inFlightBarcodes.contains(code)) {
      return;
    }
    _inFlightBarcodes.add(code);
    HapticFeedback.selectionClick();
    try {
      var product =
          p.findProductByBarcode(code) ??
          await DatabaseHelper().getProductByBarcode(code);
      if (!mounted) {
        return;
      }
      if (product != null) {
        final added = p.addToCart(product);
        if (added) {
          _feedback.play(ScanSound.success);
        } else {
          _feedback.play(ScanSound.warning);
          _showSnack(
            p.cart.isNotEmpty
                ? 'المخزون غير كافٍ لإضافة ${product.name}'
                : 'لا يمكن إضافة ${product.name}',
          );
        }
      } else {
        _feedback.play(ScanSound.unknown);
        _showSnack('منتج غير معروف: $code');
        setState(() => _isScanLocked = true);
        await showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => QuickAddProductSheet(barcode: code),
        );
        if (mounted) setState(() => _isScanLocked = false);
      }
    } finally {
      if (mounted) {
        _inFlightBarcodes.remove(code);
      }
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  Future<void> _showManualAddSheet() async {
    setState(() => _isScanLocked = true);
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ManualAddSheet(),
    );
    if (mounted) setState(() => _isScanLocked = false);
  }

  Future<void> _generateInvoice(Map<String, dynamic> sale) async {
    await generateInvoicePdf(sale);
  }

  Future<void> _completeSale() async {
    if (_isCompletingSale) return;
    final p = context.read<POSProvider>();
    if (p.cart.isEmpty) return;
    setState(() => _isCompletingSale = true);
    try {
      final customerName = _customerNameCtrl.text.trim();
      final completed = await p.completeSale(customerName: customerName);
      if (!mounted) return;
      if (completed == null) {
        _showSnack('تعذّر إتمام الفاتورة');
        return;
      }
      _customerNameCtrl.clear();
      _feedback.play(ScanSound.saleComplete);
      widget.scannerCtrl.stop();
      showDialog(
        context: context,
        builder: (ctx2) => AlertDialog(
        title: const Text('تم إتمام الفاتورة'),
        content: Text(
          'رقم #${completed['id']}\nالمجموع: ${completed['total']} $kCurrencySymbol',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx2),
            child: const Text('إغلاق'),
          ),
          FilledButton.icon(
            onPressed: () {
              Navigator.pop(ctx2);
              _generateInvoice(completed);
            },
            icon: const Icon(Icons.print, size: 18),
            label: const Text('طباعة'),
          ),
        ],
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _isCompletingSale = false);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        _SummaryCards(),
        SizedBox(
          height: 150,
          child: ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: LayoutBuilder(
              builder: (context, constraints) {
                final scanWidth = constraints.maxWidth * 0.3;
                final scanHeight = constraints.maxHeight * 0.4;
                final scanLeft = (constraints.maxWidth - scanWidth) / 2;
                final scanTop = (constraints.maxHeight - scanHeight) / 2;
                final scanRect = Rect.fromLTWH(
                  scanLeft,
                  scanTop,
                  scanWidth,
                  scanHeight,
                );

                return Stack(
                  children: [
                    MobileScanner(
                      controller: widget.scannerCtrl,
                      scanWindow: scanRect,
                      onDetect: (c) {
                        final b = c.barcodes.firstOrNull;
                        if (b?.rawValue != null) {
                          _onBarcode(b!.rawValue!);
                        }
                      },
                      errorBuilder: (context, error, child) {
                        return Container(
                          color: Colors.black54,
                          child: const Center(
                            child: Padding(
                              padding: EdgeInsets.all(16),
                              child: Text(
                                'تعذّر الوصول للكاميرا. تأكد من منح صلاحية الكاميرا من إعدادات الجهاز.',
                                style: TextStyle(
                                  color: Colors.white70,
                                  fontSize: 12,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                    _ScanOverlay(scanRect: scanRect),
                    Selector<POSProvider, bool>(
                      selector: (_, p) => p.isCameraActive,
                      builder: (_, active, _) {
                        if (!active) return const SizedBox.shrink();
                        return Positioned(
                          top: 4,
                          right: 4,
                          child: ValueListenableBuilder<TorchState>(
                            valueListenable: widget.scannerCtrl.torchState,
                            builder: (context, state, _) {
                              final isOn = state == TorchState.on;
                              return IconButton(
                                icon: Icon(
                                  isOn ? Icons.flash_on : Icons.flash_off,
                                  color: Colors.white,
                                  size: 20,
                                ),
                                onPressed: () =>
                                    widget.scannerCtrl.toggleTorch(),
                                style: IconButton.styleFrom(
                                  backgroundColor: Colors.black38,
                                  padding: const EdgeInsets.all(6),
                                  minimumSize: const Size(32, 32),
                                ),
                              );
                            },
                          ),
                        );
                      },
                    ),
                    Selector<POSProvider, bool>(
                      selector: (_, p) => p.isCameraActive,
                      builder: (_, active, _) {
                        if (active) return const SizedBox.shrink();
                        return Positioned.fill(
                          child: GestureDetector(
                            onTap: () {
                              final p = context.read<POSProvider>();
                              p.setCameraActive(true);
                              widget.scannerCtrl.start();
                            },
                            child: Container(
                              color: Colors.black.withValues(alpha: 0.55),
                              child: const Center(
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.qr_code_scanner,
                                      color: Colors.white,
                                      size: 32,
                                    ),
                                    SizedBox(height: 4),
                                    Text(
                                      'اضغط "بدء المسح" للبدء',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 12,
                                      ),
                                    ),
],
                                  ),
                                ),
                              ),
                            ),
                            );
                          },
                        ),
                  ],
                );
              },
            ),
          ),
        ),
      Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 4),
        child: Row(
          children: [
            Expanded(
              child: Selector<POSProvider, bool>(
                selector: (_, p) => p.isCameraActive,
                builder: (_, active, _) => active
                    ? OutlinedButton.icon(
                        onPressed: () {
                          final p = context.read<POSProvider>();
                          p.setCameraActive(false);
                          widget.scannerCtrl.stop();
                        },
                        icon: const Icon(Icons.stop),
                        label: const Text('إيقاف المسح'),
                      )
                    : FilledButton.icon(
                        onPressed: () {
                          final p = context.read<POSProvider>();
                          p.setCameraActive(true);
                          widget.scannerCtrl.start();
                        },
                        icon: const Icon(Icons.qr_code_scanner),
                        label: const Text('بدء المسح'),
                      ),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: _showManualAddSheet,
                icon: const Icon(Icons.playlist_add),
                label: const Text('إضافة منتج'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton.tonalIcon(
                onPressed: () {
                  widget.scannerCtrl.stop();
                  context.read<POSProvider>().startNewSale();
                },
                icon: const Icon(Icons.add_shopping_cart),
                label: const Text('فاتورة جديدة'),
              ),
            ),
          ],
        ),
      ),
      Expanded(
        child: _CartArea(
          onComplete: _completeSale,
          isCompleting: _isCompletingSale,
          customerNameCtrl: _customerNameCtrl,
        ),
      ),
    ],
  );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 8, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: theme.colorScheme.primaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Row(
                children: [
                  Icon(Icons.today, size: 16, color: theme.colorScheme.onPrimaryContainer),
                  const SizedBox(width: 6),
                  Text('اليوم', style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onPrimaryContainer,
                  )),
                  const Spacer(),
                  Selector<POSProvider, double>(
                    selector: (_, p) => p.todaySalesTotal,
                    builder: (_, total, _) => Text(
                      total.toStringAsFixed(2),
                      style: theme.textTheme.bodyMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onPrimaryContainer,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Selector<POSProvider, int>(
                    selector: (_, p) => p.todaySalesCount,
                    builder: (_, count, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: theme.colorScheme.primary,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: Text('$count', style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.onPrimary,
                        fontWeight: FontWeight.bold,
                      )),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Consumer<POSProvider>(
              builder: (_, p, _) {
                final count = p.cartItemsCount;
                final total = p.cartTotal;
                final hasItems = count > 0;
                return Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                    color: hasItems
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(Icons.receipt_long, size: 16,
                        color: hasItems
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text('الفاتورة', style: theme.textTheme.bodySmall?.copyWith(
                        color: hasItems
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      )),
                      const Spacer(),
                      Text('${total.toStringAsFixed(2)} $kCurrencySymbol',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: hasItems
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: hasItems ? theme.colorScheme.secondary : theme.colorScheme.outline,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text('$count', style: theme.textTheme.labelSmall?.copyWith(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                        )),
                      ),
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _CartArea extends StatelessWidget {
  final Future<void> Function() onComplete;
  final bool isCompleting;
  final TextEditingController customerNameCtrl;
  const _CartArea({
    required this.onComplete,
    required this.isCompleting,
    required this.customerNameCtrl,
  });

  void _showParkDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('تعليق الفاتورة'),
        content: TextField(
          controller: controller,
          decoration: const InputDecoration(
            labelText: 'اسم الفاتورة',
            hintText: 'مثال: فاتورة أحمد',
          ),
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.pop(ctx, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('تعليق'),
          ),
        ],
      ),
    ).then((name) async {
      if (name == null || name.isEmpty) return;
      if (!context.mounted) return;
      final p = context.read<POSProvider>();
      final err = await p.parkSale(name);
      if (!context.mounted) return;
      if (err != null) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
      } else {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('تم تعليق "$name"')));
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        final cart = p.cart;
        if (cart.isEmpty) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.shopping_cart_outlined,
                  size: 64,
                  color: Theme.of(context).colorScheme.outline,
                ),
                const SizedBox(height: 8),
                Text(
                  'قم بمسح منتج لبدء الفاتورة',
                  style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                    color: Theme.of(context).colorScheme.outline,
                  ),
                ),
              ],
            ),
          );
        }
        return SingleChildScrollView(
          padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListView.builder(
                padding: const EdgeInsets.all(8),
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                itemCount: cart.length,
                itemBuilder: (context, i) {
                  final item = cart[i];
                  final p = context.read<POSProvider>();
                  final step = item.isKg ? 0.5 : 1;
                  final nextQty = item.quantity + step;
                  final canIncrement = p.isStockAvailable(
                    item.barcode,
                    nextQty,
                  );
                  return Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
                      child: Row(
                        children: [
                          GestureDetector(
                            onTap: () {
                              final ctrl = TextEditingController(
                                text: item.isKg
                                    ? item.quantity.toStringAsFixed(2)
                                    : item.quantity.toInt().toString(),
                              );
                              showDialog(
                                context: context,
                                builder: (ctx) => AlertDialog(
                                  title: Text(item.productName),
                                  content: TextField(
                                    controller: ctrl,
                                    keyboardType: item.isKg
                                        ? const TextInputType.numberWithOptions(decimal: true)
                                        : TextInputType.number,
                                    autofocus: true,
                                    decoration: const InputDecoration(
                                      labelText: 'الكمية',
                                      border: OutlineInputBorder(),
                                    ),
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (v) => Navigator.pop(ctx, v),
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () => Navigator.pop(ctx),
                                      child: const Text('إلغاء'),
                                    ),
                                    FilledButton(
                                      onPressed: () {
                                        var q = double.tryParse(ctrl.text);
                                        if (q == null || q <= 0) return;
                                        if (!item.isKg) q = q.floorToDouble();
                                        if (!context
                                            .read<POSProvider>()
                                            .isStockAvailable(item.barcode, q)) {
                                          ScaffoldMessenger.of(ctx).showSnackBar(
                                            const SnackBar(
                                              content: Text(
                                                'الكمية المطلوبة أكبر من المتوفر في المخزون',
                                              ),
                                            ),
                                          );
                                          return;
                                        }
                                        Navigator.pop(ctx, ctrl.text);
                                      },
                                      child: const Text('حفظ'),
                                    ),
                                  ],
                                ),
                              ).then((v) {
                                if (v == null || !context.mounted) return;
                                var q = double.tryParse(v as String);
                                if (q != null && q > 0) {
                                  if (!item.isKg) q = q.floorToDouble();
                                  p.updateCartItemQuantity(i, q);
                                }
                              });
                            },
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.isKg
                                      ? item.quantity.toStringAsFixed(2)
                                      : '${item.quantity.toInt()}',
                                  style: Theme.of(context)
                                      .textTheme.titleSmall
                                      ?.copyWith(fontWeight: FontWeight.bold),
                                ),
                                Text(
                                  item.unitLabel,
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  item.productName,
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  overflow: TextOverflow.ellipsis,
                                ),
                                Text(
                                  '${item.price.toStringAsFixed(2)} $kCurrencySymbol/${item.isKg ? 'كجم' : 'حبة'}',
                                  style: Theme.of(context).textTheme.bodySmall,
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 4),
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(
                                '${item.subtotal.toStringAsFixed(2)} $kCurrencySymbol',
                                style: Theme.of(context)
                                    .textTheme.bodySmall
                                    ?.copyWith(fontWeight: FontWeight.bold),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CompactIconButton(
                                    icon: Icon(
                                      Icons.add_circle_outline,
                                      size: 18,
                                      color: canIncrement ? null : Colors.grey,
                                    ),
                                    onPressed: canIncrement
                                        ? () => p.updateCartItemQuantity(i, nextQty)
                                        : null,
                                  ),
                                  CompactIconButton(
                                    icon: const Icon(
                                      Icons.remove_circle_outline,
                                      size: 18,
                                      color: Colors.orange,
                                    ),
                                    onPressed: () =>
                                        p.updateCartItemQuantity(i, item.quantity - step),
                                  ),
                                  CompactIconButton(
                                    icon: const Icon(
                                      Icons.delete_outline,
                                      color: Colors.red,
                                      size: 18,
                                    ),
                                    onPressed: () => p.removeFromCart(i),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
              SafeArea(
                top: false,
                child: SingleChildScrollView(
                  child: Container(
                    padding: const EdgeInsetsDirectional.fromSTEB(16, 8, 16, 8),
                    decoration: BoxDecoration(
                      color: Theme.of(context).colorScheme.surfaceContainerHighest,
                      border: Border(
                        top: BorderSide(color: Theme.of(context).dividerColor),
                      ),
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _CustomerNameField(controller: customerNameCtrl),
                        const SizedBox(height: 8),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              'المجموع:',
                              style: Theme.of(context).textTheme.titleMedium,
                            ),
                            Consumer<POSProvider>(
                              builder: (_, p, _) => Text(
                                '${p.cartTotal.toStringAsFixed(2)} $kCurrencySymbol',
                                style: Theme.of(context).textTheme.titleLarge?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: Theme.of(context).colorScheme.primary,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            Expanded(
                              child: FilledButton.icon(
                                onPressed: isCompleting || cart.isEmpty ? null : onComplete,
                                icon: isCompleting
                                    ? const SizedBox(
                                        width: 18,
                                        height: 18,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2,
                                          color: Colors.white,
                                        ),
                                      )
                                    : const Icon(Icons.check_circle),
                                label: const Text('إتمام الفاتورة'),
                              ),
                            ),
                            if (cart.isNotEmpty) ...[
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 52,
                                height: 48,
                                child: FilledButton.tonal(
                                  onPressed: () => _showParkDialog(context),
                                  child: const Icon(Icons.pause_circle_outline, size: 20),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

class ParkedCartsList extends StatelessWidget {
  const ParkedCartsList({super.key});

  @override
  Widget build(BuildContext context) {
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        final carts = p.parkedCarts;
        if (carts.isEmpty) {
          return const Padding(
            padding: EdgeInsets.all(32),
            child: Center(child: Text('لا توجد فواتير معلقة')),
          );
        }
        return ListView.builder(
          shrinkWrap: true,
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 32),
          itemCount: carts.length,
          itemBuilder: (context, i) {
            final cart = carts[i];
            final id = cart['id'] as int;
            final name = cart['name'] as String;
            final total = (cart['total'] as num).toDouble();
            final count = cart['items_count'] as int;
            final createdAt = cart['created_at'] as String;
            return Card(
              margin: const EdgeInsets.only(bottom: 8),
              child: ListTile(
                title: Text(
                  name,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text('$count صنف • $createdAt'),
                trailing: Text('${total.toStringAsFixed(2)} $kCurrencySymbol'),
                leading: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    final err = await p.deleteParkedSale(id);
                    if (context.mounted && err != null) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(err)));
                    }
                  },
                ),
                onTap: () async {
                  final err = await p.restoreParkedSale(id);
                  if (context.mounted) {
                    if (err != null) {
                      ScaffoldMessenger.of(
                        context,
                      ).showSnackBar(SnackBar(content: Text(err)));
                    } else {
                      Navigator.pop(context);
                      ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text('تم استعادة "$name"')),
                      );
                    }
                  }
                },
              ),
            );
          },
        );
      },
    );
  }
}

class _CustomerNameField extends StatefulWidget {
  final TextEditingController controller;
  const _CustomerNameField({required this.controller});

  @override
  State<_CustomerNameField> createState() => _CustomerNameFieldState();
}

class _CustomerNameFieldState extends State<_CustomerNameField> {
  List<String> _suggestions = [];
  bool _showSuggestions = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() {
    final p = context.read<POSProvider>();
    p.customerName = widget.controller.text;
    final text = widget.controller.text.trim();
    if (text.isNotEmpty) {
      p.searchCustomers(text).then((_) {
        if (mounted) {
          final suggestions = p.customerSuggestions;
          setState(() {
            _suggestions = suggestions.map((c) => c.name).toList();
            _showSuggestions = _suggestions.isNotEmpty;
          });
        }
      });
    } else {
      setState(() {
        _suggestions = [];
        _showSuggestions = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: widget.controller,
          decoration: InputDecoration(
            labelText: 'اسم العميل (اختياري)',
            hintText: 'اكتب اسم العميل للدين',
            prefixIcon: const Icon(Icons.person, size: 20),
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
            contentPadding: const EdgeInsets.symmetric(
              horizontal: 12,
              vertical: 8,
            ),
            isDense: true,
            suffixIcon: widget.controller.text.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      widget.controller.clear();
                      context.read<POSProvider>().customerName = '';
                    },
                  )
                : null,
          ),
        ),
        if (_showSuggestions)
          Container(
            constraints: const BoxConstraints(maxHeight: 150),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              border: Border.all(color: Theme.of(context).dividerColor),
              borderRadius: BorderRadius.circular(8),
            ),
            child: ListView.builder(
              shrinkWrap: true,
              physics: const ClampingScrollPhysics(),
              itemCount: _suggestions.length,
              itemBuilder: (context, i) {
                final name = _suggestions[i];
                return ListTile(
                  dense: true,
                  title: Text(name),
                  leading: const Icon(Icons.person_outline, size: 18),
                  onTap: () {
                    widget.controller.text = name;
                    widget.controller.selection = TextSelection.fromPosition(
                      TextPosition(offset: name.length),
                    );
                    context.read<POSProvider>().customerName = name;
                    setState(() {
                      _showSuggestions = false;
                    });
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
