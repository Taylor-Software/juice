import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/shared/home_shell.dart';

void main() {
  test('kSystemBlurbs describes every system', () {
    for (final id in {...kAllSystems, 'lonelog', 'hexcrawl'}) {
      expect(kSystemBlurbs[id], isNotNull, reason: id);
    }
  });

  testWidgets('returns name + systems + genre + tone', (t) async {
    ({String name, Set<String> systems, String genre, String tone})? out;
    await t.pumpWidget(MaterialApp(
      home: Builder(
        builder: (ctx) => Scaffold(
          body: Center(
            child: ElevatedButton(
              onPressed: () async => out = await showDialog<
                  ({
                    String name,
                    Set<String> systems,
                    String genre,
                    String tone
                  })>(
                context: ctx,
                builder: (_) => const NewCampaignDialog(),
              ),
              child: const Text('open'),
            ),
          ),
        ),
      ),
    ));
    await t.tap(find.text('open'));
    await t.pumpAndSettle();
    // System checkboxes carry their description as a subtitle.
    expect(find.text(kSystemBlurbs['juice']!), findsOneWidget);
    await t.enterText(find.byKey(const Key('new-campaign-name')), 'My');
    await t.enterText(find.byKey(const Key('new-campaign-genre')), 'grimdark');
    await t.enterText(find.byKey(const Key('new-campaign-tone')), 'tense');
    await t.tap(find.text('Create'));
    await t.pumpAndSettle();
    expect(out!.name, 'My');
    expect(out!.genre, 'grimdark');
    expect(out!.tone, 'tense');
    expect(out!.systems, contains('juice'));
  });
}
