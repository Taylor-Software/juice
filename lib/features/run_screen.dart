import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

/// The live GM run-screen: a read-and-act dashboard composing initiative,
/// party HP, the active scene, and quick dice/oracle over existing providers.
class RunScreen extends ConsumerWidget {
  const RunScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return const Center(key: Key('run-screen'), child: Text('Run'));
  }
}
