import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('Thread.pinned round-trips and defaults false', () {
    expect(Thread(id: 't', title: 'T').pinned, isFalse);
    final p =
        Thread.fromJson(Thread(id: 't', title: 'T', pinned: true).toJson());
    expect(p.pinned, isTrue);
    // legacy JSON without the key
    expect(Thread.fromJson({'id': 't', 'title': 'T'}).pinned, isFalse);
    // copyWith toggles
    expect(Thread(id: 't', title: 'T').copyWith(pinned: true).pinned, isTrue);
  });

  test('Character.starred round-trips and defaults false', () {
    expect(const Character(id: 'c', name: 'N').starred, isFalse);
    final s = Character.fromJson(
        const Character(id: 'c', name: 'N', starred: true).toJson());
    expect(s.starred, isTrue);
    expect(Character.fromJson({'id': 'c', 'name': 'N'}).starred, isFalse);
    expect(const Character(id: 'c', name: 'N').copyWith(starred: true).starred,
        isTrue);
  });

  test('Thread.toJson omits pinned when false (byte-stable legacy)', () {
    expect(Thread(id: 't', title: 'T').toJson().containsKey('pinned'), isFalse);
  });

  test('Thread.progress defaults 0/10 and round-trips', () {
    final d = Thread(id: 't', title: 'T');
    expect(d.progress, 0);
    expect(d.progressMax, 10);
    // legacy JSON without keys
    final legacy = Thread.fromJson({'id': 't', 'title': 'T'});
    expect(legacy.progress, 0);
    expect(legacy.progressMax, 10);
    // toJson omits defaults (lean JSON)
    final j = d.toJson();
    expect(j.containsKey('progress'), isFalse);
    expect(j.containsKey('progressMax'), isFalse);
    // round-trip non-defaults via toJson -> fromJson
    final t = Thread(id: 't', title: 'T', progress: 4, progressMax: 6);
    final back = Thread.fromJson(t.toJson());
    expect(back.progress, 4);
    expect(back.progressMax, 6);
    // copyWith threads both fields
    final c = Thread(id: 't', title: 'T').copyWith(progress: 2, progressMax: 8);
    expect(c.progress, 2);
    expect(c.progressMax, 8);
  });

  test('Thread.progress clamps into 0..progressMax', () {
    // over max in ctor
    expect(Thread(id: 't', title: 'T', progress: 99, progressMax: 10).progress,
        10);
    // below zero in ctor
    expect(Thread(id: 't', title: 'T', progress: -5).progress, 0);
    // progressMax floored at 1
    expect(Thread(id: 't', title: 'T', progressMax: 0).progressMax, 1);
    // copyWith re-clamps against the (possibly new) max
    final t = Thread(id: 't', title: 'T', progress: 8, progressMax: 10);
    expect(t.copyWith(progressMax: 5).progress, 5);
    expect(t.copyWith(progress: -1).progress, 0);
    // tolerant fromJson clamps too
    expect(
        Thread.fromJson(
                {'id': 't', 'title': 'T', 'progress': 50, 'progressMax': 10})
            .progress,
        10);
  });

  test('Character.toJson omits starred when false', () {
    expect(const Character(id: 'c', name: 'N').toJson().containsKey('starred'),
        isFalse);
  });

  test('CampaignSettings.defaultOracle defaults juice and round-trips', () {
    expect(const CampaignSettings().defaultOracle, 'juice');
    final s = CampaignSettings.fromJson(
        const CampaignSettings(defaultOracle: 'mythic').toJson());
    expect(s.defaultOracle, 'mythic');
    expect(CampaignSettings.fromJson({}).defaultOracle, 'juice');
  });

  test('CampaignSettings.headerCollapsed defaults false and round-trips', () {
    expect(const CampaignSettings().headerCollapsed, isFalse);
    final s = CampaignSettings.fromJson(
        const CampaignSettings(headerCollapsed: true).toJson());
    expect(s.headerCollapsed, isTrue);
  });

  test('CampaignSettings keeps genre/tone alongside new fields', () {
    const s = CampaignSettings(
        genre: 'noir',
        tone: 'grim',
        defaultOracle: 'roll-high',
        headerCollapsed: true);
    final back = CampaignSettings.fromJson(s.toJson());
    expect(back.genre, 'noir');
    expect(back.tone, 'grim');
    expect(back.defaultOracle, 'roll-high');
    expect(back.headerCollapsed, isTrue);
  });
}
