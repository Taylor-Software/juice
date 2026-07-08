import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/campaign_search.dart';
import 'package:juice_oracle/engine/models.dart';
import 'package:juice_oracle/state/providers.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('Place model', () {
    test('round-trips kind/note/location; omits defaults', () {
      const p = Place(
        id: 'p1',
        name: 'The Crimson Tower',
        kind: PlaceKind.landmark,
        note: 'Home of the recluse.',
        location: LocationRef(hexCol: 3, hexRow: 4),
      );
      final j = p.toJson();
      final back = Place.fromJson(j);
      expect(back.name, 'The Crimson Tower');
      expect(back.kind, PlaceKind.landmark);
      expect(back.note, 'Home of the recluse.');
      expect(back.location?.hexCol, 3);
      expect(back.location?.hexRow, 4);

      const bare = Place(id: 'p2', name: 'X');
      expect(bare.toJson().containsKey('kind'), isFalse);
      expect(bare.toJson().containsKey('note'), isFalse);
      expect(bare.toJson().containsKey('loc'), isFalse);
      expect(Place.fromJson(bare.toJson()).kind, PlaceKind.other);
    });

    test('copyWith clearLocation drops the map pin', () {
      const p = Place(id: 'p1', name: 'X', location: LocationRef(roomId: 'r1'));
      expect(p.copyWith(clearLocation: true).location, isNull);
    });
  });

  group('Npc model', () {
    test('round-trips role/disposition/note/placeId; omits defaults', () {
      const n = Npc(
        id: 'n1',
        name: 'Bram',
        role: 'Innkeeper',
        disposition: NpcDisposition.friendly,
        note: 'Knows the back roads.',
        placeId: 'p1',
      );
      final back = Npc.fromJson(n.toJson());
      expect(back.name, 'Bram');
      expect(back.role, 'Innkeeper');
      expect(back.disposition, NpcDisposition.friendly);
      expect(back.placeId, 'p1');

      const bare = Npc(id: 'n2', name: 'Y');
      expect(bare.toJson().containsKey('role'), isFalse);
      expect(bare.toJson().containsKey('disp'), isFalse);
      expect(bare.toJson().containsKey('placeId'), isFalse);
      expect(Npc.fromJson(bare.toJson()).disposition, NpcDisposition.neutral);
    });

    test('copyWith clearPlace unlinks', () {
      const n = Npc(id: 'n1', name: 'Y', placeId: 'p1');
      expect(n.copyWith(clearPlace: true).placeId, isNull);
    });

    test('relations round-trip through JSON; omitted when empty', () {
      const n = Npc(id: 'n1', name: 'Bram', relations: [
        NpcRelation('n2', 'brother'),
        NpcRelation('n3', ''),
      ]);
      final back = Npc.fromJson(n.toJson());
      expect(back.relations.map((r) => r.npcId), ['n2', 'n3']);
      expect(back.relations.first.label, 'brother');
      expect(back.relations.last.label, '');
      expect(
          const Npc(id: 'x', name: 'Y').toJson().containsKey('rel'), isFalse);
      // Malformed relation entries are dropped.
      final tolerant = Npc.fromJson({
        'id': 'z',
        'name': 'Z',
        'rel': [
          'garbage',
          {'label': 'no-npc-id'},
          {'npc': 'ok'}
        ],
      });
      expect(tolerant.relations.map((r) => r.npcId), ['ok']);
    });
  });

  group('providers', () {
    test('PlaceNotifier add/upsert/remove persist', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      final n = c.read(placesProvider.notifier);
      await c.read(placesProvider.future);

      await n.add('Harbor', kind: PlaceKind.settlement);
      final places = c.read(placesProvider).value!;
      expect(places.single.name, 'Harbor');
      expect(places.single.kind, PlaceKind.settlement);

      // upsert existing id replaces; new id prepends.
      final edited = places.single.copyWith(note: 'Busy docks');
      await n.upsert(edited);
      expect(c.read(placesProvider).value!.single.note, 'Busy docks');
      await n.upsert(const Place(id: 'zzz', name: 'Ruin'));
      expect(c.read(placesProvider).value!.length, 2);
      expect(c.read(placesProvider).value!.first.name, 'Ruin');

      await n.remove('zzz');
      expect(c.read(placesProvider).value!.length, 1);
    });

    test('promote a met NPC to a companion Character', () async {
      SharedPreferences.setMockInitialValues({});
      final c = ProviderContainer();
      addTearDown(c.dispose);
      await c.read(charactersProvider.future);
      await c
          .read(charactersProvider.notifier)
          .addCompanion('Bram', note: 'Innkeeper turned guide');
      final chars = c.read(charactersProvider).value!;
      expect(chars.single.name, 'Bram');
      expect(chars.single.role, CharacterRole.companion);
      expect(chars.single.note, 'Innkeeper turned guide');
    });
  });

  test('placesAtLocation matches pinned places by map cell', () {
    const places = [
      Place(
          id: 'a', name: 'Tower', location: LocationRef(hexCol: 3, hexRow: 4)),
      Place(id: 'b', name: 'Cave', location: LocationRef(roomId: 'r1')),
      Place(id: 'c', name: 'Floating'), // no pin
    ];
    expect(
        placesAtLocation(places, const LocationRef(hexCol: 3, hexRow: 4))
            .map((p) => p.id),
        ['a']);
    expect(
        placesAtLocation(places, const LocationRef(roomId: 'r1')).single.name,
        'Cave');
    expect(placesAtLocation(places, const LocationRef(hexCol: 9, hexRow: 9)),
        isEmpty);
  });

  test('searchCampaign includes places and npcs', () {
    final results = searchCampaign(
      'crimson',
      places: const [Place(id: 'p1', name: 'The Crimson Tower')],
      npcs: const [Npc(id: 'n1', name: 'Bram', role: 'Innkeeper')],
    );
    expect(results, hasLength(1));
    expect(results.single.kind, SearchResultKind.place);
    expect(results.single.subtab, 'places');

    final byRole = searchCampaign(
      'innkeeper',
      npcs: const [Npc(id: 'n1', name: 'Bram', role: 'Innkeeper')],
    );
    expect(byRole.single.kind, SearchResultKind.npc);
    expect(byRole.single.subtab, 'people');
  });
}
