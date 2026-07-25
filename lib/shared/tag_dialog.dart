import 'package:flutter/material.dart';

/// Prompts for one free-text tag and returns it trimmed, or null when the user
/// cancelled or left the field blank.
///
/// Callers keep their own dedupe check — the collection differs (journal entry
/// tags, roster character tags, encounter combatant statuses) but the prompt
/// does not: [title], [label] and [fieldKey] are the only things that ever
/// varied between the three copies this replaced.
///
/// Case is preserved deliberately: search compares case-insensitively, so the
/// tag should read back the way the player typed it.
Future<String?> promptForTag(
  BuildContext context, {
  required String title,
  required String label,
  required String fieldKey,
}) async {
  final ctrl = TextEditingController();
  final result = await showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        key: Key(fieldKey),
        controller: ctrl,
        autofocus: true,
        decoration: InputDecoration(labelText: label),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, ctrl.text),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  // Dispose after the frame: the dialog's EditableText still holds the
  // controller while the route animates out.
  WidgetsBinding.instance.addPostFrameCallback((_) => ctrl.dispose());
  final tag = result?.trim() ?? '';
  return tag.isEmpty ? null : tag;
}
