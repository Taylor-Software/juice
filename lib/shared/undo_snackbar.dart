// lib/shared/undo_snackbar.dart
import 'package:flutter/material.dart';

/// Shows the standard delete-undo snackbar: [message] plus an Undo action
/// that runs [onUndo]. Every user-facing destructive delete routes through
/// this instead of a confirm dialog — deleting stays one tap, and a mis-tap
/// is recoverable for a few seconds.
void showUndoSnackbar(
  BuildContext context,
  String message,
  Future<void> Function() onUndo,
) {
  ScaffoldMessenger.of(context)
    ..hideCurrentSnackBar()
    ..showSnackBar(SnackBar(
      content: Text(message),
      duration: const Duration(seconds: 5),
      action: SnackBarAction(label: 'Undo', onPressed: () => onUndo()),
    ));
}
