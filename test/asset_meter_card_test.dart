import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/features/sheet_widgets.dart';

void main() {
  testWidgets('assetCard renders a meter stepper and reports changes',
      (tester) async {
    String? changedKey;
    int? changedVal;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(children: [
          assetCard(
            prefix: 'sf',
            index: 0,
            asset: const AssetState(
              assetId: 'sf/assets/companion/banshee',
              name: 'Banshee',
              category: 'Companion',
              meters: [
                AssetMeter(
                    key: 'health', label: 'health', min: 0, max: 4, value: 2)
              ],
            ),
            onAbilitiesChanged: (_) {},
            onDelete: () {},
            onMeterChanged: (k, v) {
              changedKey = k;
              changedVal = v;
            },
          ),
        ]),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Health'), findsOneWidget); // title-cased label
    expect(find.text('2 / 4'), findsOneWidget);

    await tester.tap(find.byKey(const Key('sf-asset-0-meter-health-plus')));
    expect(changedKey, 'health');
    expect(changedVal, 3);

    await tester.tap(find.byKey(const Key('sf-asset-0-meter-health-minus')));
    expect(changedVal, 1);
  });

  testWidgets('an asset with no meters renders no meter steppers',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: assetCard(
          prefix: 'iw',
          index: 0,
          asset: const AssetState(assetId: 'x', name: 'Swordmaster'),
          onAbilitiesChanged: (_) {},
          onDelete: () {},
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.remove_circle_outline), findsNothing);
  });
}
