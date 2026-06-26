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
    return MaterialApp(
      title: "Loreseer",
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light(),
      darkTheme: AppTheme.dark(),
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
