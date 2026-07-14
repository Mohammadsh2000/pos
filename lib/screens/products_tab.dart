import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../widgets/product_form_sheet.dart';
import '../widgets/stock_in_sheet.dart';
import '../widgets/barcode_label_dialog.dart';
import '../widgets/stock_adjustment_sheet.dart';
import '../utils/barcode_generator.dart';
import '../utils/notifications.dart';

enum _StockFilter { all, lowStock, outOfStock, inStock }

const _stockFilterLabels = {
  _StockFilter.all: 'الكل',
  _StockFilter.lowStock: 'منخفض (<5)',
  _StockFilter.outOfStock: 'نفد (0)',
  _StockFilter.inStock: 'متوفر',
};

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

  String? _filterCategory;
  String? _filterSaleType;
  _StockFilter _stockFilter = _StockFilter.all;
  bool _discountOnly = false;

  @override
  void dispose() {
    _debounce?.cancel();
    _searchCtrl.dispose();
    super.dispose();
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (!mounted) return;
      context.read<POSProvider>().searchProducts(v);
    });
  }

  List<Product> _filtered(List<Product> products) {
    var result = products.toList();

    if (_filterCategory != null) {
      result = result.where((p) => p.category == _filterCategory).toList();
    }

    if (_filterSaleType != null) {
      result = result.where((p) => p.saleType == _filterSaleType).toList();
    }

    switch (_stockFilter) {
      case _StockFilter.lowStock:
        result = result.where((p) => p.stock < 5).toList();
        break;
      case _StockFilter.outOfStock:
        result = result.where((p) => p.stock <= 0).toList();
        break;
      case _StockFilter.inStock:
        result = result.where((p) => p.stock > 0).toList();
        break;
      case _StockFilter.all:
        break;
    }

    if (_discountOnly) {
      result = result.where((p) => p.discountPercent > 0).toList();
    }

    return result;
  }

  int _activeFilterCount() {
    int n = 0;
    if (_filterCategory != null) n++;
    if (_filterSaleType != null) n++;
    if (_stockFilter != _StockFilter.all) n++;
    if (_discountOnly) n++;
    return n;
  }

  void _clearFilters() {
    setState(() {
      _filterCategory = null;
      _filterSaleType = null;
      _stockFilter = _StockFilter.all;
      _discountOnly = false;
    });
  }

  void _showFilterSheet() {
    String? tempCategory = _filterCategory;
    String? tempSaleType = _filterSaleType;
    _StockFilter tempStock = _stockFilter;
    bool tempDiscount = _discountOnly;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        final theme = Theme.of(ctx);
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 20, right: 20, top: 12,
              bottom: MediaQuery.of(context).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                Text('تصفية المخزون', style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
                const SizedBox(height: 20),
                Text('النوع', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [null, ...kCategories].map((cat) {
                    final selected = tempCategory == cat;
                    return ChoiceChip(
                      label: Text(cat ?? 'الكل'),
                      selected: selected,
                      onSelected: (_) => setSheetState(() => tempCategory = cat),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                Text('الوحدة', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: [
                    _buildSaleTypeChip('الكل', null, tempSaleType, setSheetState),
                    _buildSaleTypeChip('عدد', 'unit', tempSaleType, setSheetState),
                    _buildSaleTypeChip('كجم', 'kg', tempSaleType, setSheetState),
                    _buildSaleTypeChip('كرتونة', 'carton', tempSaleType, setSheetState),
                  ],
                ),
                const SizedBox(height: 20),
                Text('المخزون', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w600)),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  children: _StockFilter.values.map((s) {
                    final selected = tempStock == s;
                    return ChoiceChip(
                      label: Text(_stockFilterLabels[s]!),
                      selected: selected,
                      onSelected: (_) => setSheetState(() => tempStock = s),
                    );
                  }).toList(),
                ),
                const SizedBox(height: 20),
                SwitchListTile(
                  title: const Text('المنتجات المخفضة فقط'),
                  value: tempDiscount,
                  onChanged: (v) => setSheetState(() => tempDiscount = v),
                  contentPadding: EdgeInsets.zero,
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () {
                          setSheetState(() {
                            tempCategory = null;
                            tempSaleType = null;
                            tempStock = _StockFilter.all;
                            tempDiscount = false;
                          });
                        },
                        style: OutlinedButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('إعادة تعيين'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: () {
                          setState(() {
                            _filterCategory = tempCategory;
                            _filterSaleType = tempSaleType;
                            _stockFilter = tempStock;
                            _discountOnly = tempDiscount;
                          });
                          Navigator.pop(ctx);
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size.fromHeight(48),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text('تطبيق التصفية'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSaleTypeChip(String label, String? value, String? current, void Function(VoidCallback) setSheetState) {
    final selected = current == value;
    return ChoiceChip(
      label: Text(label),
      selected: selected,
      onSelected: (_) => setSheetState(() => current = value),
    );
  }

  void _showForm({Product? product}) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => ProductFormSheet(product: product),
    );
  }

  Future<void> _openStockIn() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const StockInSheet(),
    );
  }

  Future<void> _openStockAdjustment() async {
    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) => const StockAdjustmentSheet(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final filterCount = _activeFilterCount();
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        final allProducts = p.products;
        final products = _filtered(allProducts);
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 12, 4),
              child: SizedBox(
                height: 44,
                child: TextField(
                  controller: _searchCtrl,
                  decoration: InputDecoration(
                    hintText: 'بحث عن منتج...',
                    hintStyle: TextStyle(color: theme.colorScheme.onSurfaceVariant, fontSize: 14),
                    prefixIcon: Icon(Icons.search, size: 20, color: theme.colorScheme.onSurfaceVariant),
                    suffixIcon: _searchCtrl.text.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear, size: 18),
                            onPressed: () {
                              _searchCtrl.clear();
                              _onSearchChanged('');
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: theme.colorScheme.surfaceContainerLowest,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(vertical: 10),
                  ),
                  onChanged: _onSearchChanged,
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
              child: Row(
                children: [
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: FilledButton.icon(
                        onPressed: () => _showForm(),
                        icon: const Icon(Icons.add, size: 20),
                        label: const Text('إضافة'),
                        style: FilledButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                  Expanded(
                    child: SizedBox(
                      height: 44,
                      child: OutlinedButton.icon(
                        onPressed: _openStockIn,
                        icon: const Icon(Icons.receipt_long, size: 20),
                        label: const Text('شراء'),
                        style: OutlinedButton.styleFrom(
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 44,
                    width: 44,
                    child: IconButton(
                      onPressed: _openStockAdjustment,
                      icon: const Icon(Icons.balance, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: Colors.orange.shade50,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
                  ),
                  const SizedBox(width: 4),
                  SizedBox(
                    height: 44,
                    width: 44,
                    child: Badge(
                      isLabelVisible: filterCount > 0,
                      label: Text('$filterCount'),
                      child: IconButton(
                        onPressed: _showFilterSheet,
                        icon: Icon(
                          Icons.tune,
                          color: filterCount > 0
                              ? theme.colorScheme.primary
                              : theme.colorScheme.onSurfaceVariant,
                        ),
                        style: IconButton.styleFrom(
                          backgroundColor: filterCount > 0
                              ? theme.colorScheme.primaryContainer
                              : theme.colorScheme.surfaceContainerLow,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              child: Row(
                children: [
                  Text(
                    'المخزون: ${allProducts.length} منتج',
                    style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  if (products.length != allProducts.length)
                    Text(
                      ' • عرض ${products.length}',
                      style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.primary),
                    ),
                  const Spacer(),
                  if (filterCount > 0 || _searchCtrl.text.isNotEmpty)
                    TextButton.icon(
                      onPressed: () {
                        _clearFilters();
                        _searchCtrl.clear();
                        _onSearchChanged('');
                      },
                      style: TextButton.styleFrom(
                        padding: const EdgeInsets.symmetric(horizontal: 8),
                        minimumSize: Size.zero,
                        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      ),
                      icon: const Icon(Icons.close, size: 14),
                      label: const Text('مسح الكل', style: TextStyle(fontSize: 12)),
                    ),
                ],
              ),
            ),
            Expanded(
              child: products.isEmpty
                  ? Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.inventory_2_outlined, size: 64, color: theme.colorScheme.outlineVariant),
                          const SizedBox(height: 8),
                          Text(
                            'لا توجد منتجات',
                            style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.outline),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            allProducts.isEmpty
                                ? 'أضف منتجاً جديداً باستخدام الزر أعلاه'
                                : 'حاول تغيير معايير التصفية',
                            style: theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.outline),
                          ),
                        ],
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      itemCount: products.length,
                      itemBuilder: (context, i) {
                        final prod = products[i];
                        final isLowStock = prod.stock < 5;
                        final stockText = prod.isKg
                            ? prod.stock.toStringAsFixed(2)
                            : (prod.isCarton && prod.piecesPerCarton > 0
                                ? ((){
                                    final cartons = prod.stock ~/ prod.piecesPerCarton;
                                    final rem = (prod.stock % prod.piecesPerCarton).toInt();
                                    final buf = StringBuffer('$cartons كرتونة');
                                    if (rem > 0) buf.write(' + $rem قطعة');
                                    return buf.toString();
                                  })()
                                : prod.stock.toStringAsFixed(0));
                        final hasBarcode = prod.barcode.isNotEmpty;
                        final hasPurchasePrice = prod.purchasePrice > 0;
                        final profit = prod.cartonProfitMargin;

                        return Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Card(
                            margin: EdgeInsets.zero,
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14),
                              side: BorderSide(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5)),
                            ),
                            color: Colors.white,
                            clipBehavior: Clip.antiAlias,
                            child: Padding(
                              padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.center,
                                children: [
                                  Container(
                                    width: 42, height: 42,
                                    decoration: BoxDecoration(
                                      color: theme.colorScheme.primaryContainer.withValues(alpha: 0.5),
                                      borderRadius: BorderRadius.circular(10),
                                    ),
                                    child: Center(
                                      child: Text(
                                        prod.name.isNotEmpty ? prod.name[0] : '?',
                                        style: theme.textTheme.titleMedium?.copyWith(
                                          fontWeight: FontWeight.w800,
                                          color: theme.colorScheme.onPrimaryContainer,
                                        ),
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          prod.name,
                                          style: theme.textTheme.bodyLarge?.copyWith(
                                            fontWeight: FontWeight.w700,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                        const SizedBox(height: 3),
                                        Row(
                                          children: [
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: theme.colorScheme.tertiaryContainer.withValues(alpha: 0.4),
                                                borderRadius: BorderRadius.circular(4),
                                              ),
                                              child: Text(
                                                prod.category,
                                                style: theme.textTheme.labelSmall?.copyWith(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.w600,
                                                  color: theme.colorScheme.onTertiaryContainer,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(width: 5),
                                            Text(
                                              prod.isCarton
                                                  ? 'كرتونة'
                                                  : (prod.isKg
                                                      ? 'كجم'
                                                      : (prod.hasCartonSale ? 'عدد/كرتونة' : 'عدد')),
                                              style: theme.textTheme.labelSmall?.copyWith(
                                                fontSize: 10,
                                                color: theme.colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                            if (hasBarcode) ...[
                                              const SizedBox(width: 5),
                                              Icon(Icons.qr_code, size: 10, color: theme.colorScheme.onSurfaceVariant),
                                              const SizedBox(width: 2),
                                              Flexible(
                                                child: Text(
                                                  prod.barcode,
                                                  style: theme.textTheme.labelSmall?.copyWith(
                                                    fontSize: 9,
                                                    color: theme.colorScheme.onSurfaceVariant,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      if (prod.discountPercent > 0) ...[
                                        Text(
                                          '${prod.price.toStringAsFixed(2)} $kCurrencySymbol',
                                          style: theme.textTheme.bodySmall?.copyWith(
                                            decoration: TextDecoration.lineThrough,
                                            color: Colors.grey,
                                          ),
                                        ),
                                        Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Text(
                                              '${prod.discountedPrice.toStringAsFixed(2)} $kCurrencySymbol',
                                              style: theme.textTheme.titleSmall?.copyWith(
                                                fontWeight: FontWeight.w900,
                                                color: Colors.orange.shade700,
                                              ),
                                            ),
                                            const SizedBox(width: 4),
                                            Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
                                              decoration: BoxDecoration(
                                                color: Colors.red.shade50,
                                                borderRadius: BorderRadius.circular(4),
                                                border: Border.all(color: Colors.red.shade200),
                                              ),
                                              child: Text(
                                                '-${prod.discountPercent.toInt()}%',
                                                style: TextStyle(fontSize: 10, color: Colors.red[700], fontWeight: FontWeight.bold),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ] else
                                        Text(
                                          '${prod.price.toStringAsFixed(2)} $kCurrencySymbol',
                                          style: theme.textTheme.titleSmall?.copyWith(
                                            fontWeight: FontWeight.w900,
                                            color: theme.colorScheme.onSurface,
                                          ),
                                        ),
                                      const SizedBox(height: 3),
                                      Container(
                                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                        decoration: BoxDecoration(
                                          color: isLowStock ? Colors.red.shade50 : Colors.green.shade50,
                                          borderRadius: BorderRadius.circular(5),
                                        ),
                                        child: Row(
                                          mainAxisSize: MainAxisSize.min,
                                          children: [
                                            Icon(
                                              isLowStock ? Icons.inventory : Icons.check_circle,
                                              size: 11,
                                              color: isLowStock ? Colors.red.shade600 : Colors.green.shade600,
                                            ),
                                            const SizedBox(width: 3),
                                            Text(
                                              stockText,
                                              style: TextStyle(
                                                fontSize: 11,
                                                fontWeight: FontWeight.w700,
                                                color: isLowStock ? Colors.red.shade700 : Colors.green.shade700,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      if (prod.hasCartonSale) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'كرتونة: ${prod.cartonDiscountedPrice.toStringAsFixed(2)} $kCurrencySymbol',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            fontSize: 10,
                                            color: theme.colorScheme.onSurfaceVariant,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                      if (hasPurchasePrice) ...[
                                        const SizedBox(height: 2),
                                        Text(
                                          'ربح ${profit.toStringAsFixed(2)}',
                                          style: theme.textTheme.labelSmall?.copyWith(
                                            fontSize: 10,
                                            color: profit > 0 ? Colors.green.shade600 : Colors.red.shade400,
                                            fontWeight: FontWeight.w600,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(width: 6),
                                  Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      SizedBox(
                                        width: 30, height: 30,
                                        child: IconButton(
                                          onPressed: () => _showForm(product: prod),
                                          icon: Icon(Icons.edit_outlined, size: 15, color: theme.colorScheme.onSurfaceVariant),
                                          style: IconButton.styleFrom(
                                            backgroundColor: theme.colorScheme.surfaceContainerLow,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                                            padding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ),
                                      if (BarcodeGenerator.isGeneratedBarcode(prod.barcode)) ...[
                                        const SizedBox(height: 4),
                                        SizedBox(
                                          width: 30, height: 30,
                                          child: IconButton(
                                            onPressed: () {
                                              showDialog(
                                                context: context,
                                                builder: (_) => BarcodeLabelDialog(product: prod),
                                              );
                                            },
                                            icon: Icon(Icons.qr_code_2, size: 15, color: theme.colorScheme.primary),
                                            style: IconButton.styleFrom(
                                              backgroundColor: theme.colorScheme.primaryContainer.withValues(alpha: 0.3),
                                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                                              padding: EdgeInsets.zero,
                                            ),
                                          ),
                                        ),
                                      ],
                                      const SizedBox(height: 4),
                                      SizedBox(
                                        width: 30, height: 30,
                                        child: IconButton(
                                          onPressed: () async {
                                            final ok = await showDialog<bool>(
                                              context: context,
                                              builder: (ctx2) => AlertDialog(
                                                title: const Text('حذف المنتج'),
                                                content: Text('حذف "${prod.name}"؟'),
                                                actions: [
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx2, false),
                                                    child: const Text('إلغاء'),
                                                  ),
                                                  TextButton(
                                                    onPressed: () => Navigator.pop(ctx2, true),
                                                    child: const Text('حذف'),
                                                  ),
                                                ],
                                              ),
                                            );
                                            if (ok == true) {
                                              final err = await p.deleteProduct(prod.id!);
                                              if (!context.mounted) return;
                                              if (err != null) {
                                                showTopNotification(context, err);
                                              }
                                            }
                                          },
                                          icon: Icon(Icons.delete_outline, size: 15, color: Colors.red.shade400),
                                          style: IconButton.styleFrom(
                                            backgroundColor: Colors.red.shade50,
                                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(7)),
                                            padding: EdgeInsets.zero,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      },
                    ),
            ),
          ],
        );
      },
    );
  }
}
