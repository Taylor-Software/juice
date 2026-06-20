import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_riverpod/flutter_riverpod.dart';

// Platform impl: pdfrx (pdfium) on mobile/desktop, an unavailable stub on web
// (so the pdfrx package is never imported into the web build). Mirrors
// blob_store's conditional import.
import 'pdf_rasterizer_io.dart'
    if (dart.library.html) 'pdf_rasterizer_web.dart' as platform;

/// Renders pages of a user-imported PDF to raster bytes. Behind an interface so
/// tests never touch the native/WASM pdfium engine (the InterpreterService
/// pattern). See `docs/superpowers/specs/2026-06-19-pdf-annotation-pdfrx-design.md`.
abstract class PdfRasterizer {
  Future<int> pageCount(Uint8List pdfBytes);

  /// Render the 0-based [pageIndex] to PNG bytes ~[targetWidth] px wide,
  /// preserving aspect. Returns null on failure / out-of-range / unsupported.
  Future<Uint8List?> renderPage(Uint8List pdfBytes, int pageIndex,
      {int targetWidth = 1500});
}

final pdfRasterizerProvider =
    Provider<PdfRasterizer>((ref) => platform.createPdfRasterizer());

/// Whether PDF import is available on this platform. Desktop/mobile-first: false
/// on web for now (pdfium WASM wiring is a later step); web can still VIEW
/// imported-PDF annotations via the cached page raster.
final pdfAvailableProvider = Provider<bool>((ref) => !kIsWeb);
