import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/shared/campaign_preview_pane.dart';

void main() {
  testWidgets('renders verb headers and an on row', (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CampaignPreviewPane(
            systems: {'cairn', 'juice', 'party'},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('campaign-preview')), findsOneWidget);
    expect(find.text('Sheet'), findsOneWidget);
    expect(find.text('Cairn sheet'), findsOneWidget);
  });

  testWidgets('summary count reflects active surfaces', (tester) async {
    tester.view.physicalSize = const Size(500, 1600);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: CampaignPreviewPane(
            systems: {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('campaign-preview-count')), findsOneWidget);
  });
}
