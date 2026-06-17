import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

/// Guards the real shipped asset data against the Dart parser: the bespoke
/// Ironsworn sheet's picker (lib/features/ironsworn_sheet.dart) reads exactly
/// this `asset_collections` block at runtime. If build_datasworn.py changes the
/// emitted shape, this fails. Plain dart:io read — NOT rootBundle, so no hang.
void main() {
  test('real ruleset_classic.json parses into 78 well-formed asset defs', () {
    final raw = File('assets/ruleset_classic.json').readAsStringSync();
    final data = jsonDecode(raw) as Map<String, dynamic>;

    final defs = IronswornAssetDef.listFromRuleset(data);
    expect(defs.length, 78,
        reason: 'classic has 78 assets across 4 categories');

    for (final d in defs) {
      expect(d.id, isNotEmpty);
      expect(d.name, isNotEmpty);
      expect(d.abilityEnabled.length, d.abilities.length,
          reason: 'one enabled-flag per ability');
      final st = d.toState();
      expect(st.assetId, d.id);
      expect(st.enabledAbilities.length, d.abilities.length);
    }

    // Every Classic asset category is represented.
    final cats = defs.map((d) => d.category).toSet();
    expect(cats,
        containsAll(<String>['Combat Talent', 'Companion', 'Path', 'Ritual']));

    // Abilities carry real text (the picker shows toggles for them).
    final withAbilities = defs.where((d) => d.abilities.isNotEmpty).toList();
    expect(withAbilities, isNotEmpty);
    expect(
        withAbilities.first.abilities.any((t) => t.trim().isNotEmpty), isTrue);
  });

  test('real ruleset_starforged.json parses into 87 well-formed asset defs',
      () {
    final raw = File('assets/ruleset_starforged.json').readAsStringSync();
    final data = jsonDecode(raw) as Map<String, dynamic>;
    final defs = IronswornAssetDef.listFromRuleset(data);
    expect(defs.length, 87,
        reason: 'starforged has 87 assets across 6 categories');
    for (final d in defs) {
      expect(d.id, isNotEmpty);
      expect(d.name, isNotEmpty);
      expect(d.abilityEnabled.length, d.abilities.length);
    }
    final cats = defs.map((d) => d.category).toSet();
    expect(cats, containsAll(<String>['Path', 'Module', 'Companion', 'Deed']));
  });
}
