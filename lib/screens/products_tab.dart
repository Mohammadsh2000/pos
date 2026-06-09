import 'dart:async';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../models/product.dart';
import '../providers/pos_provider.dart';
import '../widgets/product_form_sheet.dart';

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
      builder: (_) => ProductFormSheet(product: product),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Selector<POSProvider, List<Product>>(
      selector: (_, p) => p.products,
      builder: (context, products, _) {
        return Column(
          children: [
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _searchCtrl,
                      decoration: const InputDecoration(
                        hintText: 'بحث...',
                        prefixIcon: Icon(Icons.search),
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                      onChanged: _onSearchChanged,
                    ),
                  ),
                  const SizedBox(width: 8),
                  FilledButton.icon(
                    onPressed: () => _showForm(),
                    icon: const Icon(Icons.add),
                    label: const Text('إضافة'),
                  ),
                ],
              ),
            ),
            Expanded(
              child: products.isEmpty
                  ? Center(
                      child: Text(
                        'لا توجد منتجات',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                              color: Theme.of(context).colorScheme.outline,
                            ),
                      ),
                    )
                  : ListView.builder(
                      itemCount: products.length,
                      itemBuilder: (context, i) {
                        final prod = products[i];
                        return Card(
                          margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
                          child: ListTile(
                            title: Text(prod.name),
                            subtitle: Text(
                              '${prod.price.toStringAsFixed(2)} ر.س | المخزون: ${prod.stock} | ${prod.category}',
                            ),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.edit_outlined),
                                  onPressed: () => _showForm(product: prod),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete_outline, color: Colors.red),
                                  onPressed: () async {
                                    final ctx = context;
                                    final messenger = ScaffoldMessenger.of(ctx);
                                    final provider = ctx.read<POSProvider>();
                                    final ok = await showDialog<bool>(
                                      context: ctx,
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
                                      final err = await provider.deleteProduct(prod.id!);
                                      if (err != null) {
                                        messenger.showSnackBar(SnackBar(content: Text(err)));
                                      }
                                    }
                                  },
                                ),
                              ],
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
