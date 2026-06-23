import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/blob_store.dart';
import '../state/providers.dart';
import 'sketch_editor.dart';

/// Captures [key]'s RenderRepaintBoundary as PNG bytes (the full painted area
/// at [pixelRatio]). Null when the boundary isn't mounted/painted yet.
Future<Uint8List?> captureBoundaryPng(GlobalKey key,
    {double pixelRatio = 2.0}) async {
  final obj = key.currentContext?.findRenderObject();
  if (obj is! RenderRepaintBoundary) return null;
  final image = await obj.toImage(pixelRatio: pixelRatio);
  try {
    final bd = await image.toByteData(format: ui.ImageByteFormat.png);
    return bd?.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

void _snack(BuildContext context, String msg) {
  ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
}

/// Snapshots the map under [boundaryKey] into a new journal sketch the player
/// can annotate. No-op when the blob store is unavailable (web). Mirrors the
/// tail of journal_screen `_annotatePdf`.
Future<void> snapshotMapToJournal(
    BuildContext context, WidgetRef ref, GlobalKey boundaryKey) async {
  if (!ref.read(blobStoreAvailableProvider)) return;
  final png = await captureBoundaryPng(boundaryKey);
  if (png == null) {
    if (context.mounted) _snack(context, 'Could not capture the map.');
    return;
  }
  final bgBlobId = await ref.read(blobStoreProvider).put(png, ext: 'png');
  // A cancelled editor leaves an orphan blob; blob GC is a later epic step.
  final bg = await decodeSketchBackground(png);
  try {
    if (!context.mounted) return;
    final data = await showSketchEditor(context,
        background: bg, backgroundBlobId: bgBlobId);
    if (data != null && !data.isEmpty) {
      await ref.read(journalProvider.notifier).addSketch(data);
      if (context.mounted) _snack(context, 'Saved to journal.');
    }
  } finally {
    bg?.dispose();
  }
}
