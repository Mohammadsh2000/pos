import 'dart:convert';
import 'package:pdf/pdf.dart' as pdf_lib;
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models/sale_item.dart';

Future<void> generateInvoicePdf(Map<String, dynamic> sale) async {
  final items = (jsonDecode(sale['items']) as List)
      .map((e) => SaleItem.fromMap(e as Map<String, dynamic>))
      .toList();
  final date = DateTime.parse(sale['created_at'] as String);
  final pdf = pw.Document();
  pdf.addPage(
    pw.MultiPage(
      pageFormat: pdf_lib.PdfPageFormat.roll80,
      margin: const pw.EdgeInsets.all(16),
      build: (pw.Context ctx) {
        return [
          pw.Center(
            child: pw.Text(
              kStoreName,
              style: pw.TextStyle(fontSize: 20, fontWeight: pw.FontWeight.bold),
            ),
          ),
          pw.SizedBox(height: 6),
          pw.Center(
            child: pw.Text('فاتورة مبيعات', style: pw.TextStyle(fontSize: 14)),
          ),
          pw.SizedBox(height: 4),
          pw.Center(
            child: pw.Text(
              DateFormat('yyyy/MM/dd HH:mm:ss').format(date),
              style: pw.TextStyle(fontSize: 10),
            ),
          ),
          pw.SizedBox(height: 2),
          pw.Center(
            child: pw.Text('#${sale['id']}', style: pw.TextStyle(fontSize: 10)),
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('المنتج', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('الكمية', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text('المجموع', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
            ],
          ),
          pw.Divider(),
          ...items.map(
            (i) => pw.Padding(
              padding: const pw.EdgeInsets.symmetric(vertical: 2),
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text(i.productName, style: pw.TextStyle(fontSize: 10)),
                  pw.Text(i.isKg ? i.quantity.toStringAsFixed(2) : i.quantity.toInt().toString(), style: pw.TextStyle(fontSize: 10)),
                  pw.Text(i.subtotal.toStringAsFixed(2), style: pw.TextStyle(fontSize: 10)),
                ],
              ),
            ),
          ),
          pw.Divider(),
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            children: [
              pw.Text('المجموع الكلي:', style: pw.TextStyle(fontWeight: pw.FontWeight.bold)),
              pw.Text(
                '${sale['total']} $kCurrencySymbol',
                style: pw.TextStyle(fontWeight: pw.FontWeight.bold),
              ),
            ],
          ),
          pw.SizedBox(height: 20),
          pw.Center(
            child: pw.Text('شكراً لتسوقكم معنا', style: pw.TextStyle(fontSize: 10)),
          ),
        ];
      },
    ),
  );
  await Printing.sharePdf(
    bytes: await pdf.save(),
    filename: 'فاتورة_${sale['id']}.pdf',
  );
}
