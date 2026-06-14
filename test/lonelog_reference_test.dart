import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/lonelog_data.dart';
import 'package:juice_oracle/features/lonelog_reference_screen.dart';
import 'package:juice_oracle/state/providers.dart';

LonelogData _data() =>
    LonelogData(jsonDecode(File('assets/lonelog_data.json').readAsStringSync())
        as Map<String, dynamic>);

void main() {
  testWidgets('renders the legend sections and a highlighted example',
      (t) async {
    // Tall surface so the whole (lazy) ListView lays out its sections.
    await t.binding.setSurfaceSize(const Size(1000, 4000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(ProviderScope(
      overrides: [
        lonelogDataProvider.overrideWith((ref) async => _data()),
      ],
      child: const MaterialApp(home: Scaffold(body: LonelogReferenceScreen())),
    ));
    await t.pumpAndSettle();

    expect(find.text('Core symbols'), findsOneWidget);
    expect(find.text('Tags & references'), findsOneWidget);
    expect(find.text('Addons'), findsOneWidget);
    // A worked-example title and one of its highlighted lines render.
    expect(find.text('A complete beat'), findsOneWidget);
    // The example line is a multi-span RichText (highlighted); check its plain
    // text rather than find.textContaining (which won't traverse the spans).
    final richTexts = t.widgetList<RichText>(find.byType(RichText));
    expect(
        richTexts.any(
            (rt) => rt.text.toPlainText().contains('Pick the warehouse lock')),
        isTrue);
  });
}
