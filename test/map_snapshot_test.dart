import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/features/map_snapshot.dart';

void main() {
  testWidgets('captureBoundaryPng returns PNG bytes for a painted boundary',
      (tester) async {
    final key = GlobalKey();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Center(
          child: RepaintBoundary(
            key: key,
            child: Container(
                width: 40, height: 40, color: const Color(0xFFFF0000)),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    Uint8List? png;
    await tester.runAsync(() async {
      png = await captureBoundaryPng(key);
    });
    expect(png, isNotNull);
    // PNG magic header: 0x89 'P' 'N' 'G'.
    expect(png!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  testWidgets('captureBoundaryPng returns null for an unmounted key',
      (tester) async {
    final key = GlobalKey();
    Uint8List? png = Uint8List(0);
    await tester.runAsync(() async {
      png = await captureBoundaryPng(key);
    });
    expect(png, isNull);
  });
}
