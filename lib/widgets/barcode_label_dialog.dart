import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:pdf/widgets.dart' as pw;

import '../constants.dart';
import '../models/product.dart';
import '../utils/barcode_generator.dart';
import '../utils/notifications.dart';

class BarcodeLabelDialog extends StatefulWidget {
  final Product product;

  const BarcodeLabelDialog({super.key, required this.product});

  @override
  State<BarcodeLabelDialog> createState() => _BarcodeLabelDialogState();
}

class _BarcodeLabelDialogState extends State<BarcodeLabelDialog> {
  bool _saving = false;
  bool _printing = false;
  int _columns = 6;
  int _rows = 12;
  double _gap = 4;
  late final TextEditingController _columnsCtrl;
  late final TextEditingController _rowsCtrl;
  late final TextEditingController _gapCtrl;

  @override
  void initState() {
    super.initState();
    _columnsCtrl = TextEditingController(text: '$_columns');
    _rowsCtrl = TextEditingController(text: '$_rows');
    _gapCtrl = TextEditingController(text: '${_gap.toInt()}');
  }

  @override
  void dispose() {
    _columnsCtrl.dispose();
    _rowsCtrl.dispose();
    _gapCtrl.dispose();
    super.dispose();
  }

  void _updateColumns(String v) {
    final n = int.tryParse(v);
    if (n != null && n >= 1 && n <= 10) {
      setState(() => _columns = n);
    }
  }

  void _updateRows(String v) {
    final n = int.tryParse(v);
    if (n != null && n >= 1 && n <= 20) {
      setState(() => _rows = n);
    }
  }

  void _updateGap(String v) {
    final n = double.tryParse(v);
    if (n != null && n >= 0 && n <= 20) {
      setState(() => _gap = n);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final product = widget.product;

    return AlertDialog(
      title: Row(
        children: [
          Icon(Icons.qr_code_2, color: theme.colorScheme.primary, size: 24),
          const SizedBox(width: 8),
          const Text('طباعة الباركود'),
        ],
      ),
      content: SizedBox(
        width: double.maxFinite,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: theme.colorScheme.outlineVariant.withValues(alpha: 0.3)),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          kStoreName,
                          style: GoogleFonts.cairo(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ),
                      Text(
                        '${product.price.toStringAsFixed(2)} $kCurrencySymbol',
                        style: GoogleFonts.cairo(
                          fontSize: 22,
                          fontWeight: FontWeight.w900,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Align(
                    alignment: Alignment.centerRight,
                    child: Text(
                      product.name,
                      style: GoogleFonts.cairo(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: theme.colorScheme.onSurface,
                      ),
                      textDirection: TextDirection.rtl,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(height: 16),
                  CustomPaint(
                    size: const Size(280, 70),
                    painter: _BarcodePainter(product.barcode),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    product.barcode,
                    style: GoogleFonts.cairo(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: theme.colorScheme.onSurfaceVariant,
                      letterSpacing: 2,
                    ),
                  ),
                  if (product.isKg) ...[
                    const SizedBox(height: 4),
                    Text(
                      'سعر الكيلو',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ] else if (product.isCarton || product.hasCartonSale) ...[
                    const SizedBox(height: 4),
                    Text(
                      product.isCarton ? 'سعر الكرتونة' : 'كرتونة: ${product.cartonPrice.toStringAsFixed(2)}',
                      style: TextStyle(fontSize: 11, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 8),
            Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(width: 48, child: Center(child: Text('أعمدة', style: theme.textTheme.bodySmall))),
                    const SizedBox(width: 16),
                    SizedBox(width: 48, child: Center(child: Text('صفوف', style: theme.textTheme.bodySmall))),
                    const SizedBox(width: 12),
                    SizedBox(width: 40, child: Center(child: Text('فجوة', style: theme.textTheme.bodySmall))),
                    const SizedBox(width: 12),
                    const SizedBox(width: 30),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    SizedBox(
                      width: 48,
                      child: TextField(
                        controller: _columnsCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: _updateColumns,
                      ),
                    ),
                    const SizedBox(width: 16),
                    SizedBox(
                      width: 48,
                      child: TextField(
                        controller: _rowsCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: _updateRows,
                      ),
                    ),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 40,
                      child: TextField(
                        controller: _gapCtrl,
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                          contentPadding: EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                        onChanged: _updateGap,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Text('= ${_columns * _rows}', style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.bold, color: theme.colorScheme.primary)),
                  ],
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _saving ? null : _saveToFile,
                    icon: _saving
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.save_alt, size: 20),
                    label: const Text('حفظ في الملفات'),
                    style: OutlinedButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _printing ? null : _print,
                    icon: _printing
                        ? const SizedBox(
                            width: 18,
                            height: 18,
                            child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                          )
                        : const Icon(Icons.print, size: 20),
                    label: const Text('طباعة'),
                    style: FilledButton.styleFrom(
                      minimumSize: const Size.fromHeight(44),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('إلغاء'),
        ),
      ],
    );
  }

  Future<void> _saveToFile() async {
    setState(() => _saving = true);
    try {
      final path = await BarcodeGenerator.saveLabelToFile(widget.product);
      if (!mounted) return;
      setState(() => _saving = false);
      Navigator.pop(context);
      if (path != null) {
        showTopNotification(context, 'تم حفظ الباركود بنجاح');
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      showTopNotification(context, 'فشل الحفظ: $e');
    }
  }

  Future<void> _print() async {
    setState(() => _printing = true);
    try {
      Navigator.pop(context);
      await BarcodeGenerator.printMultiLabel(widget.product, columns: _columns, rows: _rows, gap: _gap);
    } catch (e) {
      if (!mounted) return;
      showTopNotification(context, 'فشلت الطباعة: $e');
    } finally {
      if (mounted) setState(() => _printing = false);
    }
  }
}

class _BarcodePainter extends CustomPainter {
  final String data;
  final double _drawW = 280;
  final double _drawH = 60;

  _BarcodePainter(this.data);

  @override
  void paint(Canvas canvas, Size size) {
    try {
      final bars = pw.Barcode.code128()
          .make(data, width: _drawW, height: _drawH, drawText: false)
          .whereType<pw.BarcodeBar>()
          .where((b) => b.black)
          .toList();
      if (bars.isEmpty) return;

      double maxX = 0;
      double maxY = 0;
      for (final b in bars) {
        if (b.right > maxX) maxX = b.right;
        if (b.bottom > maxY) maxY = b.bottom;
      }
      if (maxX == 0 || maxY == 0) return;

      final scaleX = size.width / maxX;
      final scaleY = size.height / maxY;
      final paint = Paint()..color = Colors.black;

      for (final b in bars) {
        canvas.drawRect(
          Rect.fromLTWH(
            b.left * scaleX,
            b.top * scaleY,
            b.width * scaleX,
            b.height * scaleY,
          ),
          paint,
        );
      }
    } catch (_) {}
  }

  @override
  bool shouldRepaint(covariant _BarcodePainter old) => data != old.data;
}