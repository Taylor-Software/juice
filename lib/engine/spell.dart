/// A bundled, reference-only spell entry. Facts + vendored SRD text under a
/// free license (attribution carried in kContentAttributions). Pure — no Flutter.
class SpellEntry {
  const SpellEntry({
    required this.id,
    required this.system,
    this.edition,
    required this.name,
    this.level = 0,
    this.school = '',
    this.castingTime = '',
    this.range = '',
    this.components = '',
    this.duration = '',
    this.concentration = false,
    this.ritual = false,
    this.classes = const [],
    this.description = '',
    this.higherLevels,
  });

  final String id;
  final String system;
  final String? edition; // "5.1" | "5.2" | null
  final String name;
  final int level; // 0 = cantrip
  final String school;
  final String castingTime, range, components, duration;
  final bool concentration, ritual;
  final List<String> classes;
  final String description;
  final String? higherLevels;

  Map<String, dynamic> toJson() => {
        'id': id,
        'system': system,
        if (edition != null) 'edition': edition,
        'name': name,
        if (level != 0) 'level': level,
        if (school.isNotEmpty) 'school': school,
        if (castingTime.isNotEmpty) 'castingTime': castingTime,
        if (range.isNotEmpty) 'range': range,
        if (components.isNotEmpty) 'components': components,
        if (duration.isNotEmpty) 'duration': duration,
        if (concentration) 'concentration': true,
        if (ritual) 'ritual': true,
        if (classes.isNotEmpty) 'classes': classes,
        if (description.isNotEmpty) 'description': description,
        if (higherLevels != null) 'higherLevels': higherLevels,
      };

  static SpellEntry? maybeFromJson(dynamic j) {
    if (j is! Map) return null;
    final id = j['id'] as String?;
    final name = j['name'] as String?;
    if (id == null || id.isEmpty || name == null || name.isEmpty) return null;
    return SpellEntry(
      id: id,
      system: (j['system'] as String?) ?? '',
      edition: j['edition'] as String?,
      name: name,
      level: (j['level'] as num?)?.toInt() ?? 0,
      school: (j['school'] as String?) ?? '',
      castingTime: (j['castingTime'] as String?) ?? '',
      range: (j['range'] as String?) ?? '',
      components: (j['components'] as String?) ?? '',
      duration: (j['duration'] as String?) ?? '',
      concentration: j['concentration'] == true,
      ritual: j['ritual'] == true,
      classes: ((j['classes'] as List?) ?? const []).cast<String>(),
      description: (j['description'] as String?) ?? '',
      higherLevels: j['higherLevels'] as String?,
    );
  }
}
