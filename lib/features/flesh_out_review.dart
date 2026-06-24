import 'package:flutter/material.dart';

/// Append/Cancel review for an AI-generated flesh-out. Returns true on Append.
/// Shared by the map (room/hex), scenes, and any future flesh-out surface.
Future<bool> showFleshOutReview(BuildContext context, String generated) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => AlertDialog(
      key: const Key('flesh-out-review'),
      title: const Text('Flesh out'),
      content: SingleChildScrollView(child: Text(generated)),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel')),
        FilledButton(
          key: const Key('flesh-out-append'),
          onPressed: () => Navigator.pop(context, true),
          child: const Text('Append'),
        ),
      ],
    ),
  );
  return ok ?? false;
}
