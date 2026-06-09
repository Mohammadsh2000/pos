import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import '../models/sale_item.dart';
import '../providers/pos_provider.dart';
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
          left: 0, right: 0, bottom: 8,
          child: Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.black54,
                borderRadius: BorderRadius.circular(4),
              ),
              child: const Text('ضع الباركود داخل المستطيل', style: TextStyle(color: Colors.white, fontSize: 11)),
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
  final Set<String> _inFlightBarcodes = <String>{};
  final _feedback = FeedbackService.instance;

  @override
  void dispose() {
    _inFlightBarcodes.clear();
    super.dispose();
  }

  Future<void> _onBarcode(String code) async {
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
      var product = p.findProductByBarcode(code) ??
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
          _showSnack(p.cart.isNotEmpty
              ? 'المخزون غير كافٍ لإضافة ${product.name}'
              : 'لا يمكن إضافة ${product.name}');
        }
      } else {
        _feedback.play(ScanSound.unknown);
        _showSnack('منتج غير معروف: $code');
        showModalBottomSheet(
          context: context,
          isScrollControlled: true,
          builder: (_) => QuickAddProductSheet(barcode: code),
        );
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

  void _showManualAddSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => const ManualAddSheet(),
    );
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
      final completed = await p.completeSale();
      if (!mounted) return;
      if (completed == null) {
        _showSnack('تعذّر إتمام الفاتورة');
        return;
      }
      _feedback.play(ScanSound.saleComplete);
      widget.scannerCtrl.stop();
      showDialog(
        context: context,
        builder: (ctx2) => AlertDialog(
          title: const Text('تم إتمام الفاتورة'),
          content: Text(
            'رقم #${completed['id']}\nالمجموع: ${completed['total']} ر.س',
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
                final scanRect = Rect.fromLTWH(scanLeft, scanTop, scanWidth, scanHeight);

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
                                style: TextStyle(color: Colors.white70, fontSize: 12),
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
                                    Icon(Icons.qr_code_scanner, color: Colors.white, size: 32),
                                    SizedBox(height: 4),
                                    Text(
                                      'اضغط "بدء المسح" للبدء',
                                      style: TextStyle(color: Colors.white, fontSize: 12),
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
          child: _CartArea(onComplete: _completeSale, isCompleting: _isCompletingSale),
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
                  Text(
                    'اليوم',
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
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
                  const SizedBox(width: 6),
                  Selector<POSProvider, int>(
                    selector: (_, p) => p.todaySalesCount,
                    builder: (_, count, _) => Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
          const SizedBox(width: 8),
          Expanded(
            child: Selector<POSProvider, _CartSummary>(
              selector: (_, p) => _CartSummary(p.cartItemsCount, p.cartTotal),
              builder: (_, s, _) {
                final hasItems = s.count > 0;
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
                      Icon(
                        Icons.receipt_long,
                        size: 16,
                        color: hasItems
                            ? theme.colorScheme.onSecondaryContainer
                            : theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'الفاتورة',
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: hasItems
                              ? theme.colorScheme.onSecondaryContainer
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const Spacer(),
                      Text(
                        s.total.toStringAsFixed(2),
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
                          color: hasItems
                              ? theme.colorScheme.secondary
                              : theme.colorScheme.outline,
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${s.count}',
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

class _CartSummary {
  final int count;
  final double total;
  const _CartSummary(this.count, this.total);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is _CartSummary && other.count == count && other.total == total);

  @override
  int get hashCode => Object.hash(count, total);
}

class _CartArea extends StatelessWidget {
  final Future<void> Function() onComplete;
  final bool isCompleting;
  const _CartArea({required this.onComplete, required this.isCompleting});

  void _showParkDialog(BuildContext context) {
    final controller = TextEditingController();
    showDialog(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: ui.TextDirection.rtl,
        child: AlertDialog(
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم تعليق "$name"')),
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Selector<POSProvider, List<SaleItem>>(
      selector: (_, p) => p.cart,
      builder: (context, cart, _) {
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
        return Column(
          children: [
            Expanded(
              child: ListView.builder(
                padding: const EdgeInsets.all(8),
                itemCount: cart.length,
                itemBuilder: (context, i) {
                  final item = cart[i];
                  return Card(
                    margin: const EdgeInsets.only(bottom: 4),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(12, 6, 4, 6),
                      child: Row(
                        children: [
                          Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '${item.quantity}',
                                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Text('عدد', style: Theme.of(context).textTheme.bodySmall),
                            ],
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
                                  '${item.price.toStringAsFixed(2)} ر.س',
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
                                '${item.subtotal.toStringAsFixed(2)} ر.س',
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                      fontWeight: FontWeight.bold,
                                    ),
                              ),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  CompactIconButton(
                                    icon: const Icon(Icons.add_circle_outline, size: 18),
                                    onPressed: () => context
                                        .read<POSProvider>()
                                        .updateCartItemQuantity(i, item.quantity + 1),
                                  ),
                                  CompactIconButton(
                                    icon: const Icon(Icons.remove_circle_outline, size: 18, color: Colors.orange),
                                    onPressed: () => context
                                        .read<POSProvider>()
                                        .updateCartItemQuantity(i, item.quantity - 1),
                                  ),
                                  CompactIconButton(
                                    icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
                                    onPressed: () => context.read<POSProvider>().removeFromCart(i),
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
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text('المجموع:', style: Theme.of(context).textTheme.titleMedium),
                        Selector<POSProvider, double>(
                          selector: (_, p) => p.cartTotal,
                          builder: (_, total, _) => Text(
                            '${total.toStringAsFixed(2)} ر.س',
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
                                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
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
                title: Text(name, style: const TextStyle(fontWeight: FontWeight.bold)),
                subtitle: Text('$count صنف • $createdAt'),
                trailing: Text('${total.toStringAsFixed(2)} ر.س'),
                leading: IconButton(
                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                  onPressed: () async {
                    final err = await p.deleteParkedSale(id);
                    if (context.mounted && err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
                    }
                  },
                ),
                onTap: () async {
                  final err = await p.restoreParkedSale(id);
                  if (context.mounted) {
                    if (err != null) {
                      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(err)));
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
