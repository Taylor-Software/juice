import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/sketch.dart';
import '../state/blob_store.dart';
import '../state/providers.dart';
import 'sketch_editor.dart';

/// Opens a sketch journal entry in the editor (resolving its blob background)
/// and persists edits back onto the entry. Shared by the journal's sketch
/// cards and the map's hex "Open map" chip.
Future<void> openSketchEntry(
    BuildContext context, WidgetRef ref, JournalEntry e) async {
  final data = SketchData.fromJson(
      (e.payload?['sketch'] as Map?)?.cast<String, dynamic>() ?? const {});
  final id = data.backgroundBlobId;
  ui.Image? bg;
  if (id != null && ref.read(blobStoreAvailableProvider)) {
    bg =
        await decodeSketchBackground(await ref.read(blobStoreProvider).get(id));
  }
  try {
    if (!context.mounted) return;
    final edited = await showSketchEditor(context,
        initial: data,
        background: bg,
        backgroundBlobId: id,
        pdfBlobId: data.pdfBlobId,
        pdfPage: data.pdfPage);
    if (edited != null) {
      await ref
          .read(journalProvider.notifier)
          .replace(e.copyWith(payload: {'v': 1, 'sketch': edited.toJson()}));
    }
  } finally {
    // We own the decoded image; release it after the editor's exit
    // transition (disposing inline races the pop animation).
    disposeSketchBackgroundLater(bg);
  }
}
