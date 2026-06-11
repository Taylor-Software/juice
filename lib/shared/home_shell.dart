import 'package:flutter/material.dart';

import '../engine/oracle.dart';
import '../features/fate_screen.dart';
import '../features/generators_screen.dart';
import '../features/tables_screen.dart';
import '../features/tracker_screen.dart';

class HomeShell extends StatefulWidget {
  const HomeShell({super.key, required this.oracle});
  final Oracle oracle;

  @override
  State<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends State<HomeShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    final pages = [
      FateScreen(oracle: widget.oracle),
      GeneratorsScreen(oracle: widget.oracle),
      TablesScreen(oracle: widget.oracle),
      const TrackerScreen(),
    ];
    return Scaffold(
      appBar: AppBar(title: const Text('Juice Oracle')),
      body: SafeArea(
        child: IndexedStack(index: _index, children: pages),
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(
              icon: Icon(Icons.help_outline), label: 'Fate'),
          NavigationDestination(
              icon: Icon(Icons.auto_awesome_outlined), label: 'Generators'),
          NavigationDestination(
              icon: Icon(Icons.grid_view_outlined), label: 'Tables'),
          NavigationDestination(
              icon: Icon(Icons.bookmarks_outlined), label: 'Tracker'),
        ],
      ),
    );
  }
}
