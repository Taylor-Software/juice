/// Block kinds the help asset can carry (see assets/help_data.json).
enum HelpBlockKind { h, p, tip, steps }

/// One typed content block: [text] for h/p/tip, [items] for steps.
class HelpBlock {
  const HelpBlock.h(this.text)
      : kind = HelpBlockKind.h,
        items = const [];
  const HelpBlock.p(this.text)
      : kind = HelpBlockKind.p,
        items = const [];
  const HelpBlock.tip(this.text)
      : kind = HelpBlockKind.tip,
        items = const [];
  const HelpBlock.steps(this.items)
      : kind = HelpBlockKind.steps,
        text = '';

  final HelpBlockKind kind;
  final String text;
  final List<String> items;
}

/// One help page: a titled, ordered list of blocks.
class HelpPage {
  const HelpPage({required this.id, required this.title, required this.blocks});
  final String id;
  final String title;
  final List<HelpBlock> blocks;
}

/// One help section (guide / systems / about) with its pages in asset order.
class HelpSection {
  const HelpSection(
      {required this.id, required this.title, required this.pages});
  final String id;
  final String title;
  final List<HelpPage> pages;
}

/// Parsed view over assets/help_data.json (hand-written original prose;
/// the asset-shape test guards the structure). Unknown block keys are
/// skipped so future kinds degrade gracefully.
class HelpData {
  HelpData(Map<String, dynamic> json) : sections = _parse(json);

  /// Sections in asset order: guide, systems, about.
  final List<HelpSection> sections;

  static List<HelpSection> _parse(Map<String, dynamic> json) => [
        for (final s in (json['sections'] as List).cast<Map<String, dynamic>>())
          HelpSection(
            id: s['id'] as String,
            title: s['title'] as String,
            pages: [
              for (final p in (s['pages'] as List).cast<Map<String, dynamic>>())
                HelpPage(
                  id: p['id'] as String,
                  title: p['title'] as String,
                  blocks: _blocks(p['blocks'] as List),
                ),
            ],
          ),
      ];

  static List<HelpBlock> _blocks(List<dynamic> raw) {
    final out = <HelpBlock>[];
    for (final b in raw.cast<Map<String, dynamic>>()) {
      final block = _block(b);
      if (block != null) out.add(block);
    }
    return out;
  }

  static HelpBlock? _block(Map<String, dynamic> b) => switch (b.keys.single) {
        'h' => HelpBlock.h(b['h'] as String),
        'p' => HelpBlock.p(b['p'] as String),
        'tip' => HelpBlock.tip(b['tip'] as String),
        'steps' => HelpBlock.steps((b['steps'] as List).cast<String>()),
        _ => null, // unknown kind: skip
      };

  /// The page with [id], searching every section; ArgumentError on unknown.
  HelpPage page(String id) {
    for (final s in sections) {
      for (final p in s.pages) {
        if (p.id == id) return p;
      }
    }
    throw ArgumentError('unknown help page: $id');
  }

  /// Pages of section [sectionId] in order; ArgumentError on unknown.
  List<HelpPage> pagesOf(String sectionId) {
    for (final s in sections) {
      if (s.id == sectionId) return s.pages;
    }
    throw ArgumentError('unknown help section: $sectionId');
  }
}
