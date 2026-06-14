import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/map_builder.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../shared/result_card.dart';
import '../state/providers.dart';

/// Grid cell size for the dungeon canvas, in logical pixels.
const _cell = 56.0;

/// Inset of a room's rounded rect inside its cell.
const _roomInset = 6.0;

/// Pixel rect of a room's cell content. The canvas origin is offset so the
/// minimum grid coordinates land at pad = cell/2 from the top-left; painter
/// and [roomIdAt] share this so they can't drift.
Rect roomRectFor(DungeonRoom r, int minX, int minY, double cell) {
  final pad = cell / 2;
  final left = (r.x - minX) * cell + pad;
  final top = (r.y - minY) * cell + pad;
  return Rect.fromLTWH(left + _roomInset, top + _roomInset,
      cell - 2 * _roomInset, cell - 2 * _roomInset);
}

/// Pure hit-test: id of the room whose rect contains [local], else null.
String? roomIdAt(List<DungeonRoom> rooms, Offset local, double cell) {
  if (rooms.isEmpty) return null;
  final minX = rooms.map((r) => r.x).reduce(math.min);
  final minY = rooms.map((r) => r.y).reduce(math.min);
  for (final r in rooms) {
    if (roomRectFor(r, minX, minY, cell).contains(local)) return r.id;
  }
  return null;
}

// -- Dungeon ----------------------------------------------------------------
class DungeonMapPane extends ConsumerStatefulWidget {
  const DungeonMapPane({super.key, required this.oracle});
  final Oracle oracle;

  @override
  ConsumerState<DungeonMapPane> createState() => DungeonMapPaneState();
}

class DungeonMapPaneState extends ConsumerState<DungeonMapPane> {
  GenResult? _last; // latest linger result
  int _hcDungeonCount = 8; // hexcrawl "Generate dungeon" room count

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mapProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (s) {
        final selected = s.currentRoomId == null
            ? null
            : s.rooms.where((r) => r.id == s.currentRoomId).firstOrNull;
        return Column(
          children: [
            _controls(context, s),
            if (_hexcrawlOn()) _hexcrawlDungeonControls(context),
            Expanded(child: s.rooms.isEmpty ? _empty(context) : _canvas(s)),
            if (selected != null) _detailCard(context, selected),
            if (_last != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ResultCard(
                  result: _last!,
                  onLog: () => _log(_last!.title, _last!.asText),
                ),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  Widget _controls(BuildContext context, MapState s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          // Flexible bounds the button's width. As a bare non-flex Row child a
          // FilledButton is measured with maxWidth:Infinity (RenderFlex sizes
          // non-flex children against an unbounded main axis) and throws
          // "BoxConstraints forces an infinite width" — aborting the whole
          // tab's layout (blank tool / hung release web).
          Flexible(
            child: FilledButton.tonal(
              key: const Key('new-room'),
              onPressed: _newRoom,
              child: const Text('New room'),
            ),
          ),
          const Spacer(),
          IconButton(
            key: const Key('dungeon-journal'),
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Add map to journal',
            onPressed: s.rooms.isEmpty
                ? null
                : () => _log('Dungeon map', _dungeonSummary(s)),
          ),
          IconButton(
            key: const Key('dungeon-reset'),
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Reset dungeon',
            onPressed: () => _reset(context),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No rooms yet. New room rolls the dungeon oracle and maps it.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _canvas(MapState s) {
    final scheme = Theme.of(context).colorScheme;
    final minX = s.rooms.map((r) => r.x).reduce(math.min);
    final minY = s.rooms.map((r) => r.y).reduce(math.min);
    final maxX = s.rooms.map((r) => r.x).reduce(math.max);
    final maxY = s.rooms.map((r) => r.y).reduce(math.max);
    final width = math.max((maxX - minX + 1) * _cell + _cell, 360.0);
    final height = math.max((maxY - minY + 1) * _cell + _cell, 360.0);
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(400),
      minScale: 0.5,
      maxScale: 3,
      child: SizedBox(
        width: width,
        height: height,
        child: GestureDetector(
          // InteractiveViewer delivers tap positions in child coordinates
          // (already inverse-transformed) — no manual matrix math.
          onTapUp: (d) {
            final id = roomIdAt(s.rooms, d.localPosition, _cell);
            if (id != null) ref.read(mapProvider.notifier).selectRoom(id);
          },
          child: CustomPaint(
            key: const Key('dungeon-canvas'),
            size: Size(width, height),
            painter: _DungeonPainter(
              rooms: s.rooms,
              corridors: s.corridors,
              currentRoomId: s.currentRoomId,
              scheme: scheme,
            ),
          ),
        ),
      ),
    );
  }

  bool _lonelogOn() =>
      (ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
              kAllSystems)
          .contains('lonelog');

  bool _hexcrawlOn() =>
      (ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
              kAllSystems)
          .contains('hexcrawl');

  Future<void> _hcRoom() async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier).crawlDungeon(data, widget.oracle.dice);
  }

  Future<void> _hcDungeon() async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .generateDungeon(data, _hcDungeonCount, widget.oracle.dice);
  }

  Widget _hexcrawlDungeonControls(BuildContext context) {
    final data = ref.watch(hexcrawlDataProvider).valueOrNull;
    if (data == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          FilledButton.tonal(
            key: const Key('hexcrawl-new-room'),
            onPressed: _hcRoom,
            child: const Text('New room (hexcrawl)'),
          ),
          FilledButton.tonal(
            key: const Key('hexcrawl-generate-dungeon'),
            onPressed: _hcDungeon,
            child: Text('Generate dungeon ($_hcDungeonCount)'),
          ),
          IconButton(
            icon: const Icon(Icons.remove),
            onPressed: () => setState(
                () => _hcDungeonCount = (_hcDungeonCount - 2).clamp(4, 30)),
          ),
          IconButton(
            icon: const Icon(Icons.add),
            onPressed: () => setState(
                () => _hcDungeonCount = (_hcDungeonCount + 2).clamp(4, 30)),
          ),
        ],
      ),
    );
  }

  Widget _detailCard(BuildContext context, DungeonRoom room) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('room-detail-card'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(room.title, style: theme.textTheme.titleMedium),
            const SizedBox(height: 4),
            ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 120),
              child: SingleChildScrollView(
                child: Text(room.detail, style: theme.textTheme.bodyMedium),
              ),
            ),
            const SizedBox(height: 8),
            if (_lonelogOn()) ...[
              Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  for (final st in kDungeonRoomStatuses)
                    ChoiceChip(
                      label: Text(st),
                      visualDensity: VisualDensity.compact,
                      selected: room.status == st,
                      onSelected: (sel) => ref
                          .read(mapProvider.notifier)
                          .setRoomStatus(room.id, sel ? st : ''),
                    ),
                ],
              ),
              const SizedBox(height: 8),
            ],
            Row(
              children: [
                OutlinedButton(
                  key: const Key('linger'),
                  onPressed: () => _linger(room),
                  child: const Text('Linger'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _newRoom() async {
    final g = widget.oracle.dungeonRoom();
    final title = g.rolls.isEmpty ? g.title : g.rolls.first.value;
    await ref
        .read(mapProvider.notifier)
        .addRoom(title: title, detail: g.asText, dice: widget.oracle.dice);
  }

  Future<void> _linger(DungeonRoom room) async {
    final g = widget.oracle.dungeonLinger();
    await ref.read(mapProvider.notifier).appendRoomDetail(room.id, g.asText);
    setState(() => _last = g);
  }

  String _dungeonSummary(MapState s) {
    final titles = s.rooms.map((r) => r.title).take(12).join(', ');
    final more = s.rooms.length > 12 ? ', …' : '';
    return '${s.rooms.length} rooms — $titles$more';
  }

  Future<void> _log(String title, String body) async {
    await ref.read(journalProvider.notifier).add(title, body);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to journal')),
      );
    }
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset dungeon?'),
        content: const Text('All mapped rooms are removed. '
            'The hex map is kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(mapProvider.notifier).resetDungeon();
    if (mounted) setState(() => _last = null);
  }
}

class _DungeonPainter extends CustomPainter {
  _DungeonPainter({
    required this.rooms,
    required this.corridors,
    required this.currentRoomId,
    required this.scheme,
  });

  final List<DungeonRoom> rooms;
  final List<List<String>> corridors;
  final String? currentRoomId;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    if (rooms.isEmpty) return;
    final minX = rooms.map((r) => r.x).reduce(math.min);
    final minY = rooms.map((r) => r.y).reduce(math.min);
    final byId = {for (final r in rooms) r.id: r};

    // Corridors first, under the rooms.
    final line = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 2;
    for (final c in corridors) {
      final a = byId[c[0]];
      final b = byId[c[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(roomRectFor(a, minX, minY, _cell).center,
          roomRectFor(b, minX, minY, _cell).center, line);
    }

    for (final r in rooms) {
      final rect = roomRectFor(r, minX, minY, _cell);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
      final isCurrent = r.id == currentRoomId;
      canvas.drawRRect(
          rrect,
          Paint()
            ..color = isCurrent
                ? scheme.primaryContainer
                : scheme.surfaceContainerHighest);
      if (isCurrent) {
        canvas.drawRRect(
            rrect,
            Paint()
              ..color = scheme.primary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2);
      }
      final tp = TextPainter(
        text: TextSpan(
          text: r.title.isEmpty ? '?' : r.title[0].toUpperCase(),
          style: TextStyle(
            color:
                isCurrent ? scheme.onPrimaryContainer : scheme.onSurfaceVariant,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, rect.center - Offset(tp.width / 2, tp.height / 2));
    }
  }

  @override
  bool shouldRepaint(_DungeonPainter old) =>
      old.rooms != rooms ||
      old.corridors != corridors ||
      old.currentRoomId != currentRoomId ||
      old.scheme != scheme;
}

// -- Hex --------------------------------------------------------------------

/// Flat-top hex radius (center to corner), in logical pixels.
const _hexSize = 34.0;

/// Pixel center of an odd-q offset cell (flat-top hexes, odd columns
/// shifted half a hex DOWN). The canvas origin is offset so the minimum
/// grid coordinates land at pad = 2*size; painter and [hexAt] share this
/// so they can't drift. NOTE: the half-hex parity shift uses the ABSOLUTE
/// column ([col].isOdd, true for negative odd cols too), not the shifted
/// one — the layout must not reflow when the map grows past the origin.
Offset hexCenterFor(int col, int row, int minCol, int minRow, double size) {
  final pad = 2 * size;
  return Offset(
    (col - minCol) * 1.5 * size + pad,
    (row - minRow) * math.sqrt(3) * size +
        (col.isOdd ? math.sqrt(3) / 2 * size : 0) +
        pad,
  );
}

/// Pure inverse of [hexCenterFor]: the candidate cell whose center is
/// nearest to [local] and within 0.9 * size of it, else null.
({int col, int row})? hexAt(
  Offset local,
  double size,
  List<({int col, int row})> cells, {
  required int minCol,
  required int minRow,
}) {
  ({int col, int row})? best;
  var bestDistance = 0.9 * size;
  for (final c in cells) {
    final d =
        (hexCenterFor(c.col, c.row, minCol, minRow, size) - local).distance;
    if (d < bestDistance) {
      bestDistance = d;
      best = c;
    }
  }
  return best;
}

/// Fixed base hues for the 10 wilderness environments (index = envRow - 1):
/// 1 Arctic ice, 2 Mountain grey, 3 Cavern violet, 4 Hills light green,
/// 5 Grassland lime, 6 Forest green, 7 Swamp murk, 8 Water blue,
/// 9 Coast sand, 10 Desert orange. Alpha-blended over the theme surface in
/// the painter so they sit comfortably in light and dark mode.
const _envHues = [
  Color(0xFF80DEEA),
  Color(0xFF90A4AE),
  Color(0xFF7E57C2),
  Color(0xFFAED581),
  Color(0xFFCDDC39),
  Color(0xFF388E3C),
  Color(0xFF6D8B3C),
  Color(0xFF42A5F5),
  Color(0xFFFFD54F),
  Color(0xFFFF8A65),
];

/// Fixed hues for the 10 Verdant terrain keys (used when a hex has Verdant
/// terrain instead of a Juice envRow).
const Map<String, Color> _verdantTerrainHues = {
  'caatinga': Color(0xFF8D6E63),
  'desert': Color(0xFFE0C068),
  'floodplain': Color(0xFF7CB342),
  'forest': Color(0xFF2E7D32),
  'grassland': Color(0xFF9CCC65),
  'hills': Color(0xFFA1887F),
  'marsh': Color(0xFF26A69A),
  'mountain': Color(0xFF78909C),
  'swamp': Color(0xFF558B2F),
  'water': Color(0xFF1E88E5),
};

/// Fixed hues for the 12 generic hexcrawl terrain keys (used when a hex carries
/// a hexcrawl-generated terrain instead of a Juice envRow / Verdant terrain).
const Map<String, Color> hexcrawlTerrainHues = {
  'arctic': Color(0xFFB3E5FC),
  'coast': Color(0xFF80DEEA),
  'desert': Color(0xFFE0C068),
  'forest': Color(0xFF2E7D32),
  'hills': Color(0xFFA1887F),
  'jungle': Color(0xFF1B5E20),
  'marsh': Color(0xFF26A69A),
  'mountains': Color(0xFF78909C),
  'plains': Color(0xFF9CCC65),
  'taiga': Color(0xFF4DB6AC),
  'wastes': Color(0xFFBCAAA4),
  'water': Color(0xFF1E88E5),
};

class HexMapPane extends ConsumerStatefulWidget {
  const HexMapPane({super.key, required this.oracle});
  final Oracle oracle;

  @override
  ConsumerState<HexMapPane> createState() => HexMapPaneState();
}

enum _HexZoom { region, flower }

class HexMapPaneState extends ConsumerState<HexMapPane> {
  GenResult? _last; // latest travel result
  String _hcClimate = 'temperate';
  int _hcCount = 10;
  int? _selCol, _selRow; // selected revealed hex (null = none)
  _HexZoom _zoom = _HexZoom.region;

  HexCell? _selectedHex(MapState s) => _selCol == null
      ? null
      : s.hexes.where((h) => h.col == _selCol && h.row == _selRow).firstOrNull;

  List<String> get _envNames =>
      widget.oracle.data.table('wilderness_environment');

  bool _hexcrawlOn() =>
      (ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
              kAllSystems)
          .contains('hexcrawl');

  Future<void> _hcCrawl() async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .crawlHexcrawl(data, _hcClimate, widget.oracle.dice);
  }

  Future<void> _hcRegion() async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .generateRegion(data, _hcClimate, _hcCount, widget.oracle.dice);
  }

  Widget _hexcrawlControls(BuildContext context) {
    final data = ref.watch(hexcrawlDataProvider).valueOrNull;
    if (data == null) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: 6,
            children: [
              for (final c in data.climates)
                ChoiceChip(
                  label: Text(c),
                  selected: _hcClimate == c,
                  onSelected: (_) => setState(() => _hcClimate = c),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              FilledButton.tonal(
                key: const Key('hexcrawl-reveal'),
                onPressed: _hcCrawl,
                child: const Text('Reveal next (hexcrawl)'),
              ),
              FilledButton.tonal(
                key: const Key('hexcrawl-generate-region'),
                onPressed: _hcRegion,
                child: Text('Generate region ($_hcCount)'),
              ),
              IconButton(
                icon: const Icon(Icons.remove),
                onPressed: () =>
                    setState(() => _hcCount = (_hcCount - 5).clamp(5, 60)),
              ),
              IconButton(
                icon: const Icon(Icons.add),
                onPressed: () =>
                    setState(() => _hcCount = (_hcCount + 5).clamp(5, 60)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(mapProvider);
    final crawl = ref.watch(crawlProvider).valueOrNull ?? const CrawlState();
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (s) {
        final sel = _selectedHex(s);
        return Column(
          children: [
            if (crawl.envRow != null) _envLine(context, crawl),
            _controls(context, s),
            if (_hexcrawlOn()) _hexcrawlControls(context),
            Expanded(
              child: _zoom == _HexZoom.flower && sel != null
                  ? _flowerView(context, sel)
                  : (s.hexes.isEmpty ? _empty(context) : _canvas(s)),
            ),
            if (_hexcrawlOn() && sel != null && _zoom == _HexZoom.region)
              _hexDetailCard(context, sel),
            if (_last != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: ResultCard(
                  result: _last!,
                  onLog: () => _log(_last!.title, _last!.asText),
                ),
              ),
            const SizedBox(height: 8),
          ],
        );
      },
    );
  }

  /// Current crawl environment + Lost flag, mirroring the Exploration tool.
  Widget _envLine(BuildContext context, CrawlState crawl) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          '${_envNames[crawl.envRow! - 1]}'
          '${crawl.lost ? ' — LOST (d6 encounters)' : ''}',
          style: theme.textTheme.bodySmall,
        ),
      ),
    );
  }

  Widget _controls(BuildContext context, MapState s) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
      child: Row(
        children: [
          // Flexible bounds the button's width — see the dungeon _controls note:
          // a bare FilledButton in this Row is measured with infinite width and
          // throws, aborting the tab layout.
          Flexible(
            child: FilledButton.tonal(
              key: const Key('travel'),
              onPressed: _travel,
              child: const Text('Travel'),
            ),
          ),
          const Spacer(),
          IconButton(
            key: const Key('hex-journal'),
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Add map to journal',
            onPressed: s.hexes.isEmpty
                ? null
                : () => _log('Wilderness map', _hexSummary(s)),
          ),
          IconButton(
            key: const Key('hex-reset'),
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Reset hex map',
            onPressed: () => _reset(context),
          ),
        ],
      ),
    );
  }

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          'No hexes yet. Travel reveals the map as you go.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _canvas(MapState s) {
    final scheme = Theme.of(context).colorScheme;
    final revealed = {for (final h in s.hexes) (h.col, h.row)};
    final ghosts = <({int col, int row})>[];
    final seen = <(int, int)>{};
    for (final h in s.hexes) {
      for (final n in hexNeighbors(h.col, h.row)) {
        final key = (n.col, n.row);
        if (!revealed.contains(key) && seen.add(key)) ghosts.add(n);
      }
    }
    final cells = [
      for (final h in s.hexes) (col: h.col, row: h.row),
      ...ghosts,
    ];
    final minCol = cells.map((c) => c.col).reduce(math.min);
    final minRow = cells.map((c) => c.row).reduce(math.min);
    final maxCol = cells.map((c) => c.col).reduce(math.max);
    final maxRow = cells.map((c) => c.row).reduce(math.max);
    final width =
        math.max((maxCol - minCol) * 1.5 * _hexSize + 4 * _hexSize, 360.0);
    final height = math.max(
        (maxRow - minRow + 0.5) * math.sqrt(3) * _hexSize + 4 * _hexSize,
        360.0);
    return InteractiveViewer(
      constrained: false,
      boundaryMargin: const EdgeInsets.all(400),
      minScale: 0.5,
      maxScale: 3,
      child: SizedBox(
        width: width,
        height: height,
        child: GestureDetector(
          // InteractiveViewer delivers tap positions in child coordinates
          // (already inverse-transformed) — no manual matrix math.
          onTapUp: (d) {
            final hit = hexAt(d.localPosition, _hexSize, cells,
                minCol: minCol, minRow: minRow);
            if (hit == null) return;
            // Revealed cells select (for the detail card); faint neighbors reveal.
            if (revealed.contains((hit.col, hit.row))) {
              setState(() {
                _selCol = hit.col;
                _selRow = hit.row;
                _zoom = _HexZoom.region;
              });
              return;
            }
            _manualReveal(hit.col, hit.row);
          },
          child: CustomPaint(
            key: const Key('hex-canvas'),
            size: Size(width, height),
            painter: _HexPainter(
              hexes: s.hexes,
              ghosts: ghosts,
              currentCol: s.currentHexCol,
              currentRow: s.currentHexRow,
              minCol: minCol,
              minRow: minRow,
              envNames: _envNames,
              scheme: scheme,
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _travel() async {
    final s = await ref.read(crawlProvider.future);
    final r = widget.oracle.wildernessTravel(s);
    await ref.read(crawlProvider.notifier).save(r.state);
    if (r.state.envRow != null) {
      await ref.read(mapProvider.notifier).revealHex(
          envRow: r.state.envRow!,
          lost: r.state.lost,
          dice: widget.oracle.dice);
    }
    setState(() => _last = r.result);
  }

  Future<void> _manualReveal(int col, int row) async {
    final names = _envNames;
    final envRow = await showDialog<int>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Environment'),
        children: [
          for (var i = 0; i < names.length; i++)
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, i + 1),
              child: Text(names[i]),
            ),
        ],
      ),
    );
    if (envRow == null) return;
    await ref.read(mapProvider.notifier).revealHexAt(col, row, envRow);
  }

  String _hexSummary(MapState s) {
    final base = '${s.hexes.length} hexes revealed';
    final cur = s.hexes
        .where((h) => h.col == s.currentHexCol && h.row == s.currentHexRow)
        .firstOrNull;
    if (cur == null) return base;
    return '$base — current: ${_envNames[cur.envRow - 1]}';
  }

  Future<void> _log(String title, String body) async {
    await ref.read(journalProvider.notifier).add(title, body);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Added to journal')),
      );
    }
  }

  Future<void> _reset(BuildContext context) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset hex map?'),
        content: const Text('All revealed hexes are removed. '
            'The dungeon map is kept.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await ref.read(mapProvider.notifier).resetHexes();
    if (mounted) setState(() => _last = null);
  }

  // ---- H4a: local-zoom flower ----

  Widget _hexDetailCard(BuildContext context, HexCell h) {
    final theme = Theme.of(context);
    return Card(
      key: const Key('hex-detail-card'),
      margin: const EdgeInsets.fromLTRB(12, 4, 12, 4),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Hex (${h.col}, ${h.row})', style: theme.textTheme.titleSmall),
            if (h.terrain != null)
              Text(h.terrain!, style: theme.textTheme.bodyMedium),
            if (h.site != null)
              Text('Site: ${h.site}', style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (h.terrain != null)
                FilledButton.tonal(
                  key: const Key('local-zoom-in'),
                  onPressed: () => setState(() => _zoom = _HexZoom.flower),
                  child: const Text('Zoom in'),
                ),
            ]),
          ],
        ),
      ),
    );
  }

  Future<void> _localCrawl(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .crawlLocal(h.col, h.row, data, widget.oracle.dice);
  }

  Future<void> _localFull(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .generateLocal(h.col, h.row, data, widget.oracle.dice);
  }

  Widget _flowerView(BuildContext context, HexCell h) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          child: Wrap(
            spacing: 8,
            runSpacing: 8,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              OutlinedButton(
                key: const Key('local-back'),
                onPressed: () => setState(() => _zoom = _HexZoom.region),
                child: const Text('Back'),
              ),
              FilledButton.tonal(
                key: const Key('local-reveal'),
                onPressed: () => _localCrawl(h),
                child: const Text('Reveal sub-hex'),
              ),
              FilledButton.tonal(
                key: const Key('local-fill'),
                onPressed: () => _localFull(h),
                child: const Text('Fill hex'),
              ),
            ],
          ),
        ),
        Expanded(
          child: InteractiveViewer(
            constrained: false,
            boundaryMargin: const EdgeInsets.all(200),
            minScale: 0.5,
            maxScale: 3,
            child: SizedBox(
              width: 360,
              height: 360,
              child: CustomPaint(
                key: const Key('flower-canvas'),
                size: const Size(360, 360),
                painter: _FlowerPainter(
                    centerTerrain: h.terrain ?? '',
                    ring: h.local,
                    scheme: scheme),
              ),
            ),
          ),
        ),
        if (h.local.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxHeight: 96),
            child: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  for (final lc in h.local)
                    Text('• ${lc.terrain}: ${lc.feature}',
                        style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
            ),
          ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _FlowerPainter extends CustomPainter {
  _FlowerPainter(
      {required this.centerTerrain, required this.ring, required this.scheme});
  final String centerTerrain;
  final List<LocalCell> ring;
  final ColorScheme scheme;

  @override
  void paint(Canvas canvas, Size size) {
    final neighbours = hexNeighbors(0, 0); // 6, fixed order = slot order
    final cells = <({int col, int row, String terrain, bool center})>[
      (col: 0, row: 0, terrain: centerTerrain, center: true),
      for (final lc in ring)
        if (lc.slot >= 0 && lc.slot < 6)
          (
            col: neighbours[lc.slot].col,
            row: neighbours[lc.slot].row,
            terrain: lc.terrain,
            center: false
          ),
    ];
    final minCol = cells.map((c) => c.col).reduce(math.min);
    final minRow = cells.map((c) => c.row).reduce(math.min);
    final origin = Offset(size.width / 2, size.height / 2);
    final ref0 = hexCenterFor(0, 0, minCol, minRow, _hexSize);
    for (final cell in cells) {
      final c = origin +
          (hexCenterFor(cell.col, cell.row, minCol, minRow, _hexSize) - ref0);
      final path = _FlowerPainter._hexPath(c, _hexSize - 1);
      final base = _verdantTerrainHues[cell.terrain] ??
          hexcrawlTerrainHues[cell.terrain] ??
          scheme.surfaceContainerHighest;
      canvas.drawPath(
          path,
          Paint()
            ..color = Color.alphaBlend(
                base.withValues(alpha: 0.5), scheme.surfaceContainerHighest));
      canvas.drawPath(
          path,
          Paint()
            ..color = cell.center ? scheme.primary : scheme.outlineVariant
            ..style = PaintingStyle.stroke
            ..strokeWidth = cell.center ? 3 : 1);
      final label = cell.terrain.isEmpty ? '?' : cell.terrain[0].toUpperCase();
      final tp = TextPainter(
        text: TextSpan(
            text: label,
            style: TextStyle(
                color: scheme.onSurface,
                fontSize: 18,
                fontWeight: FontWeight.w600)),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
    }
  }

  static Path _hexPath(Offset center, double size) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i;
      final v = center + Offset(size * math.cos(a), size * math.sin(a));
      i == 0 ? path.moveTo(v.dx, v.dy) : path.lineTo(v.dx, v.dy);
    }
    return path..close();
  }

  @override
  bool shouldRepaint(_FlowerPainter old) =>
      old.centerTerrain != centerTerrain ||
      old.ring != ring ||
      old.scheme != scheme;
}

class _HexPainter extends CustomPainter {
  _HexPainter({
    required this.hexes,
    required this.ghosts,
    required this.currentCol,
    required this.currentRow,
    required this.minCol,
    required this.minRow,
    required this.envNames,
    required this.scheme,
  });

  final List<HexCell> hexes;
  final List<({int col, int row})> ghosts;
  final int? currentCol;
  final int? currentRow;
  final int minCol;
  final int minRow;
  final List<String> envNames;
  final ColorScheme scheme;

  /// Flat-top hexagon: corners at 0, 60, ... 300 degrees from the center.
  static Path _hexPath(Offset center, double size) {
    final path = Path();
    for (var i = 0; i < 6; i++) {
      final a = math.pi / 3 * i;
      final v = center + Offset(size * math.cos(a), size * math.sin(a));
      i == 0 ? path.moveTo(v.dx, v.dy) : path.lineTo(v.dx, v.dy);
    }
    return path..close();
  }

  static void _dashPath(Canvas canvas, Path path, Paint paint) {
    for (final metric in path.computeMetrics()) {
      var d = 0.0;
      while (d < metric.length) {
        canvas.drawPath(
            metric.extractPath(d, math.min(d + 6, metric.length)), paint);
        d += 10;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    // Faint dashed outlines for unrevealed-but-tappable neighbors.
    final ghostPaint = Paint()
      ..color = scheme.outlineVariant
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final g in ghosts) {
      final c = hexCenterFor(g.col, g.row, minCol, minRow, _hexSize);
      _dashPath(canvas, _hexPath(c, _hexSize - 2), ghostPaint);
    }

    for (final h in hexes) {
      final c = hexCenterFor(h.col, h.row, minCol, minRow, _hexSize);
      final path = _hexPath(c, _hexSize - 1);
      final hasTerrain = h.terrain != null;
      final baseHue = hasTerrain
          ? (_verdantTerrainHues[h.terrain] ??
              hexcrawlTerrainHues[h.terrain] ??
              scheme.surfaceContainerHighest)
          : _envHues[h.envRow - 1];
      final isCurrent = h.col == currentCol && h.row == currentRow;
      // Uniform 0.5 alpha for every hex (current is marked by its primary
      // border below) — keeps Juice-hex rendering identical to before.
      final fill = Color.alphaBlend(
          baseHue.withValues(alpha: 0.5), scheme.surfaceContainerHighest);
      canvas.drawPath(path, Paint()..color = fill);
      canvas.drawPath(
          path,
          Paint()
            ..color = scheme.outlineVariant
            ..style = PaintingStyle.stroke
            ..strokeWidth = 1);
      if (isCurrent) {
        canvas.drawPath(
            path,
            Paint()
              ..color = scheme.primary
              ..style = PaintingStyle.stroke
              ..strokeWidth = 3);
      }
      if (h.site != null) {
        canvas.drawCircle(c + const Offset(0, -_hexSize * 0.45), 3,
            Paint()..color = scheme.primary);
      }
      // Only the first letter is drawn (single-glyph hex label), so the bare
      // key is enough — no need to title-case the whole terrain name.
      final name = hasTerrain ? h.terrain! : envNames[h.envRow - 1];
      final tp = TextPainter(
        text: TextSpan(
          text: name.isEmpty ? '?' : name[0].toUpperCase(),
          style: TextStyle(
            color: scheme.onSurface,
            fontSize: 18,
            fontWeight: FontWeight.w600,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, c - Offset(tp.width / 2, tp.height / 2));
      if (h.pois.isNotEmpty) {
        final badge = TextPainter(
          text: TextSpan(
            text: '★${h.pois.length}',
            style: TextStyle(color: scheme.tertiary, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        badge.paint(canvas, c + Offset(-badge.width / 2, 10));
      }
      if (h.lost) {
        final badge = TextPainter(
          text: TextSpan(
            text: '!',
            style: TextStyle(
              color: scheme.error,
              fontSize: 14,
              fontWeight: FontWeight.w800,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        badge.paint(
            canvas,
            c +
                Offset(_hexSize * 0.35 - badge.width / 2,
                    -_hexSize * 0.6 - badge.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_HexPainter old) =>
      old.hexes != hexes ||
      old.ghosts != ghosts ||
      old.currentCol != currentCol ||
      old.currentRow != currentRow ||
      old.minCol != minCol ||
      old.minRow != minRow ||
      old.scheme != scheme;
}
