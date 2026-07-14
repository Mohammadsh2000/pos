import 'dart:async';

import 'package:flutter/material.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:provider/provider.dart';
import '../constants.dart';
import '../models/product.dart';
import '../models/stock_in_entry.dart';
import '../providers/pos_provider.dart';
import '../services/database_helper.dart';
import '../utils/notifications.dart';
import '../utils/barcode_utils.dart';
import '../screens/purchase_history_screen.dart';

class _CartItem {
  final int productId;
  final String productName;
  final double currentStock;
  final double currentCost;
  final TextEditingController qtyCtrl;
  final TextEditingController costCtrl;
  final TextEditingController unitPriceCtrl;
  final String saleType;
  final int piecesPerCarton;
  bool _updating = false;

  bool get isCarton => saleType == 'carton';

  _CartItem({
    required this.productId,
    required this.productName,
    required this.currentStock,
    required this.currentCost,
    required double quantity,
    required double batchCost,
    this.saleType = 'unit',
    this.piecesPerCarton = 1,
  })  : qtyCtrl = TextEditingController(text: quantity.toStringAsFixed(quantity == quantity.roundToDouble() ? 0 : 2)),
        costCtrl = TextEditingController(text: (batchCost * quantity).toStringAsFixed(3)),
        unitPriceCtrl = TextEditingController(text: batchCost.toStringAsFixed(3)) {
    qtyCtrl.addListener(_onQtyChanged);
    unitPriceCtrl.addListener(_onUnitPriceChanged);
    costCtrl.addListener(_onTotalChanged);
  }

  String get qtyLabel {
    switch (saleType) {
      case 'kg': return 'الوزن (كغ)';
      case 'carton': return 'العدد (كرتونة)';
      default: return 'الكمية';
    }
  }

  String get unitPriceLabel {
    switch (saleType) {
      case 'kg': return 'سعر الكيلو';
      case 'carton': return 'سعر الكرتونة';
      default: return 'سعر الحبة';
    }
  }

  String get stockLabel {
    if (isCarton && piecesPerCarton > 0) {
      final cartons = currentStock / piecesPerCarton;
      final s = cartons == cartons.roundToDouble()
          ? cartons.toInt().toString()
          : cartons.toStringAsFixed(2);
      return 'المخزون الحالي: $s كرتونة';
    }
    final s = currentStock == currentStock.roundToDouble()
        ? currentStock.toInt().toString()
        : currentStock.toStringAsFixed(2);
    switch (saleType) {
      case 'kg': return 'المخزون الحالي: $s كغ';
      default: return 'المخزون الحالي: $s';
    }
  }

  String get avgLabel {
    if (isCarton && piecesPerCarton > 0) {
      return 'متوسط سعر الكرتونة ${(newCost * piecesPerCarton).toStringAsFixed(3)}';
    }
    final prefix = switch (saleType) {
      'kg' => 'متوسط سعر الكيلو',
      _ => 'المتوسط',
    };
    return '$prefix ${newCost.toStringAsFixed(3)}';
  }

  double get quantity => double.tryParse(qtyCtrl.text) ?? 0;
  double get totalPrice => double.tryParse(costCtrl.text) ?? 0;
  double get batchCost => quantity > 0 ? totalPrice / quantity : totalPrice;
  double get subtotal => totalPrice;
  double get qtyInPieces => isCarton ? quantity * piecesPerCarton : quantity;
  double get newStock => currentStock + qtyInPieces;
  double get newCost {
    if (isCarton && piecesPerCarton > 0) {
      final costPerPiece = batchCost / piecesPerCarton;
      final totalValue = currentStock * currentCost + qtyInPieces * costPerPiece;
      final raw = newStock > 0 ? totalValue / newStock : costPerPiece;
      return double.parse(raw.toStringAsFixed(5));
    }
    final totalValue = currentStock * currentCost + quantity * batchCost;
    final raw = newStock > 0 ? totalValue / newStock : batchCost;
    return double.parse(raw.toStringAsFixed(5));
  }

  void _onQtyChanged() {
    if (_updating) return;
    _updating = true;
    final up = double.tryParse(unitPriceCtrl.text) ?? 0;
    final q = double.tryParse(qtyCtrl.text) ?? 0;
    if (q > 0 && up >= 0) {
      costCtrl.text = (up * q).toStringAsFixed(3);
    }
    _updating = false;
  }

  void _onUnitPriceChanged() {
    if (_updating) return;
    _updating = true;
    final up = double.tryParse(unitPriceCtrl.text) ?? 0;
    if (quantity > 0 && up > 0) {
      final newTotal = up * quantity;
      costCtrl.text = newTotal.toStringAsFixed(3);
    }
    _updating = false;
  }

  void _onTotalChanged() {
    if (_updating) return;
    _updating = true;
    final tp = double.tryParse(costCtrl.text) ?? 0;
    if (quantity > 0 && tp > 0) {
      unitPriceCtrl.text = (tp / quantity).toStringAsFixed(3);
    }
    _updating = false;
  }

  void dispose() {
    qtyCtrl.removeListener(_onQtyChanged);
    qtyCtrl.dispose();
    unitPriceCtrl.removeListener(_onUnitPriceChanged);
    unitPriceCtrl.dispose();
    costCtrl.removeListener(_onTotalChanged);
    costCtrl.dispose();
  }
}

class StockInSheet extends StatefulWidget {
  const StockInSheet({super.key});

  @override
  State<StockInSheet> createState() => _StockInSheetState();
}

class _StockInSheetState extends State<StockInSheet> with WidgetsBindingObserver {
  final _barcodeCtrl = TextEditingController();
  final _merchantNameCtrl = TextEditingController();
  List<String> _merchantSuggestions = [];
  final _merchantFieldKey = GlobalKey();
  OverlayEntry? _merchantOverlay;
  final _scannerCtrl = MobileScannerController(
    autoStart: false,
    torchEnabled: false,
    cameraResolution: const Size(1280, 720),
    formats: const [
      BarcodeFormat.ean13,
      BarcodeFormat.ean8,
      BarcodeFormat.upcA,
      BarcodeFormat.upcE,
      BarcodeFormat.code128,
      BarcodeFormat.code39,
      BarcodeFormat.code93,
      BarcodeFormat.itf,
    ],
  );
  final List<_CartItem> _items = [];
  bool _saving = false;
  bool _scannerOn = false;
  final Map<String, DateTime> _lastStockInScanPerCode = {};
  final _barcodeFieldKey = GlobalKey();
  List<Product> _barcodeSuggestions = [];
  OverlayEntry? _barcodeOverlay;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _barcodeCtrl.addListener(_onBarcodeChanged);
    _merchantNameCtrl.addListener(_onMerchantNameChanged);
    _loadMerchantSuggestions();
  }

  Future<void> _loadMerchantSuggestions() async {
    final names = await DatabaseHelper().getDistinctMerchantNames();
    if (mounted) setState(() => _merchantSuggestions = names);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.paused && _scannerOn) {
      setState(() => _scannerOn = false);
    }
  }

  Future<void> _stopScanner() async {
    try {
      await _scannerCtrl.stop();
    } catch (_) {}
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _barcodeCtrl.dispose();
    _merchantNameCtrl.removeListener(_onMerchantNameChanged);
    _merchantNameCtrl.dispose();
    _dismissBarcodeOverlay();
    _dismissMerchantOverlay();
    unawaited(_stopScanner().then((_) => _scannerCtrl.dispose()));
    for (final item in _items) {
      item.dispose();
    }
    super.dispose();
  }

  Future<void> _onBarcode(String code) async {
    if (code.trim().isEmpty) return;
    final now = DateTime.now();
    final lastScan = _lastStockInScanPerCode[code];
    if (lastScan != null && now.difference(lastScan) < const Duration(seconds: 2)) return;
    _lastStockInScanPerCode[code] = now;
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
          saleType: product.saleType,
          piecesPerCarton: product.piecesPerCarton,
        ));
      }
      _barcodeCtrl.clear();
    });
  }

  void _addProduct(Product product) {
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
          saleType: product.saleType,
          piecesPerCarton: product.piecesPerCarton,
        ));
      }
      _barcodeCtrl.clear();
      _barcodeSuggestions = [];
      _dismissBarcodeOverlay();
    });
  }

  void _dismissBarcodeOverlay() {
    _barcodeOverlay?.remove();
    _barcodeOverlay = null;
  }

  void _showBarcodeOverlay() {
    _dismissBarcodeOverlay();
    _barcodeOverlay = OverlayEntry(
      builder: (_) {
        final renderBox = _barcodeFieldKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) return const SizedBox.shrink();
        final screenWidth = MediaQuery.of(context).size.width;
        final overlayWidth = screenWidth * 0.8;
        final pos = renderBox.localToGlobal(Offset.zero);
        final fieldWidth = renderBox.size.width;
        final left = pos.dx + (fieldWidth - overlayWidth) / 2;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: pos.dy + renderBox.size.height + 4,
              child: Material(
                elevation: 6,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(8),
                surfaceTintColor: Colors.transparent,
                child: Container(
                  width: overlayWidth,
                  constraints: const BoxConstraints(maxHeight: 120),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _barcodeSuggestions.length,
                    itemBuilder: (context, i) {
                      final product = _barcodeSuggestions[i];
                      return InkWell(
                        onTap: () => _addProduct(product),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                          child: Row(
                            children: [
                              Icon(Icons.shopping_bag_outlined, size: 14, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(product.name, style: const TextStyle(fontSize: 13)),
                              ),
                              Text('(${product.barcode})', style: TextStyle(fontSize: 11, color: Theme.of(context).colorScheme.onSurfaceVariant)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_barcodeOverlay!);
  }

  void _dismissMerchantOverlay() {
    _merchantOverlay?.remove();
    _merchantOverlay = null;
  }

  void _showMerchantOverlay() {
    _dismissMerchantOverlay();
    _merchantOverlay = OverlayEntry(
      builder: (_) {
        final renderBox = _merchantFieldKey.currentContext?.findRenderObject() as RenderBox?;
        if (renderBox == null || !renderBox.hasSize) return const SizedBox.shrink();
        final screenWidth = MediaQuery.of(context).size.width;
        final overlayWidth = screenWidth * 0.8;
        final pos = renderBox.localToGlobal(Offset.zero);
        final fieldWidth = renderBox.size.width;
        final left = pos.dx + (fieldWidth - overlayWidth) / 2;
        return Stack(
          children: [
            Positioned(
              left: left,
              top: pos.dy + renderBox.size.height + 4,
              child: Material(
                elevation: 6,
                shadowColor: Colors.black38,
                borderRadius: BorderRadius.circular(8),
                surfaceTintColor: Colors.transparent,
                child: Container(
                  width: overlayWidth,
                  constraints: const BoxConstraints(maxHeight: 160),
                  child: ListView.builder(
                    padding: EdgeInsets.zero,
                    itemCount: _merchantSuggestions.length,
                    itemBuilder: (context, i) {
                      final name = _merchantSuggestions[i];
                      return InkWell(
                        onTap: () {
                          _merchantNameCtrl.text = name;
                          _merchantNameCtrl.selection = TextSelection.fromPosition(
                            TextPosition(offset: name.length),
                          );
                          _merchantSuggestions = [];
                          _dismissMerchantOverlay();
                          setState(() {});
                        },
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                          child: Row(
                            children: [
                              Icon(Icons.person_outline, size: 16, color: Theme.of(context).colorScheme.onSurfaceVariant),
                              const SizedBox(width: 6),
                              Text(name, style: const TextStyle(fontSize: 13)),
                            ],
                          ),
                        ),
                      );
                    },
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
    Overlay.of(context).insert(_merchantOverlay!);
  }

  void _onMerchantNameChanged() {
    final text = _merchantNameCtrl.text.trim();
    if (text.isNotEmpty) {
      final filtered = _merchantSuggestions.where((n) => n.toLowerCase().contains(text.toLowerCase())).toList();
      if (filtered.isNotEmpty) {
        _showMerchantOverlay();
      } else {
        _dismissMerchantOverlay();
      }
    } else {
      _dismissMerchantOverlay();
    }
  }

  void _onBarcodeChanged() {
    final text = _barcodeCtrl.text.trim();
    if (text.isNotEmpty) {
      DatabaseHelper().searchProducts(text).then((results) {
        if (mounted && _barcodeCtrl.text.trim() == text) {
          final isExactMatch = results.any((p) => p.name == text || p.barcode == text);
          if (results.isNotEmpty && !isExactMatch) {
            _barcodeSuggestions = results;
            _showBarcodeOverlay();
          } else {
            _barcodeSuggestions = [];
            _dismissBarcodeOverlay();
          }
          setState(() {});
        }
      });
    } else {
      _barcodeSuggestions = [];
      _dismissBarcodeOverlay();
      setState(() {});
    }
  }

  void _toggleScanner() {
    setState(() {
      _scannerOn = !_scannerOn;
      if (_scannerOn) {
        _scannerCtrl.start();
      } else {
        unawaited(_stopScanner());
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
    final merchantName = _merchantNameCtrl.text.trim();
    final err = await context.read<POSProvider>().createPurchase(entries, merchantName: merchantName.isNotEmpty ? merchantName : null);
    if (mounted) {
      setState(() => _saving = false);
      if (err != null) {
        showTopNotification(context, err);
      } else {
        if (_scannerOn) {
          unawaited(_stopScanner());
          _scannerOn = false;
        }
        if (!mounted) return;
        Navigator.pop(context, true);
      }
    }
  }

  double get _total => _items.fold(0.0, (s, i) => s + i.subtotal);
  bool get _hasInvalid => _items.any((i) => i.quantity <= 0 || i.batchCost <= 0);
  int get _validCount => _items.where((i) => i.quantity > 0 && i.batchCost > 0).length;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;
    return PopScope(
      canPop: !_scannerOn,
      onPopInvokedWithResult: (didPop, _) async {
        if (!didPop) {
          if (_scannerOn) {
            await _stopScanner();
            if (!mounted) return;
            setState(() => _scannerOn = false);
          }
          Navigator.pop(context);
        }
      },
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: 0.08),
                borderRadius: const BorderRadius.vertical(top: Radius.circular(20)),
              ),
              child: Column(
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
                        Container(
                          width: 40, height: 40,
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(12),
                          ),
                          child: Icon(Icons.receipt_long, color: theme.colorScheme.primary, size: 22),
                        ),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('فاتورة شراء', style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                            Text('تسجيل مشتريات جديدة', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                          ],
                        ),
                        const Spacer(),
                        IconButton(
                          icon: const Icon(Icons.history, size: 20),
                          tooltip: 'سجل المشتريات',
                          onPressed: () {
                            Navigator.push(
                              context,
                              MaterialPageRoute(builder: (_) => const PurchaseHistoryScreen()),
                            );
                          },
                          style: IconButton.styleFrom(
                            backgroundColor: theme.colorScheme.surfaceContainerLow,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                          ),
                        ),
                        const SizedBox(width: 4),
                        IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () async {
                            if (_scannerOn) {
                              await _stopScanner();
                              if (!mounted) return;
                              setState(() => _scannerOn = false);
                            }
                            Navigator.pop(context);
                          },
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                child: Padding(
                  padding: EdgeInsets.only(bottom: bottomInset),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (_items.isNotEmpty) ...[
                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 4),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [
                                  theme.colorScheme.primary.withValues(alpha: 0.08),
                                  theme.colorScheme.primary.withValues(alpha: 0.02),
                                ],
                                begin: Alignment.centerRight, end: Alignment.centerLeft,
                              ),
                              borderRadius: BorderRadius.circular(14),
                              border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.12)),
                            ),
                            child: Row(
                              children: [
                                _StatItem(label: 'عدد الأصناف', value: '${_items.length}', icon: Icons.inventory_2, color: theme.colorScheme.primary),
                                Container(height: 30, width: 1, color: theme.colorScheme.primary.withValues(alpha: 0.15)),
                                _StatItem(label: 'الإجمالي', value: '${_total.toStringAsFixed(3)} $kCurrencySymbol', icon: Icons.attach_money, color: Colors.green.shade600),
                                Container(height: 30, width: 1, color: theme.colorScheme.primary.withValues(alpha: 0.15)),
                                _StatItem(label: 'صالح', value: '$_validCount', icon: Icons.check_circle_outline, color: Colors.green.shade600),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      const SizedBox(height: 12),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Row(
                          children: [
                            Expanded(
                              child: TextField(
                                key: _barcodeFieldKey,
                                controller: _barcodeCtrl,
                                decoration: InputDecoration(
                                  hintText: 'ابحث بالاسم أو الباركود',
                                  hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                                  prefixIcon: InkWell(
                                    onTap: _toggleScanner,
                                    borderRadius: BorderRadius.circular(12),
                                    child: Padding(
                                      padding: const EdgeInsets.all(12),
                                      child: Icon(
                                        Icons.qr_code_scanner,
                                        size: 20,
                                        color: _scannerOn ? theme.colorScheme.primary : theme.colorScheme.onSurfaceVariant,
                                      ),
                                    ),
                                  ),
                                  suffixIcon: _barcodeCtrl.text.isNotEmpty
                                      ? IconButton(
                                          icon: const Icon(Icons.add_circle_outline, size: 20),
                                          onPressed: () => _onBarcode(_barcodeCtrl.text),
                                        )
                                      : null,
                                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                                  contentPadding: const EdgeInsets.symmetric(vertical: 12),
                                  filled: true,
                                  fillColor: theme.colorScheme.surfaceContainerLowest,
                                ),
                                onSubmitted: _onBarcode,
                                onChanged: (_) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            AnimatedContainer(
                              duration: const Duration(milliseconds: 200),
                              height: 48, width: 48,
                              decoration: BoxDecoration(
                                color: _scannerOn ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerLowest,
                                borderRadius: BorderRadius.circular(14),
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
                            borderRadius: BorderRadius.circular(14),
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
                                          if (b?.rawValue != null && isProductBarcode(b!.format)) {
                                            _onBarcode(b.rawValue!);
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
                                        child: ValueListenableBuilder<MobileScannerState>(
                                          valueListenable: _scannerCtrl,
                                          builder: (context, state, _) {
                                            final isOn = state.torchState == TorchState.on;
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
                                          onPressed: () async {
                                            await _stopScanner();
                                            if (mounted) setState(() => _scannerOn = false);
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
                      const SizedBox(height: 10),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: TextField(
                          key: _merchantFieldKey,
                          controller: _merchantNameCtrl,
                          decoration: InputDecoration(
                            hintText: 'اسم التاجر (اختياري)',
                            hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.6)),
                            prefixIcon: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Icon(Icons.store_outlined, size: 20, color: theme.colorScheme.onSurfaceVariant),
                            ),
                            suffixIcon: _merchantNameCtrl.text.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear, size: 18),
                                    onPressed: () {
                                      _merchantNameCtrl.clear();
                                      _dismissMerchantOverlay();
                                    },
                                  )
                                : null,
                            border: OutlineInputBorder(borderRadius: BorderRadius.circular(14)),
                            contentPadding: const EdgeInsets.symmetric(vertical: 12),
                            filled: true,
                            fillColor: theme.colorScheme.surfaceContainerLowest,
                          ),
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(height: 12),
                      if (_items.isEmpty)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 40, horizontal: 20),
                          child: Center(
                            child: Column(
                              children: [
                                Container(
                                  width: 80, height: 80,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.08),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Icon(Icons.shopping_cart_outlined, size: 40, color: theme.colorScheme.primary.withValues(alpha: 0.4)),
                                ),
                                const SizedBox(height: 16),
                                Text('لا توجد منتجات بعد', style: theme.textTheme.titleSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
                                const SizedBox(height: 4),
                                Text('أضف منتجات بالبحث أو الباركود', style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.7))),
                              ],
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _items.length,
                          itemBuilder: (context, i) {
                            final item = _items[i];
                            return _buildItemCard(theme, item, i);
                          },
                        ),
                      if (_items.isNotEmpty) ...[
                        const SizedBox(height: 8),
                        Container(
                          margin: const EdgeInsets.symmetric(horizontal: 20),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary.withValues(alpha: 0.06),
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: theme.colorScheme.primary.withValues(alpha: 0.12)),
                          ),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                            child: Row(
                              children: [
                                Container(
                                  width: 36, height: 36,
                                  decoration: BoxDecoration(
                                    color: theme.colorScheme.primary.withValues(alpha: 0.15),
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                  child: Icon(Icons.receipt, color: theme.colorScheme.primary, size: 18),
                                ),
                                const SizedBox(width: 12),
                                Text('الإجمالي', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                                const Spacer(),
                                Text(
                                  '${_total.toStringAsFixed(3)} $kCurrencySymbol',
                                  style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 12),
                        Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
                          child: SizedBox(
                            width: double.infinity,
                            height: 52,
                            child: FilledButton.icon(
                              onPressed: (_saving || _hasInvalid) ? null : _save,
                              icon: _saving
                                  ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.5, color: Colors.white))
                                  : const Icon(Icons.save_rounded, size: 22),
                              label: Text(
                                _saving ? 'جارٍ الحفظ...' : 'حفظ فاتورة الشراء',
                                style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                                elevation: 0,
                              ),
                            ),
                          ),
                        ),
                      ],
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemCard(ThemeData theme, _CartItem item, int index) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 8,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 44, height: 44,
                    decoration: BoxDecoration(
                      color: Colors.indigo.shade50,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Center(
                      child: Text(
                        item.productName.isNotEmpty ? item.productName[0].toUpperCase() : '?',
                        style: TextStyle(fontWeight: FontWeight.bold, color: Colors.indigo.shade700, fontSize: 16),
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.productName, style: theme.textTheme.bodyLarge?.copyWith(fontWeight: FontWeight.w600)),
                        const SizedBox(height: 2),
                        Text(
                          item.stockLabel,
                          style: TextStyle(fontSize: 12, color: theme.colorScheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    width: 32, height: 32,
                    decoration: BoxDecoration(
                      color: Colors.red.shade50,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      icon: Icon(Icons.delete_outline, size: 18, color: Colors.red.shade400),
                      onPressed: () {
                        item.dispose();
                        setState(() => _items.removeAt(index));
                      },
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: item.qtyCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      decoration: InputDecoration(
                        labelText: item.qtyLabel,
                        labelStyle: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                        ),
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
                        labelText: 'سعر الشروة كلها',
                        labelStyle: TextStyle(fontSize: 13, color: theme.colorScheme.onSurfaceVariant),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: theme.colorScheme.primary, width: 1.5),
                        ),
                      ),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 90,
                    child: TextField(
                      controller: item.unitPriceCtrl,
                      keyboardType: const TextInputType.numberWithOptions(decimal: true),
                      textAlign: TextAlign.center,
                      decoration: InputDecoration(
                        labelText: item.unitPriceLabel,
                        labelStyle: TextStyle(fontSize: 11, color: Colors.amber.shade700),
                        isDense: true,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.amber.shade200),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(10),
                          borderSide: BorderSide(color: Colors.amber.shade500, width: 1.5),
                        ),
                        filled: true,
                        fillColor: Colors.amber.shade50,
                      ),
                      style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: Colors.amber.shade800),
                      onChanged: (_) => setState(() {}),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: theme.colorScheme.surfaceContainerLowest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  children: [
                    const Spacer(),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(4),
                      ),
                      child: Text(
                        item.avgLabel,
                        style: TextStyle(fontSize: 10, color: Colors.green.shade700),
                      ),
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

class _StatItem extends StatelessWidget {
  final String label;
  final String value;
  final IconData icon;
  final Color color;

  const _StatItem({
    required this.label,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Column(
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(height: 2),
          Text(value,
            style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: color),
            textAlign: TextAlign.center,
          ),
          Text(label,
            style: TextStyle(fontSize: 10, color: color.withValues(alpha: 0.7)),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
