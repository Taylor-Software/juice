import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/play_context.dart';

JournalEntry _e(String id, String title, String body, String kind) =>
    JournalEntry.fromJson({
      'id': id,
      'timestamp': '2026-06-12T10:00:00.000',
      'title': title,
      'body': body,
      'kind': kind,
    });

void main() {
  test('fleshOutSeedFrom: name recall + newest scene + primer passthrough', () {
    // journal is newest-first
    final journal = [
      _e('3', 'Scene Two', 'A new place', 'scene'),
      _e('2', 'Vane speaks', 'Sister Vane warns the party', 'text'),
      _e('1', 'Scene One', 'The crypt', 'scene'),
    ];
    final seed = fleshOutSeedFrom(
      entityKind: 'NPC',
      name: 'Vane',
      existingDetail: 'grim',
      systemPrimer: 'Ironsworn',
      activeCharacter: 'Taurin (PC)',
      journal: journal,
    );
    expect(seed.entityKind, 'NPC');
    expect(seed.name, 'Vane');
    expect(seed.existingDetail, 'grim');
    expect(seed.systemPrimer, 'Ironsworn');
    expect(seed.activeCharacter, 'Taurin (PC)');
    expect(seed.sceneTitle, 'Scene Two'); // newest scene's title
    expect(seed.journalContext.any((l) => l.contains('Vane')), isTrue);
  });

  test('fleshOutSeedFrom: excludeId drops the subject entry from recall', () {
    // The scene IS a journal entry; its title is the name-query, so it would
    // self-match. excludeId keeps it out of recall (it's already `existing:`).
    final journal = [
      _e('s1', 'The Crypt', 'A damp vault.', 'scene'),
      _e('2', 'The Crypt revisited', 'Bones everywhere', 'text'),
    ];
    final seed = fleshOutSeedFrom(
      entityKind: 'scene',
      name: 'The Crypt',
      existingDetail: 'A damp vault.',
      systemPrimer: '',
      activeCharacter: '',
      journal: journal,
      excludeId: 's1',
    );
    expect(
        seed.journalContext.any((l) => l.contains('A damp vault.')), isFalse);
    expect(seed.journalContext.any((l) => l.contains('Bones everywhere')),
        isTrue); // the other matching entry still recalled
  });

  test('fleshOutSeedFrom: empty journal -> null scene + empty context', () {
    final seed = fleshOutSeedFrom(
      entityKind: 'location',
      name: 'Mill',
      existingDetail: '',
      systemPrimer: '',
      activeCharacter: '',
      journal: const [],
    );
    expect(seed.sceneTitle, isNull);
    expect(seed.journalContext, isEmpty);
  });
}
