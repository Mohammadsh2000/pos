import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:printing/printing.dart';
import 'package:pdf/pdf.dart';
import 'package:path_provider/path_provider.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models/sale_item.dart';
import '../utils/invoice_pdf.dart';
import '../utils/notifications.dart';

class InvoicePreviewScreen extends StatelessWidget {
  final Map<String, dynamic> sale;

  const InvoicePreviewScreen({super.key, required this.sale});

  @override
  Widget build(BuildContext context) {
    final items = (jsonDecode(sale['items'] as String) as List)
        .map((e) => SaleItem.fromMap(e as Map<String, dynamic>))
        .toList();
    final date = DateTime.parse(sale['created_at'] as String);
    final id = sale['id'] as int;
    final total = (sale['total'] as num).toDouble();
    final discount = (sale['discount'] as num?)?.toDouble() ?? 0;
    final customer = sale['customer_name'] as String?;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: Text('فاتورة #$id'),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.download_rounded),
            tooltip: 'حفظ في الملفات',
            onPressed: () async {
              final bytes = await buildInvoicePdf(sale, scale: 4.0);
              final dir = await getTemporaryDirectory();
              final path = '${dir.path}/فاتورة_$id.pdf';
              await File(path).writeAsBytes(bytes);
              if (!context.mounted) return;
              showSuccessNotification(context, 'تم حفظ الفاتورة بخط كبير في: $path', duration: const Duration(seconds: 5));
            },
          ),
          IconButton(
            icon: const Icon(Icons.copy_rounded),
            tooltip: 'نسخ النص',
            onPressed: () {
              final text = buildInvoiceText(sale);
              Clipboard.setData(ClipboardData(text: text));
              showSuccessNotification(context, 'تم نسخ الفاتورة - يمكنك لصقها في واتساب أو أي تطبيق آخر');
            },
          ),
          IconButton(
            icon: const Icon(Icons.print),
            tooltip: 'طباعة',
            onPressed: () async {
              final bytes = await buildInvoicePdf(sale, format: PdfPageFormat.roll80, scale: 1.0);
              await Printing.sharePdf(bytes: bytes, filename: 'فاتورة_$id.pdf');
            },
          ),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 400),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(context, customer),
                const SizedBox(height: 16),
                _buildInvoiceInfo(context, id, date),
                const SizedBox(height: 16),
                _buildItemsTable(context, items),
                const SizedBox(height: 16),
                _buildTotalSection(context, items.length, total, discount),
                const SizedBox(height: 24),
                _buildBarcode(id),
                const SizedBox(height: 16),
                _buildFooter(context),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeader(BuildContext context, String? customer) {
    final theme = Theme.of(context);
    return Column(
      children: [
        Text(kStoreName, style: theme.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.bold)),
        if (kStoreAddress.isNotEmpty) Text(kStoreAddress, style: theme.textTheme.bodySmall),
        if (kStorePhone.isNotEmpty) Text(kStorePhone, style: theme.textTheme.bodySmall),
        const SizedBox(height: 8),
        Text('فاتورة مبيعات', style: theme.textTheme.titleMedium?.copyWith(color: Colors.grey)),
      ],
    );
  }

  Widget _buildInvoiceInfo(BuildContext context, int id, DateTime date) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('#${DateFormat('yyyyMMdd').format(date)}-$id',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
          Text(DateFormat('yyyy/MM/dd').format(date), style: const TextStyle(fontSize: 13)),
          Text(DateFormat('HH:mm').format(date), style: const TextStyle(fontSize: 13)),
        ],
      ),
    );
  }

  Widget _buildItemsTable(BuildContext context, List<SaleItem> items) {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
          decoration: BoxDecoration(
            color: Colors.grey[900],
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(
            textDirection: ui.TextDirection.rtl,
            children: [
              const Expanded(flex: 4, child: Text('الصنف', style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              const Expanded(flex: 2, child: Text('الكمية', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              const Expanded(flex: 2, child: Text('السعر', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
              const Expanded(flex: 2, child: Text('المجموع', textAlign: TextAlign.center, style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold))),
            ],
          ),
        ),
        ...List.generate(items.length, (i) {
          final item = items[i];
          final isOdd = i.isOdd;
          return Container(
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
            color: isOdd ? Colors.grey[50] : Colors.white,
            child: Row(
              textDirection: ui.TextDirection.rtl,
              children: [
                Expanded(flex: 4, child: Text(item.productName, style: const TextStyle(fontWeight: FontWeight.w600))),
                Expanded(flex: 2, child: Text(
                  item.isCarton ? '${item.quantity.toInt()} كرتونة' : (item.isKg ? '${item.quantity.toStringAsFixed(2)} كجم' : '${item.quantity.toInt()}'),
                  textAlign: TextAlign.center,
                )),
                Expanded(flex: 2, child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (item.discountPercent > 0) ...[
                      Text(
                        item.price.toStringAsFixed(2),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.grey[400],
                          decoration: TextDecoration.lineThrough,
                          fontSize: 11,
                        ),
                      ),
                      Text(
                        item.discountedPrice.toStringAsFixed(2),
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.orange[700],
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                    ] else
                      Text(
                        item.price.toStringAsFixed(2),
                        textAlign: TextAlign.center,
                        style: TextStyle(color: Colors.grey[700]),
                      ),
                  ],
                )),
                Expanded(flex: 2, child: Text(
                  item.subtotal.toStringAsFixed(2),
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                )),
              ],
            ),
          );
        }),
      ],
    );
  }

  Widget _buildTotalSection(BuildContext context, int itemCount, double total, [double discount = 0]) {
    return Container(
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey[300]!),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('عدد الأصناف', style: TextStyle(color: Colors.grey[600])),
                Text('$itemCount', style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey[300]),
          if (discount > 0) ...[
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text('الخصم', style: TextStyle(color: Colors.red[700])),
                  Text(
                    '- ${discount.toStringAsFixed(2)} $kCurrencySymbol',
                    style: TextStyle(color: Colors.red[700], fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
            Divider(height: 1, color: Colors.grey[300]),
          ],
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: Colors.grey[100],
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(8),
                bottomRight: Radius.circular(8),
              ),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text('المجموع الكلي', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold)),
                Text('${total.toStringAsFixed(2)} $kCurrencySymbol',
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.bold)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildBarcode(int id) {
    return Center(
      child: Text('#${id.toString().padLeft(8, '0')}',
          style: const TextStyle(letterSpacing: 4, fontWeight: FontWeight.bold)),
    );
  }

  Widget _buildFooter(BuildContext context) {
    return Column(
      children: [
        Row(
          children: List.generate(
            40,
            (i) => Expanded(
              child: Container(height: 1, color: i.isEven ? Colors.grey[400] : Colors.white),
            ),
          ),
        ),
        const SizedBox(height: 8),
        Text('شكراً لتسوقكم معنا', style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold)),
        if (kStoreFooter.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(kStoreFooter, style: TextStyle(color: Colors.grey[600], fontSize: 13)),
        ],
        const SizedBox(height: 4),
        Text('نظام نقاط البيع', style: TextStyle(color: Colors.grey[500], fontSize: 11)),
      ],
    );
  }
}
