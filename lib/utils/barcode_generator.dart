import 'dart:io';

import 'package:flutter/services.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

import '../constants.dart';
import '../models/product.dart';

pw.Font? _cairo;
pw.Font? _cairoBold;

Future<void> _ensureFonts() async {
  if (_cairo != null) return;
  final d = await rootBundle.load('assets/fonts/Cairo.ttf');
  _cairo = pw.Font.ttf(d);
  _cairoBold = pw.Font.ttf(d);
}

class BarcodeGenerator {
  BarcodeGenerator._();

  static const _generatedPrefix = '2';

  static bool isGeneratedBarcode(String barcode) {
    return barcode.startsWith(_generatedPrefix) && barcode.length == 13;
  }

  static String generateUniqueCode() {
    final now = DateTime.now();
    final ts = now.millisecondsSinceEpoch.toString();
    final suffix = ts.length >= 12 ? ts.substring(ts.length - 12) : ts.padLeft(12, '0');
    return '$_generatedPrefix$suffix';
  }

  static pw.Widget _buildLabelContent(Product product, pw.Font font, pw.Font bold, double scale) {
    final s = scale;
    return pw.Container(
      decoration: pw.BoxDecoration(
        border: pw.Border.all(color: PdfColors.grey400, width: (0.5 * s).clamp(0.2, 0.5)),
      ),
      padding: pw.EdgeInsets.all(8 * s),
      child: pw.Column(
        crossAxisAlignment: pw.CrossAxisAlignment.center,
        mainAxisAlignment: pw.MainAxisAlignment.center,
        children: [
          pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
            crossAxisAlignment: pw.CrossAxisAlignment.center,
            children: [
              pw.Flexible(
                fit: pw.FlexFit.loose,
                child: pw.Text(
                  kStoreName,
                  style: pw.TextStyle(fontSize: 22 * s, fontWeight: pw.FontWeight.bold, font: bold),
                  textDirection: pw.TextDirection.rtl,
                  maxLines: 2,
                ),
              ),
              pw.SizedBox(width: 4 * s),
              pw.Text(
                '$kCurrencySymbol ${product.price.toStringAsFixed(2)} ',
                style: pw.TextStyle(fontSize: 26 * s, fontWeight: pw.FontWeight.bold, font: bold),
              ),
            ],
          ),
          pw.SizedBox(height: 4 * s),
          pw.Align(
            alignment: pw.Alignment.centerRight,
            child: pw.Text(
              product.name,
              style: pw.TextStyle(fontSize: 18 * s, fontWeight: pw.FontWeight.bold, font: bold),
              textDirection: pw.TextDirection.rtl,
              maxLines: 2,
            ),
          ),
          pw.SizedBox(height: 6 * s),
          pw.SizedBox(
            width: 284 * s,
            height: 55 * s,
            child: pw.BarcodeWidget(
              barcode: pw.Barcode.code128(),
              data: product.barcode,
              width: 284 * s,
              height: 55 * s,
              drawText: false,
            ),
          ),
          pw.SizedBox(height: 2 * s),
          pw.Center(
            child: pw.Text(
              product.barcode,
              style: pw.TextStyle(fontSize: 22 * s, letterSpacing: 1.5 * s, font: font),
            ),
          ),
          if (product.isKg)
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                'سعر الكيلو',
                style: pw.TextStyle(fontSize: 11 * s, font: font),
              ),
            )
          else if (product.isCarton || product.hasCartonSale)
            pw.Align(
              alignment: pw.Alignment.centerLeft,
              child: pw.Text(
                product.isCarton ? 'سعر الكرتونة' : 'كرتونة: ${product.cartonPrice.toStringAsFixed(2)}',
                style: pw.TextStyle(fontSize: 11 * s, font: font),
              ),
            ),
        ],
      ),
    );
  }

  static Future<Uint8List> generateLabelPdf(Product product) async {
    await _ensureFonts();
    final font = _cairo!;
    final bold = _cairoBold!;
    final pdf = pw.Document();

    pdf.addPage(pw.Page(
      pageFormat: const PdfPageFormat(300, 150),
      margin: pw.EdgeInsets.zero,
      build: (ctx) => _buildLabelContent(product, font, bold, 1),
    ));

    return await pdf.save();
  }

  static Future<Uint8List> generateMultiLabelPdf(Product product, {int columns = 6, int rows = 12, double gap = 4}) async {
    await _ensureFonts();
    final font = _cairo!;
    final bold = _cairoBold!;
    final pdf = pw.Document();

    const margin = 0.0;
    const epsilon = 0.5;
    final page = PdfPageFormat.a4;
    final totalGapX = gap * (columns - 1);
    final totalGapY = gap * (rows - 1);
    final labelW = (page.width - 2 * margin - totalGapX) / columns;
    final labelH = (page.height - 2 * margin - totalGapY - epsilon) / rows;
    final scale = (labelW / 300) < (labelH / 150) ? (labelW / 300) : (labelH / 150);

    pdf.addPage(pw.Page(
      pageFormat: PdfPageFormat.a4,
      margin: pw.EdgeInsets.all(margin),
      build: (ctx) {
        final rowWidgets = <pw.Widget>[];
        for (int row = 0; row < rows; row++) {
          if (row > 0) rowWidgets.add(pw.SizedBox(height: gap));
          final colWidgets = <pw.Widget>[];
          for (int col = 0; col < columns; col++) {
            if (col > 0) colWidgets.add(pw.SizedBox(width: gap));
            colWidgets.add(pw.Container(
              width: labelW,
              height: labelH,
              decoration: pw.BoxDecoration(
                border: pw.Border.all(color: PdfColors.grey400, width: 0.3),
              ),
              child: pw.Center(
                child: _buildLabelContent(product, font, bold, scale),
              ),
            ));
          }
          rowWidgets.add(pw.Row(
            mainAxisAlignment: pw.MainAxisAlignment.start,
            crossAxisAlignment: pw.CrossAxisAlignment.start,
            children: colWidgets,
          ));
        }
        return pw.Column(
          mainAxisSize: pw.MainAxisSize.min,
          mainAxisAlignment: pw.MainAxisAlignment.start,
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: rowWidgets,
        );
      },
    ));
    return await pdf.save();
  }

  static Future<void> printLabel(Product product) async {
    final bytes = await generateLabelPdf(product);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static Future<void> printMultiLabel(Product product, {int columns = 6, int rows = 12, double gap = 4}) async {
    final bytes = await generateMultiLabelPdf(product, columns: columns, rows: rows, gap: gap);
    await Printing.layoutPdf(onLayout: (_) async => bytes);
  }

  static Future<String?> saveLabelToFile(Product product) async {
    final bytes = await generateLabelPdf(product);
    final fileName = '${product.name}_barcode.pdf'
        .replaceAll(RegExp(r'[\\/:*?"<>|]'), '_');

    try {
      final outputPath = await FilePicker.saveFile(
        dialogTitle: 'حفظ الباركود',
        fileName: fileName,
        bytes: bytes,
      );
      return outputPath;
    } catch (_) {
      final dir = await getApplicationDocumentsDirectory();
      final filePath = '${dir.path}/$fileName';
      await File(filePath).writeAsBytes(bytes);
      return filePath;
    }
  }
}
