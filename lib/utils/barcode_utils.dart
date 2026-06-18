import 'package:mobile_scanner/mobile_scanner.dart';

bool isProductBarcode(BarcodeFormat? format) {
  if (format == null) return false;
  switch (format) {
    case BarcodeFormat.ean13:
    case BarcodeFormat.ean8:
    case BarcodeFormat.upcA:
    case BarcodeFormat.upcE:
    case BarcodeFormat.code128:
    case BarcodeFormat.code39:
    case BarcodeFormat.code93:
    case BarcodeFormat.itf:
      return true;
    default:
      return false;
  }
}
