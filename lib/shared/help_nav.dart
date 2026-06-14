import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../features/help_screen.dart';
import '../state/providers.dart';

/// Opens Help as a route (Help has no tab home). Optional [topic] preselects a
/// help page via [helpTopicProvider].
void openHelp(BuildContext context, WidgetRef ref, {String? topic}) {
  if (topic != null) ref.read(helpTopicProvider.notifier).state = topic;
  Navigator.of(context).push(
    MaterialPageRoute<void>(builder: (_) => const HelpScreen()),
  );
}
