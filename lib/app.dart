import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'features/launcher_screen.dart';
import 'shared/home_shell.dart';
import 'shared/theme.dart';
import 'state/providers.dart';

class JuiceApp extends ConsumerWidget {
  const JuiceApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final oracle = ref.watch(oracleProvider);
    final textScale = ref.watch(textScaleProvider).valueOrNull ?? 1.0;
    return MaterialApp(
      title: "Solo Adventurer's Journal",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
      // Reading-size setting: multiplies the platform text scale so the OS
      // accessibility setting still applies underneath.
      builder: (context, child) {
        if (textScale == 1.0 || child == null) return child ?? const SizedBox();
        final mq = MediaQuery.of(context);
        return MediaQuery(
          data: mq.copyWith(
              textScaler: TextScaler.linear(mq.textScaler.scale(textScale))),
          child: child,
        );
      },
      home: oracle.when(
        loading: () => const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
        error: (e, _) => Scaffold(
          body: Center(child: Text('Failed to load oracle data:\n$e')),
        ),
        data: (o) => ref.watch(launcherGateProvider)
            ? const LauncherScreen()
            : HomeShell(oracle: o),
      ),
    );
  }
}
