import 'dart:async';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

import 'pdf_rasterizer.dart';

PdfRasterizer createPdfRasterizer() => PdfrxRasterizer();

/// Real implementation backed by pdfrx (pdfium native). Thin glue; not
/// unit-tested (needs native) — verified on device.
class PdfrxRasterizer implements PdfRasterizer {
  @override
  Future<int> pageCount(Uint8List pdfBytes) async {
    await pdfrxFlutterInitialize();
    final doc = await PdfDocument.openData(pdfBytes);
    try {
      return doc.pages.length;
    } finally {
      await doc.dispose();
    }
  }

  @override
  Future<Uint8List?> renderPage(Uint8List pdfBytes, int pageIndex,
      {int targetWidth = 1500}) async {
    await pdfrxFlutterInitialize();
    PdfDocument? doc;
    try {
      doc = await PdfDocument.openData(pdfBytes);
      if (pageIndex < 0 || pageIndex >= doc.pages.length) return null;
      final page = doc.pages[pageIndex];
      final w = targetWidth;
      final h = (targetWidth * page.height / page.width).round();
      final img = await page.render(
        width: w,
        height: h,
        fullWidth: w.toDouble(),
        fullHeight: h.toDouble(),
      );
      if (img == null) return null;
      try {
        final uiImage = await _toUiImage(img.pixels, img.width, img.height);
        try {
          final bd = await uiImage.toByteData(format: ui.ImageByteFormat.png);
          return bd?.buffer.asUint8List();
        } finally {
          uiImage.dispose();
        }
      } finally {
        img.dispose();
      }
    } catch (_) {
      return null; // unsupported / corrupt PDF
    } finally {
      await doc?.dispose();
    }
  }

  // pdfrx pixels are BGRA8888.
  Future<ui.Image> _toUiImage(Uint8List bgra, int w, int h) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromPixels(
        bgra, w, h, ui.PixelFormat.bgra8888, completer.complete);
    return completer.future;
  }
}
