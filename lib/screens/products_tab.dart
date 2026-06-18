import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../constants.dart';
import '../providers/pos_provider.dart';
import '../widgets/product_form_sheet.dart';
import '../widgets/stock_in_sheet.dart';
import '../utils/notifications.dart';
import 'purchase_history_screen.dart';

class ProductsTab extends StatefulWidget {
  const ProductsTab({super.key});

  @override
  State<ProductsTab> createState() => _ProductsTabState();
}

class _ProductsTabState extends State<ProductsTab> {
  final _searchCtrl = TextEditingController();
  Timer? _debounce;

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

  void _openPurchaseHistory() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => const PurchaseHistoryScreen()),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Consumer<POSProvider>(
      builder: (context, p, _) {
        final products = p.products;
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
                      onPressed: _openPurchaseHistory,
                      icon: const Icon(Icons.history, size: 20),
                      style: IconButton.styleFrom(
                        backgroundColor: theme.colorScheme.surfaceContainerLow,
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                      ),
                    ),
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
                            'أضف منتجاً جديداً باستخدام الزر أعلاه',
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
                            : prod.stock.toStringAsFixed(0);
                        final hasBarcode = prod.barcode.isNotEmpty;
                        final hasPurchasePrice = prod.purchasePrice > 0;
                        final profit = prod.price - prod.purchasePrice;

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
                                              prod.isKg ? 'كجم' : 'عدد',
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
