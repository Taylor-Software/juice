import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('Thread.pinned round-trips and defaults false', () {
    expect(const Thread(id: 't', title: 'T').pinned, isFalse);
    final p = Thread.fromJson(
        const Thread(id: 't', title: 'T', pinned: true).toJson());
    expect(p.pinned, isTrue);
    // legacy JSON without the key
    expect(Thread.fromJson({'id': 't', 'title': 'T'}).pinned, isFalse);
    // copyWith toggles
    expect(const Thread(id: 't', title: 'T').copyWith(pinned: true).pinned,
        isTrue);
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
    expect(const Thread(id: 't', title: 'T').toJson().containsKey('pinned'),
        isFalse);
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
