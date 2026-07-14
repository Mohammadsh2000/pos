import 'dart:convert';
import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart' as pdf_lib;
import 'package:pdf/widgets.dart' as pw;
import 'package:intl/intl.dart';
import '../constants.dart';
import '../models/sale_item.dart';

pw.Font? _cairo;
pw.Font? _cairoBold;

Future<void> _ensureFonts() async {
  if (_cairo != null) return;
  final d = await rootBundle.load('assets/fonts/Cairo.ttf');
  _cairo = pw.Font.ttf(d);
  _cairoBold = pw.Font.ttf(d);
}

const _rtl = pw.TextDirection.rtl;

_SaleData _parse(Map<String, dynamic> sale) {
  final items = (jsonDecode(sale['items']) as List)
      .map((e) => SaleItem.fromMap(e as Map<String, dynamic>))
      .toList();
  return _SaleData(
    items: items,
    date: DateTime.parse(sale['created_at'] as String),
    id: sale['id'] as int,
    total: sale['total'] as num,
    discount: (sale['discount'] as num?)?.toDouble() ?? 0,
    customer: sale['customer_name'] as String?,
  );
}

class _SaleData {
  final List<SaleItem> items;
  final DateTime date;
  final int id;
  final num total;
  final double discount;
  final String? customer;
  const _SaleData({
    required this.items,
    required this.date,
    required this.id,
    required this.total,
    this.discount = 0,
    this.customer,
  });
}

String _f(num v) => v.toStringAsFixed(2);

String _fmtQty(SaleItem i) {
  if (i.isCarton) return '${i.quantity.toInt()} كرتونة';
  if (i.isKg) return '${i.quantity.toStringAsFixed(2)} كجم';
  return i.quantity == i.quantity.roundToDouble()
      ? '${i.quantity.toInt()}'
      : i.quantity.toStringAsFixed(2);
}

String _trunc(String s, int max) =>
    s.length > max ? '${s.substring(0, max - 1)}…' : s;

Future<Uint8List> buildInvoicePdf(
    Map<String, dynamic> sale, {
      pdf_lib.PdfPageFormat? format,
      double scale = 1.0,
    }) async {
  await _ensureFonts();
  final d = _parse(sale);
  final hasCustomer = d.customer != null && d.customer!.trim().isNotEmpty;

  final pf = (format ?? pdf_lib.PdfPageFormat.roll80).copyWith(
    marginTop: 0, marginBottom: 0, marginLeft: 0, marginRight: 0,
  );
  final sf = pdf_lib.PdfPageFormat(pf.width, 600 * scale);

  // ── أنماط النصوص ──
  pw.TextStyle r(double s, [bool bold = false]) =>
      pw.TextStyle(font: bold ? _cairoBold : _cairo, fontSize: s * scale);
  pw.TextStyle muted(double s) =>
      r(s).copyWith(color: pdf_lib.PdfColors.grey600);
  pw.TextStyle white(double s, [bool bold = false]) =>
      r(s, bold).copyWith(color: pdf_lib.PdfColors.white);

  // ── فاصل ──
  pw.Widget divider({bool thick = false, pdf_lib.PdfColor? color}) =>
      pw.Divider(
        height: (thick ? 3 : 1) * scale,
        thickness: (thick ? 1 : 0.5) * scale,
        color: color ?? pdf_lib.PdfColors.grey300,
      );

  // ── الهيدر ──
  pw.Widget head() {
    return pw.Column(
      crossAxisAlignment: pw.CrossAxisAlignment.center,
      children: [
        // اسم المتجر
        pw.Container(
          width: double.infinity,
          padding: pw.EdgeInsets.symmetric(vertical: 4 * scale),
          decoration: pw.BoxDecoration(
            color: pdf_lib.PdfColors.grey100,
            borderRadius: pw.BorderRadius.circular(6 * scale),
          ),
          child: pw.Column(
            children: [
              pw.Text(
                kStoreName,
                textDirection: _rtl,
                style: r(18, true),
                textAlign: pw.TextAlign.center,
              ),
              if (kStoreAddress.isNotEmpty) ...[
                pw.SizedBox(height: 2 * scale),
                pw.Text(
                  kStoreAddress,
                  textDirection: _rtl,
                  style: muted(7.5),
                  textAlign: pw.TextAlign.center,
                ),
              ],
              if (kStorePhone.isNotEmpty)
                pw.Text(
                  kStorePhone,
                  textDirection: _rtl,
                  style: white(7.5).copyWith(color: pdf_lib.PdfColors.grey300),
                  textAlign: pw.TextAlign.center,
                ),
            ],
          ),
        ),

        pw.SizedBox(height: 2 * scale),

        // عنوان الفاتورة
        pw.Text(
          'فاتورة مبيعات',
          textDirection: _rtl,
          style: muted(9),
          textAlign: pw.TextAlign.center,
        ),

        pw.SizedBox(height: 2 * scale),

        // رقم + تاريخ + وقت
        pw.Container(
          padding: pw.EdgeInsets.symmetric(
            horizontal: 8 * scale, vertical: 3 * scale,
          ),
          child: pw.Directionality(
            textDirection: _rtl,
            child: pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text(
                  '#${DateFormat('yyyyMMdd').format(d.date)}-${d.id}',
                  style: r(8, true),
                ),
                pw.Text(
                  DateFormat('yyyy/MM/dd').format(d.date),
                  style: muted(8),
                ),
                pw.Text(
                  DateFormat('HH:mm').format(d.date),
                  style: muted(8),
                ),
              ],
            ),
          ),
        ),

        // العميل
        if (hasCustomer) ...[
          pw.SizedBox(height: 2 * scale),
          pw.Container(
            width: double.infinity,
            padding: pw.EdgeInsets.symmetric(
              horizontal: 8 * scale, vertical: 3 * scale,
            ),
            decoration: pw.BoxDecoration(
              border: pw.Border.all(
                color: pdf_lib.PdfColors.grey300,
                width: 0.5 * scale,
              ),
              borderRadius: pw.BorderRadius.circular(4 * scale),
            ),
            child: pw.Directionality(
              textDirection: _rtl,
              child: pw.Row(
                children: [
                  pw.Text('العميل: ', style: muted(9)),
                  pw.Text(d.customer!, style: r(9, true)),
                ],
              ),
            ),
          ),
        ],
      ],
    );
  }

  // ── رأس الجدول ──
  pw.Widget tblHead() {
    pw.Widget col(String t, {int flex = 2, pw.TextAlign align = pw.TextAlign.center}) =>
        pw.Expanded(
          flex: flex,
          child: pw.Text(
            t,
            textDirection: _rtl,
            textAlign: align,
            style: white(8.5, true),
          ),
        );

    return pw.Container(
      padding: pw.EdgeInsets.symmetric(
        vertical: 4 * scale, horizontal: 6 * scale,
      ),
      decoration: pw.BoxDecoration(
        color: pdf_lib.PdfColors.grey900,
        borderRadius: pw.BorderRadius.circular(4 * scale),
      ),
      child: pw.Directionality(
        textDirection: _rtl,
        child: pw.Row(children: [
          col('الصنف', flex: 4, align: pw.TextAlign.right),
          col('الكمية'),
          col('السعر'),
          col('المجموع'),
        ]),
      ),
    );
  }

  // ── صف منتج ──
  pw.Widget tblRow(SaleItem i, bool isOdd) {
    pw.Widget cell(String t, {int flex = 2, pw.TextAlign align = pw.TextAlign.center, bool bold = false}) =>
        pw.Expanded(
          flex: flex,
          child: pw.Text(
            t,
            textDirection: _rtl,
            textAlign: align,
            style: bold ? r(9, true) : muted(9),
          ),
        );

    final priceText = i.discountPercent > 0
        ? '${_f(i.discountedPrice)} (-${i.discountPercent.toInt()}%)'
        : _f(i.price);

    return pw.Container(
      padding: pw.EdgeInsets.symmetric(
        vertical: 3 * scale, horizontal: 6 * scale,
      ),
      color: isOdd ? pdf_lib.PdfColors.grey50 : pdf_lib.PdfColors.white,
      child: pw.Directionality(
        textDirection: _rtl,
        child: pw.Row(
          crossAxisAlignment: pw.CrossAxisAlignment.center,
          children: [
            cell(_trunc(i.productName, 22),
                flex: 4, align: pw.TextAlign.right, bold: true),
            cell(_fmtQty(i)),
            cell(priceText),
            cell(_f(i.subtotal), bold: true),
          ],
        ),
      ),
    );
  }

  // ── الإجمالي ──
  pw.Widget totalSection() {
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: pdf_lib.PdfColors.grey300, width: 0.5 * scale),
        borderRadius: pw.BorderRadius.circular(6 * scale),
      ),
      child: pw.Column(
        children: [
          // عدد الأصناف
          pw.Container(
            padding: pw.EdgeInsets.symmetric(
              horizontal: 10 * scale, vertical: 3 * scale,
            ),
            child: pw.Directionality(
              textDirection: _rtl,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('عدد الأصناف', style: muted(9)),
                  pw.Text('${d.items.length}', style: r(9, true)),
                ],
              ),
            ),
          ),

          // فاصل
          pw.Container(
            height: 0.5 * scale,
            color: pdf_lib.PdfColors.grey300,
          ),

          // الخصم (إذا موجود)
          if (d.discount > 0) ...[
            pw.Container(
              padding: pw.EdgeInsets.symmetric(
                horizontal: 10 * scale, vertical: 3 * scale,
              ),
              child: pw.Directionality(
                textDirection: _rtl,
                child: pw.Row(
                  mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                  children: [
                    pw.Text('الخصم:', style: muted(9).copyWith(color: pdf_lib.PdfColors.red700)),
                    pw.Text(
                      '- ${_f(d.discount)} $kCurrencySymbol',
                      style: r(9, true).copyWith(color: pdf_lib.PdfColors.red700),
                    ),
                  ],
                ),
              ),
            ),
            pw.Container(
              height: 0.5 * scale,
              color: pdf_lib.PdfColors.grey300,
            ),
          ],

          // المجموع الكلي
          pw.Container(
            padding: pw.EdgeInsets.symmetric(
              horizontal: 10 * scale, vertical: 4 * scale,
            ),
            decoration: pw.BoxDecoration(
              color: pdf_lib.PdfColors.grey100,
              borderRadius: pw.BorderRadius.only(
                bottomLeft: pw.Radius.circular(5 * scale),
                bottomRight: pw.Radius.circular(5 * scale),
              ),
            ),
            child: pw.Directionality(
              textDirection: _rtl,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                children: [
                  pw.Text('المجموع الكلي', style: r(11, true)),
                  pw.Text(
                    '${_f(d.total.toDouble())} $kCurrencySymbol',
                    textDirection: _rtl,
                    style: r(14, true),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── الباركود ──
  pw.Widget bcode() {
    final c = d.id.toString().padLeft(8, '0');
    return pw.Center(
      child: pw.BarcodeWidget(
        barcode: pw.Barcode.code128(),
        data: c,
        width: 160 * scale,
        height: 20 * scale,
        drawText: false,
      ),
    );
  }

  // ── الفوتر ──
  pw.Widget foot() {
    return pw.Column(
      children: [
        // خط متقطع
        pw.Row(
          children: List.generate(
            40,
                (i) => pw.Expanded(
              child: pw.Container(
                height: 0.5 * scale,
                color: i.isEven ? pdf_lib.PdfColors.grey400 : pdf_lib.PdfColors.white,
              ),
            ),
          ),
        ),

        pw.SizedBox(height: 2 * scale),

        pw.Text(
          'شكراً لتسوقكم معنا',
          style: r(10, true).copyWith(color: pdf_lib.PdfColors.grey800),
          textDirection: _rtl,
          textAlign: pw.TextAlign.center,
        ),

        if (kStoreFooter.isNotEmpty) ...[
          pw.SizedBox(height: 2 * scale),
          pw.Text(
            kStoreFooter,
            style: muted(8),
            textDirection: _rtl,
            textAlign: pw.TextAlign.center,
          ),
        ],

        pw.SizedBox(height: 2 * scale),
        pw.Text(
          'نظام نقاط البيع',
          style: muted(7),
          textDirection: _rtl,
          textAlign: pw.TextAlign.center,
        ),
        pw.SizedBox(height: 2 * scale),
      ],
    );
  }

  // ── بناء الصفحة ──
  final pdf = pw.Document();
  pdf.addPage(
    pw.Page(
      pageFormat: sf,
      build: (_) => pw.DefaultTextStyle(
        style: r(10),
        child: pw.Padding(
          padding: pw.EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 2 * scale),
          child: pw.Column(
            crossAxisAlignment: pw.CrossAxisAlignment.stretch,
            children: [
              head(),
              pw.SizedBox(height: 3 * scale),
              tblHead(),
              // صفوف المنتجات متعاقبة
              ...d.items.asMap().entries.map(
                    (e) => tblRow(e.value, e.key.isOdd),
              ),
              divider(thick: true),
              pw.SizedBox(height: 2 * scale),
              totalSection(),
              pw.SizedBox(height: 3 * scale),
              bcode(),
              pw.SizedBox(height: 3 * scale),
              foot(),
            ],
          ),
        ),
      ),
    ),
  );

  return pdf.save();
}

String buildInvoiceText(Map<String, dynamic> sale) {
  final d = _parse(sale);
  final hasCustomer = d.customer != null && d.customer!.trim().isNotEmpty;
  const w = 34;
  String pr(String s) => s.padLeft(8);
  String pl(String s) => s.padRight(16);
  String pc(String s) => ' ' * ((w - s.length) ~/ 2) + s;

  final b = StringBuffer();
  b.writeln('━' * w);
  b.writeln(pc(kStoreName));
  b.writeln(pc('فاتورة مبيعات'));
  b.writeln('━' * w);
  if (kStoreAddress.isNotEmpty) b.writeln(kStoreAddress);
  if (kStorePhone.isNotEmpty) b.writeln(kStorePhone);
  b.writeln('─' * w);
  b.writeln('التاريخ: ${DateFormat('yyyy/MM/dd').format(d.date)}');
  b.writeln('الوقت:   ${DateFormat('HH:mm:ss').format(d.date)}');
  b.writeln('الرقم:   #${DateFormat('yyyyMMdd').format(d.date)}-${d.id}');
  if (hasCustomer) b.writeln('العميل:  ${d.customer}');
  b.writeln('─' * w);
  b.writeln('${pl('الصنف')}  ${'الكمية'.padLeft(6)} ${pr('السعر')} ${pr('المجموع')}');
  b.writeln('─' * w);
  for (final i in d.items) {
    final priceStr = i.discountPercent > 0
        ? '${_f(i.discountedPrice)}*'
        : _f(i.price);
    b.writeln(
      '${pl(_trunc(i.productName, 16))}  ${_fmtQty(i).padLeft(6)} ${pr(priceStr)} ${pr(_f(i.subtotal))}',
    );
  }
  if (d.items.any((i) => i.discountPercent > 0)) {
    b.writeln('─' * w);
    for (final i in d.items.where((i) => i.discountPercent > 0)) {
      b.writeln('* ${_trunc(i.productName, 16)} خصم ${i.discountPercent.toInt()}%');
    }
  }
  b.writeln('─' * w);
  b.writeln('${'عدد الأصناف:'.padLeft(16)} ${d.items.length.toString().padLeft(6)}');
  if (d.discount > 0) {
    b.writeln('${'الخصم:'.padLeft(20)} ${pr('${_f(d.discount)} $kCurrencySymbol')}');
  }
  b.writeln('━' * w);
  b.writeln(
    '${'المجموع الكلي:'.padLeft(20)} ${pr('${_f(d.total)} $kCurrencySymbol')}',
  );
  b.writeln('━' * w);
  b.writeln(pc('شكراً لتسوقكم معنا'));
  b.writeln(pc(kStoreFooter));
  b.writeln(pc('نظام نقاط البيع'));
  b.writeln('─' * w);
  return b.toString();
}