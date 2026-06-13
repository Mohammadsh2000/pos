import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../providers/pos_provider.dart';
import '../constants.dart';
import '../services/database_helper.dart';
import '../services/feedback_service.dart';
import '../utils/notifications.dart';
import '../widgets/compact_icon_button.dart';
import '../widgets/manual_add_sheet.dart';
import 'daily_sales_screen.dart';
import 'invoice_preview_screen.dart';

const double _kMobileBreakpoint = 600;
const double _kTabletBreakpoint = 900;

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
    if (!p.canScanBarcode(code)) return;
    if (_inFlightBarcodes.contains(code)) return;
    _inFlightBarcodes.add(code);
    HapticFeedback.selectionClick();
    try {
      var product =
          p.findProductByBarcode(code) ??
          await DatabaseHelper().getProductByBarcode(code);
      if (!mounted) return;
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
        if (mounted) _showSnack('منتج غير معروف: $code');
      }
    } finally {
      if (mounted) _inFlightBarcodes.remove(code);
    }
  }

  void _showSnack(String msg) {
    if (!mounted) return;
    showTopNotification(context, msg);
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
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => InvoicePreviewScreen(sale: completed),
                  ),
                );
              },
              icon: const Icon(Icons.print, size: 18),
              label: const Text('عرض الفاتورة'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _isCompletingSale = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        if (width >= _kTabletBreakpoint) {
          return _buildDesktopLayout();
        } else if (width >= _kMobileBreakpoint) {
          return _buildTabletLayout();
        }
        return _buildMobileLayout();
      },
    );
  }

  Widget _buildMobileLayout() {
    return Column(
      children: [
        _SummaryCards(),
        Selector<POSProvider, bool>(
          selector: (_, p) => p.isCameraActive,
          builder: (_, active, __) {
            if (!active) return const SizedBox.shrink();
            return _ScannerSection(
              scannerCtrl: widget.scannerCtrl,
              isScanLocked: _isScanLocked,
              onBarcode: _onBarcode,
              onManualAdd: _showManualAddSheet,
              height: 150,
            );
          },
        ),
        Expanded(
          child: _CartArea(
            onComplete: _completeSale,
            isCompleting: _isCompletingSale,
            customerNameCtrl: _customerNameCtrl,
            compact: true,
          ),
        ),
        _buildScannerActionBar(),
      ],
    );
  }

  Widget _buildScannerActionBar() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Row(
        children: [
          Expanded(
            child: Selector<POSProvider, bool>(
              selector: (_, p) => p.isCameraActive,
              builder: (_, active, __) {
                if (active) {
                  return FittedBox(
                    child: OutlinedButton.icon(
                      onPressed: () {
                        context.read<POSProvider>().setCameraActive(false);
                        widget.scannerCtrl.stop();
                      },
                      icon: const Icon(Icons.stop, size: 15),
                      label: const Text('إيقاف المسح', style: TextStyle(fontSize: 13)),
                      style: OutlinedButton.styleFrom(
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      ),
                    ),
                  );
                }
                return FittedBox(
                  child: FilledButton.icon(
                    onPressed: () {
                      context.read<POSProvider>().setCameraActive(true);
                      widget.scannerCtrl.start();
                    },
                    icon: const Icon(Icons.qr_code_scanner, size: 15),
                    label: const Text('بدء المسح', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              child: FilledButton.tonalIcon(
                onPressed: _showManualAddSheet,
                icon: const Icon(Icons.playlist_add, size: 15),
                label: const Text('إضافة منتج', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: FittedBox(
              child: FilledButton.tonalIcon(
                onPressed: () {
                  widget.scannerCtrl.stop();
                  context.read<POSProvider>().startNewSale();
                },
                icon: const Icon(Icons.add_shopping_cart, size: 15),
                label: const Text('فاتورة جديدة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                style: FilledButton.styleFrom(
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTabletLayout() {
    return Column(
      children: [
        _SummaryCards(),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 320,
                child: Column(
                  children: [
                    Selector<POSProvider, bool>(
                      selector: (_, p) => p.isCameraActive,
                      builder: (_, active, __) {
                        if (!active) return const SizedBox.shrink();
                        return _ScannerSection(
                          scannerCtrl: widget.scannerCtrl,
                          isScanLocked: _isScanLocked,
                          onBarcode: _onBarcode,
                          onManualAdd: _showManualAddSheet,
                          height: 200,
                        );
                      },
                    ),
                    _buildScannerActionBar(),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _CartArea(
                  onComplete: _completeSale,
                  isCompleting: _isCompletingSale,
                  customerNameCtrl: _customerNameCtrl,
                  compact: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _buildDesktopLayout() {
    return Column(
      children: [
        _SummaryCards(),
        Expanded(
          child: Row(
            children: [
              SizedBox(
                width: 380,
                child: Column(
                  children: [
                    _ScannerSection(
                      scannerCtrl: widget.scannerCtrl,
                      isScanLocked: _isScanLocked,
                      onBarcode: _onBarcode,
                      onManualAdd: _showManualAddSheet,
                      height: 240,
                    ),
                  ],
                ),
              ),
              const VerticalDivider(width: 1),
              Expanded(
                child: _CartArea(
                  onComplete: _completeSale,
                  isCompleting: _isCompletingSale,
                  customerNameCtrl: _customerNameCtrl,
                  compact: false,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ScannerSection extends StatelessWidget {
  final MobileScannerController scannerCtrl;
  final bool isScanLocked;
  final Future<void> Function(String) onBarcode;
  final VoidCallback onManualAdd;
  final double height;

  const _ScannerSection({
    required this.scannerCtrl,
    required this.isScanLocked,
    required this.onBarcode,
    required this.onManualAdd,
    required this.height,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 4, 12, 4),
      child: Column(
        children: [
          SizedBox(
            height: height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final scanWidth = constraints.maxWidth * 0.8;
                  final scanHeight = constraints.maxHeight * 0.8;
                  final scanRect = Rect.fromLTWH(
                    (constraints.maxWidth - scanWidth) / 2,
                    (constraints.maxHeight - scanHeight) / 2,
                    scanWidth,
                    scanHeight,
                  );
                  return Stack(
                    children: [
                      MobileScanner(
                        controller: scannerCtrl,
                        scanWindow: scanRect,
                        onDetect: (capture) {
                          final barcode = capture.barcodes.firstOrNull;
                          if (barcode?.rawValue != null) {
                            onBarcode(barcode!.rawValue!);
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
                      Positioned(
                        top: 4, right: 4,
                        child: ValueListenableBuilder<TorchState>(
                          valueListenable: scannerCtrl.torchState,
                          builder: (context, state, _) {
                            final isOn = state == TorchState.on;
                            return IconButton(
                              icon: Icon(isOn ? Icons.flash_on : Icons.flash_off, color: Colors.white, size: 20),
                              onPressed: () => scannerCtrl.toggleTorch(),
                              style: IconButton.styleFrom(
                                backgroundColor: Colors.black38,
                                padding: const EdgeInsets.all(6),
                                minimumSize: const Size(32, 32),
                              ),
                            );
                          },
                        ),
                      ),
                      if (isScanLocked)
                        Container(
                          color: Colors.black54,
                          child: const Center(child: CircularProgressIndicator()),
                        ),
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _SummaryCards extends StatelessWidget {
  const _SummaryCards();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 12, 2),
      child: Row(
        children: [
          Expanded(
            child: GestureDetector(
              onTap: () {
                context.read<POSProvider>().loadDailySales();
                Navigator.push(
                  context,
                  MaterialPageRoute(builder: (_) => const DailySalesScreen()),
                );
              },
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 8),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    Icon(
                      Icons.today,
                      size: 14,
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      'اليوم',
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.w900,
                        fontSize: 10,
                      ),
                    ),
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
                    const SizedBox(width: 4),
                    Selector<POSProvider, int>(
                      selector: (_, p) => p.todaySalesCount,
                      builder: (_, count, _) => Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primary,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
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
                  padding: const EdgeInsets.symmetric(
                    horizontal: 5,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: hasItems
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    children: [
                      Icon(
                        Icons.receipt_long,
                        size: 14,
                        color: hasItems
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 2),
                      Text(
                        'الفاتورة',
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: FontWeight.w900,
                          fontSize: 10,
                          color: hasItems
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        '${total.toStringAsFixed(2)} ',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: hasItems
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: hasItems
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.outline,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '$count',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
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
  final bool compact;

  const _CartArea({
    required this.onComplete,
    required this.isCompleting,
    required this.customerNameCtrl,
    this.compact = false,
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
        showTopNotification(context, err);
      } else {
        showTopNotification(context, 'تم تعليق "$name"');
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
                  size: compact ? 48 : 64,
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
        final screenHeight = MediaQuery.of(context).size.height;
        return Column(
          children: [
            Expanded(
              child: Scrollbar(
                child: SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: screenHeight * 0.3,
                      maxHeight: screenHeight * 0.4,
                    ),
                    child: ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      padding: const EdgeInsets.all(8),
                      itemCount: cart.length,
                      itemBuilder: (context, i) {
                        final item = cart[i];
                        final step = item.isKg ? 0.5 : 1;
                        final nextQty = item.quantity + step;
                        final canIncrement = p.isStockAvailable(
                          item.barcode,
                          nextQty,
                        );
                        return Card(
                          margin: const EdgeInsets.only(bottom: 4),
                          child: Padding(
                            padding: const EdgeInsetsDirectional.fromSTEB(
                              12,
                              6,
                              4,
                              6,
                            ),
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
                                              ? const TextInputType.numberWithOptions(
                                                  decimal: true,
                                                )
                                              : TextInputType.number,
                                          autofocus: true,
                                          decoration: const InputDecoration(
                                            labelText: 'الكمية',
                                            border: OutlineInputBorder(),
                                          ),
                                          textInputAction: TextInputAction.done,
                                          onSubmitted: (v) =>
                                              Navigator.pop(ctx, v),
                                        ),
                                        actions: [
                                          TextButton(
                                            onPressed: () => Navigator.pop(ctx),
                                            child: const Text('إلغاء'),
                                          ),
                                          FilledButton(
                                            onPressed: () {
                                              var q = double.tryParse(
                                                ctrl.text,
                                              );
                                              if (q == null || q <= 0) return;
                                              if (!item.isKg)
                                                q = q.floorToDouble();
                                              if (!context
                                                  .read<POSProvider>()
                                                  .isStockAvailable(
                                                    item.barcode,
                                                    q,
                                                  )) {
                                                showTopNotification(
                                                  ctx,
                                                  'الكمية المطلوبة أكبر من المتوفر في المخزون',
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
                                            .textTheme
                                            .titleSmall
                                            ?.copyWith(
                                              fontWeight: FontWeight.bold,
                                            ),
                                      ),
                                      Text(
                                        item.unitLabel,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(
                                        item.productName,
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodyMedium,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                      Text(
                                        '${item.price.toStringAsFixed(2)} $kCurrencySymbol/${item.isKg ? 'كجم' : 'حبة'}',
                                        style: Theme.of(
                                          context,
                                        ).textTheme.bodySmall,
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
                                          .textTheme
                                          .bodySmall
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        CompactIconButton(
                                          icon: Icon(
                                            Icons.add_circle_outline,
                                            size: 18,
                                            color: canIncrement
                                                ? null
                                                : Colors.grey,
                                          ),
                                          onPressed: canIncrement
                                              ? () => p.updateCartItemQuantity(
                                                  i,
                                                  nextQty,
                                                )
                                              : null,
                                        ),
                                        CompactIconButton(
                                          icon: const Icon(
                                            Icons.remove_circle_outline,
                                            size: 18,
                                            color: Colors.orange,
                                          ),
                                          onPressed: () =>
                                              p.updateCartItemQuantity(
                                                i,
                                                item.quantity - step,
                                              ),
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
                  ),
                ),
              ),
            ),
            SafeArea(
              top: false,
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
                            style: Theme.of(context).textTheme.titleLarge
                                ?.copyWith(
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
                            onPressed: isCompleting || cart.isEmpty
                                ? null
                                : onComplete,
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
                              child: const Icon(
                                Icons.pause_circle_outline,
                                size: 20,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ],
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
                      showTopNotification(context, err);
                    }
                  },
                ),
                onTap: () async {
                  final err = await p.restoreParkedSale(id);
                  if (context.mounted) {
                    if (err != null) {
                      showTopNotification(context, err);
                    } else {
                      Navigator.pop(context);
                      showTopNotification(context, 'تم استعادة "$name"');
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
                    setState(() => _showSuggestions = false);
                  },
                );
              },
            ),
          ),
      ],
    );
  }
}
