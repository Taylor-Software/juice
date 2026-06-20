import 'dart:typed_data';

import 'pdf_rasterizer.dart';

PdfRasterizer createPdfRasterizer() => _UnavailablePdfRasterizer();

/// Web stub: PDF rasterization is unavailable (pdfium WASM wiring is a later
/// epic step), so PDF import is hidden via [pdfAvailableProvider]. Imports no
/// pdfrx, keeping it out of the web build entirely.
class _UnavailablePdfRasterizer implements PdfRasterizer {
  @override
  Future<int> pageCount(Uint8List pdfBytes) async => 0;

  @override
  Future<Uint8List?> renderPage(Uint8List pdfBytes, int pageIndex,
          {int targetWidth = 1500}) async =>
      null;
}
