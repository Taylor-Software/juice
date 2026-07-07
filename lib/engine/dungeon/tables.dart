/// Typed view over assets/dungeon_data.json (Roll 4 Ruin, CC-BY-NC-SA-4.0).
/// Pure: no Flutter, no I/O. Tolerant of missing optional tables (P1 ships a
/// subset; unknown keys are simply absent). Tables not modelled with a typed
/// getter remain reachable through [raw] for the generator's ref-expansion.
library;

/// Shared shape for both A2 (dungeon room types) and D2 (cave types) rolls.
class A2Type {
  const A2Type(
      {required this.name,
      this.note = '',
      this.tierBump = 0,
      this.treasureBonus = 0,
      this.stockDouble = false,
      this.leadsToCaves = false,
      this.onStock6 = '',
      this.veinBonus = 0,
      this.veinBonusDie = 0,
      this.leadsToDungeon = false,
      this.monsterDie = 0});
  final String name;
  final String note;
  final int tierBump;
  final int treasureBonus;
  final bool stockDouble;
  final bool leadsToCaves;
  final String onStock6;
  final int veinBonus;
  final int veinBonusDie;
  final bool leadsToDungeon;
  final int monsterDie;

  factory A2Type.fromJson(Map<String, dynamic> j) => A2Type(
        name: j['name'] as String? ?? '',
        note: j['note'] as String? ?? '',
        tierBump: (j['tier_bump'] as num?)?.toInt() ?? 0,
        treasureBonus: (j['treasure_bonus'] as num?)?.toInt() ?? 0,
        stockDouble: j['stock_double'] as bool? ?? false,
        leadsToCaves: j['leads_to_caves'] as bool? ?? false,
        onStock6: j['on_stock_6'] as String? ?? '',
        veinBonus: (j['vein_bonus'] as num?)?.toInt() ?? 0,
        veinBonusDie: (j['vein_bonus_die'] as num?)?.toInt() ?? 0,
        leadsToDungeon: j['leads_to_dungeon'] as bool? ?? false,
        monsterDie: (j['monster_die'] as num?)?.toInt() ?? 0,
      );
}

class MonsterRow {
  const MonsterRow(
      {required this.text, required this.count, required this.organized});
  final String text;
  final String count;
  final bool organized;
  factory MonsterRow.fromJson(Map<String, dynamic> j) => MonsterRow(
      text: j['text'] as String,
      count: j['count'] as String? ?? '1',
      organized: j['organized'] as bool? ?? false);
}

class DungeonTables {
  const DungeonTables({
    required this.a1,
    required this.a2,
    required this.b2,
    required this.b5,
    required this.c2,
    required this.reaction,
    required this.upperMonsters,
    required this.factionNames,
    required this.corridorFamilies,
    required this.chamberFamilies,
    required this.labelFallbacks,
    required this.d1,
    required this.d2,
    required this.e2,
    required this.f2,
    required this.cavestone,
    required this.tunnelFamilies,
    required this.caveFamilies,
    required this.centralMonsters,
    required this.deepMonsters,
    required this.raw,
  });

  final List<String> a1;
  final Map<String, A2Type> a2;
  final List<String> b2;
  final List<String> b5;
  final List<String> c2;
  final Map<String, String> reaction;
  final List<MonsterRow> upperMonsters;
  final List<String> factionNames;
  final Map<String, List<List<int>>> corridorFamilies;
  final Map<String, List<List<int>>> chamberFamilies;
  final Map<String, String> labelFallbacks;
  final List<String> d1;
  final Map<String, A2Type> d2;
  final List<String> e2;
  final List<String> f2;
  final List<String> cavestone;
  final Map<String, List<List<int>>> tunnelFamilies;
  final Map<String, List<List<int>>> caveFamilies;
  final List<MonsterRow> centralMonsters;
  final List<MonsterRow> deepMonsters;
  final Map<String, dynamic> raw;

  static List<String> _strs(dynamic v) =>
      (v as List? ?? const []).map((e) => e.toString()).toList();
  static Map<String, List<List<int>>> _fam(dynamic v) => {
        for (final e in (v as Map? ?? const {}).entries)
          e.key as String: [
            for (final r in e.value as List)
              [(r as List)[0] as int, r[1] as int]
          ]
      };

  factory DungeonTables.fromJson(Map<String, dynamic> j) => DungeonTables(
        a1: _strs(j['A1']),
        a2: {
          for (final e in (j['A2'] as Map).entries)
            e.key as String:
                A2Type.fromJson((e.value as Map).cast<String, dynamic>())
        },
        b2: _strs(j['B2']),
        b5: _strs(j['B5']),
        c2: _strs(j['C2']),
        reaction:
            (j['G1'] as Map).map((k, v) => MapEntry(k as String, v.toString())),
        upperMonsters: [
          for (final r in (j['G2'] as List? ?? const []))
            MonsterRow.fromJson((r as Map).cast<String, dynamic>())
        ],
        factionNames: _strs(j['faction_names']),
        corridorFamilies: _fam(j['corridor_families']),
        chamberFamilies: _fam(j['chamber_families']),
        labelFallbacks: (j['label_fallbacks'] as Map? ?? const {})
            .map((k, v) => MapEntry(k as String, v.toString())),
        d1: _strs(j['D1']),
        d2: {
          for (final e in (j['D2'] as Map? ?? const {}).entries)
            e.key as String:
                A2Type.fromJson((e.value as Map).cast<String, dynamic>())
        },
        e2: _strs(j['E2']),
        f2: _strs(j['F2']),
        cavestone: _strs(j['E5']),
        tunnelFamilies: _fam(j['tunnel_families']),
        caveFamilies: _fam(j['cave_families']),
        centralMonsters: [
          for (final r in (j['G3'] as List? ?? const []))
            MonsterRow.fromJson((r as Map).cast<String, dynamic>())
        ],
        deepMonsters: [
          for (final r in (j['G4'] as List? ?? const []))
            MonsterRow.fromJson((r as Map).cast<String, dynamic>())
        ],
        raw: j,
      );
}
