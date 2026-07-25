/// Ironsworn-family sheets (Ironsworn, Starforged, Sundered Isles).
///
/// Part of the `models` library — see models.dart. Split for
/// navigability only; parts share one scope, so the private helpers
/// (`_intOr`, `_strOr`, `_strSet`) and every cross-reference still work.
part of '../models.dart';

/// Classic Ironsworn debilities (conditions, banes, burdens). Each marked
/// debility lowers max momentum and the burn-reset value by 1.
const kIronswornDebilities = <String, String>{
  'wounded': 'Wounded',
  'shaken': 'Shaken',
  'unprepared': 'Unprepared',
  'encumbered': 'Encumbered',
  'maimed': 'Maimed',
  'corrupted': 'Corrupted',
  'cursed': 'Cursed',
  'tormented': 'Tormented',
};

/// Bespoke Classic Ironsworn sheet. Additive on [Character] like
/// [CharacterEmulation]: null until "New Ironsworn character" writes it.
class IronswornSheet {
  const IronswornSheet({
    this.edge = 1,
    this.heart = 1,
    this.iron = 1,
    this.shadow = 1,
    this.wits = 1,
    this.health = 5,
    this.spirit = 5,
    this.supply = 5,
    this.momentum = 2,
    this.xpEarned = 0,
    this.xpSpent = 0,
    this.bonds = 0,
    this.debilities = const {},
    this.vows = const [],
    this.assets = const [],
  });

  final int edge, heart, iron, shadow, wits; // 1..3
  final int health, spirit, supply; // 0..5
  final int momentum; // -6..momentumMax
  final int xpEarned, xpSpent; // >=0
  final int bonds; // 0..10 progress boxes
  final Set<String> debilities; // ids from kIronswornDebilities
  final List<ProgressTrack> vows;
  final List<AssetState> assets;

  int get momentumMax => 10 - debilities.length;
  int get momentumReset => (2 - debilities.length).clamp(0, 2);

  /// Standard pre-made starting character (3/2/2/1/1, full meters, +2 momentum).
  factory IronswornSheet.premade() => const IronswornSheet(
        edge: 3,
        heart: 2,
        iron: 2,
        shadow: 1,
        wits: 1,
        health: 5,
        spirit: 5,
        supply: 5,
        momentum: 2,
      );

  IronswornSheet copyWith({
    int? edge,
    int? heart,
    int? iron,
    int? shadow,
    int? wits,
    int? health,
    int? spirit,
    int? supply,
    int? momentum,
    int? xpEarned,
    int? xpSpent,
    int? bonds,
    Set<String>? debilities,
    List<ProgressTrack>? vows,
    List<AssetState>? assets,
  }) {
    final dbs = debilities ?? this.debilities;
    final maxM = 10 - dbs.length;
    return IronswornSheet(
      edge: (edge ?? this.edge).clamp(1, 3),
      heart: (heart ?? this.heart).clamp(1, 3),
      iron: (iron ?? this.iron).clamp(1, 3),
      shadow: (shadow ?? this.shadow).clamp(1, 3),
      wits: (wits ?? this.wits).clamp(1, 3),
      health: (health ?? this.health).clamp(0, 5),
      spirit: (spirit ?? this.spirit).clamp(0, 5),
      supply: (supply ?? this.supply).clamp(0, 5),
      momentum: (momentum ?? this.momentum).clamp(-6, maxM),
      xpEarned: (xpEarned ?? this.xpEarned).clamp(0, 1 << 31),
      xpSpent: (xpSpent ?? this.xpSpent).clamp(0, 1 << 31),
      bonds: (bonds ?? this.bonds).clamp(0, 10),
      debilities: dbs,
      vows: vows ?? this.vows,
      assets: assets ?? this.assets,
    );
  }

  Map<String, dynamic> toJson() => {
        'edge': edge,
        'heart': heart,
        'iron': iron,
        'shadow': shadow,
        'wits': wits,
        'health': health,
        'spirit': spirit,
        'supply': supply,
        'momentum': momentum,
        'xpEarned': xpEarned,
        'xpSpent': xpSpent,
        'bonds': bonds,
        if (debilities.isNotEmpty) 'debilities': debilities.toList(),
        if (vows.isNotEmpty) 'vows': vows.map((v) => v.toJson()).toList(),
        if (assets.isNotEmpty) 'assets': assets.map((a) => a.toJson()).toList(),
      };

  static IronswornSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final dbs = j['debilities'] is List
        ? (j['debilities'] as List)
            .whereType<String>()
            .where(kIronswornDebilities.containsKey)
            .toSet()
        : <String>{};
    final maxM = 10 - dbs.length;
    return IronswornSheet(
      edge: _intOr(j['edge'], 1).clamp(1, 3),
      heart: _intOr(j['heart'], 1).clamp(1, 3),
      iron: _intOr(j['iron'], 1).clamp(1, 3),
      shadow: _intOr(j['shadow'], 1).clamp(1, 3),
      wits: _intOr(j['wits'], 1).clamp(1, 3),
      health: _intOr(j['health'], 5).clamp(0, 5),
      spirit: _intOr(j['spirit'], 5).clamp(0, 5),
      supply: _intOr(j['supply'], 5).clamp(0, 5),
      momentum: _intOr(j['momentum'], 2).clamp(-6, maxM),
      xpEarned: _intOr(j['xpEarned'], 0).clamp(0, 1 << 31),
      xpSpent: _intOr(j['xpSpent'], 0).clamp(0, 1 << 31),
      bonds: _intOr(j['bonds'], 0).clamp(0, 10),
      debilities: dbs,
      vows: j['vows'] is List
          ? (j['vows'] as List)
              .map(ProgressTrack.maybeFromJson)
              .whereType<ProgressTrack>()
              .toList()
          : const [],
      assets: j['assets'] is List
          ? (j['assets'] as List)
              .map(AssetState.maybeFromJson)
              .whereType<AssetState>()
              .toList()
          : const [],
    );
  }
}

/// Read-only asset definition parsed from a loaded ruleset map's
/// `asset_collections` block (emitted by build_datasworn.py).
class IronswornAssetDef {
  const IronswornAssetDef({
    required this.id,
    required this.name,
    required this.category,
    required this.abilities,
    required this.abilityEnabled,
    this.meters = const [],
  });
  final String id;
  final String name;
  final String category;
  final List<String> abilities; // ability text
  final List<bool> abilityEnabled; // default-on flags
  final List<AssetMeter> meters; // condition meters (health/integrity/ammo/…)

  /// A fresh persisted [AssetState] with the definition's default flags + meters.
  AssetState toState() => AssetState(
        assetId: id,
        name: name,
        category: category,
        enabledAbilities: List<bool>.of(abilityEnabled),
        meters: List<AssetMeter>.of(meters),
      );

  /// Parse condition meters from a Datasworn asset's `controls` map. Each
  /// control with `field_type == 'condition_meter'` becomes an [AssetMeter]
  /// seeded at its default `value`; nested toggles (battered, out-of-action) are
  /// not surfaced yet.
  static List<AssetMeter> _metersFromControls(dynamic controls) {
    if (controls is! Map) return const [];
    final out = <AssetMeter>[];
    for (final e in controls.entries) {
      final c = e.value;
      if (c is! Map || c['field_type'] != 'condition_meter') continue;
      final max = (c['max'] as num?)?.toInt();
      if (max == null) continue;
      final min = (c['min'] as num?)?.toInt() ?? 0;
      out.add(AssetMeter(
        key: '${e.key}',
        label: c['label'] is String ? c['label'] as String : '${e.key}',
        min: min,
        max: max,
        value: (c['value'] as num?)?.toInt() ?? max,
      ));
    }
    return out;
  }

  static List<IronswornAssetDef> listFromRuleset(Map<String, dynamic> ruleset) {
    final out = <IronswornAssetDef>[];
    final colls = ruleset['asset_collections'];
    if (colls is! List) return out;
    for (final coll in colls) {
      if (coll is! Map) continue;
      final assets = coll['assets'];
      if (assets is! List) continue;
      final collName = coll['name'] is String ? coll['name'] as String : '';
      for (final a in assets) {
        if (a is! Map) continue;
        final id = a['id'];
        final name = a['name'];
        if (id is! String || name is! String) continue;
        final abilities = <String>[];
        final enabled = <bool>[];
        if (a['abilities'] is List) {
          for (final ab in a['abilities'] as List) {
            if (ab is! Map) continue;
            abilities.add(ab['text'] is String ? ab['text'] as String : '');
            enabled.add(ab['enabled'] == true);
          }
        }
        out.add(IronswornAssetDef(
          id: id,
          name: name,
          category:
              a['category'] is String ? a['category'] as String : collName,
          abilities: abilities,
          abilityEnabled: enabled,
          meters: _metersFromControls(a['controls']),
        ));
      }
    }
    return out;
  }
}

/// Starforged impacts (replace Classic debilities). Each marked impact lowers
/// max momentum and the burn-reset value by 1. Ordered by datasworn category:
/// misfortunes, vehicle troubles, burdens, lasting effects.
const kStarforgedImpacts = <String, String>{
  'wounded': 'Wounded',
  'shaken': 'Shaken',
  'unprepared': 'Unprepared',
  'battered': 'Battered',
  'cursed': 'Cursed',
  'doomed': 'Doomed',
  'tormented': 'Tormented',
  'indebted': 'Indebted',
  'permanently_harmed': 'Permanently Harmed',
  'traumatized': 'Traumatized',
};

/// Bespoke Starforged sheet. Additive on [Character] like [IronswornSheet]:
/// null until "New Starforged character" writes it.
class StarforgedSheet {
  const StarforgedSheet({
    this.edge = 1,
    this.heart = 1,
    this.iron = 1,
    this.shadow = 1,
    this.wits = 1,
    this.health = 5,
    this.spirit = 5,
    this.supply = 5,
    this.momentum = 2,
    this.xpEarned = 0,
    this.xpSpent = 0,
    this.questsLegacy = 0,
    this.bondsLegacy = 0,
    this.discoveriesLegacy = 0,
    this.impacts = const {},
    this.vows = const [],
    this.connections = const [],
    this.assets = const [],
    this.assetRuleset = 'starforged',
  });

  final int edge, heart, iron, shadow, wits; // 1..3
  final int health, spirit, supply; // 0..5
  final int momentum; // -6..momentumMax
  final int xpEarned, xpSpent; // >=0
  final int questsLegacy, bondsLegacy, discoveriesLegacy; // 0..10 boxes
  final Set<String> impacts; // ids from kStarforgedImpacts
  final List<ProgressTrack> vows;
  final List<ProgressTrack> connections;
  final List<AssetState> assets;
  final String assetRuleset; // 'starforged' | 'sundered_isles'

  bool get isSundered => assetRuleset == 'sundered_isles';

  static String _validRuleset(String s) =>
      s == 'sundered_isles' ? 'sundered_isles' : 'starforged';

  int get momentumMax => 10 - impacts.length;
  int get momentumReset => (2 - impacts.length).clamp(0, 2);

  factory StarforgedSheet.premade({String assetRuleset = 'starforged'}) =>
      StarforgedSheet(
        edge: 3,
        heart: 2,
        iron: 2,
        shadow: 1,
        wits: 1,
        health: 5,
        spirit: 5,
        supply: 5,
        momentum: 2,
        assetRuleset: assetRuleset,
      );

  StarforgedSheet copyWith({
    int? edge,
    int? heart,
    int? iron,
    int? shadow,
    int? wits,
    int? health,
    int? spirit,
    int? supply,
    int? momentum,
    int? xpEarned,
    int? xpSpent,
    int? questsLegacy,
    int? bondsLegacy,
    int? discoveriesLegacy,
    Set<String>? impacts,
    List<ProgressTrack>? vows,
    List<ProgressTrack>? connections,
    List<AssetState>? assets,
    String? assetRuleset,
  }) {
    final imp = impacts ?? this.impacts;
    final maxM = 10 - imp.length;
    return StarforgedSheet(
      edge: (edge ?? this.edge).clamp(1, 3),
      heart: (heart ?? this.heart).clamp(1, 3),
      iron: (iron ?? this.iron).clamp(1, 3),
      shadow: (shadow ?? this.shadow).clamp(1, 3),
      wits: (wits ?? this.wits).clamp(1, 3),
      health: (health ?? this.health).clamp(0, 5),
      spirit: (spirit ?? this.spirit).clamp(0, 5),
      supply: (supply ?? this.supply).clamp(0, 5),
      momentum: (momentum ?? this.momentum).clamp(-6, maxM),
      xpEarned: (xpEarned ?? this.xpEarned).clamp(0, 1 << 31),
      xpSpent: (xpSpent ?? this.xpSpent).clamp(0, 1 << 31),
      questsLegacy: (questsLegacy ?? this.questsLegacy).clamp(0, 10),
      bondsLegacy: (bondsLegacy ?? this.bondsLegacy).clamp(0, 10),
      discoveriesLegacy:
          (discoveriesLegacy ?? this.discoveriesLegacy).clamp(0, 10),
      impacts: imp,
      vows: vows ?? this.vows,
      connections: connections ?? this.connections,
      assets: assets ?? this.assets,
      assetRuleset: _validRuleset(assetRuleset ?? this.assetRuleset),
    );
  }

  Map<String, dynamic> toJson() => {
        'edge': edge,
        'heart': heart,
        'iron': iron,
        'shadow': shadow,
        'wits': wits,
        'health': health,
        'spirit': spirit,
        'supply': supply,
        'momentum': momentum,
        'xpEarned': xpEarned,
        'xpSpent': xpSpent,
        'questsLegacy': questsLegacy,
        'bondsLegacy': bondsLegacy,
        'discoveriesLegacy': discoveriesLegacy,
        if (impacts.isNotEmpty) 'impacts': impacts.toList(),
        if (vows.isNotEmpty) 'vows': vows.map((v) => v.toJson()).toList(),
        if (connections.isNotEmpty)
          'connections': connections.map((c) => c.toJson()).toList(),
        if (assets.isNotEmpty) 'assets': assets.map((a) => a.toJson()).toList(),
        if (assetRuleset != 'starforged') 'assetRuleset': assetRuleset,
      };

  static StarforgedSheet? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    List<ProgressTrack> tracks(dynamic v) => v is List
        ? v.map(ProgressTrack.maybeFromJson).whereType<ProgressTrack>().toList()
        : const [];
    final imp = j['impacts'] is List
        ? (j['impacts'] as List)
            .whereType<String>()
            .where(kStarforgedImpacts.containsKey)
            .toSet()
        : <String>{};
    final maxM = 10 - imp.length;
    return StarforgedSheet(
      edge: _intOr(j['edge'], 1).clamp(1, 3),
      heart: _intOr(j['heart'], 1).clamp(1, 3),
      iron: _intOr(j['iron'], 1).clamp(1, 3),
      shadow: _intOr(j['shadow'], 1).clamp(1, 3),
      wits: _intOr(j['wits'], 1).clamp(1, 3),
      health: _intOr(j['health'], 5).clamp(0, 5),
      spirit: _intOr(j['spirit'], 5).clamp(0, 5),
      supply: _intOr(j['supply'], 5).clamp(0, 5),
      momentum: _intOr(j['momentum'], 2).clamp(-6, maxM),
      xpEarned: _intOr(j['xpEarned'], 0).clamp(0, 1 << 31),
      xpSpent: _intOr(j['xpSpent'], 0).clamp(0, 1 << 31),
      questsLegacy: _intOr(j['questsLegacy'], 0).clamp(0, 10),
      bondsLegacy: _intOr(j['bondsLegacy'], 0).clamp(0, 10),
      discoveriesLegacy: _intOr(j['discoveriesLegacy'], 0).clamp(0, 10),
      impacts: imp,
      vows: tracks(j['vows']),
      connections: tracks(j['connections']),
      assets: j['assets'] is List
          ? (j['assets'] as List)
              .map(AssetState.maybeFromJson)
              .whereType<AssetState>()
              .toList()
          : const [],
      assetRuleset: _validRuleset(j['assetRuleset'] is String
          ? j['assetRuleset'] as String
          : 'starforged'),
    );
  }
}

// --- D&D 5e (SRD 5.1 game-mechanic facts only; no SRD prose) ---------------
