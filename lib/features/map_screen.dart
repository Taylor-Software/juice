import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/dungeon/footprint.dart';
import '../engine/dungeon/generator.dart' show DungeonBranch;
import '../engine/dungeon/organic.dart';
import '../engine/map_builder.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../shared/ai_badge.dart';
import '../shared/destination.dart';
import '../shared/result_card.dart';
import '../shared/entry_preview.dart';
import 'sketch_open.dart';
import '../shared/shell_route.dart';
import '../state/blob_store.dart';
import '../state/interpreter.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'inspire.dart';
import 'flesh_out_review.dart';
import 'map_snapshot.dart';

/// Grid cell size for the dungeon canvas, in logical pixels.
const _cell = 56.0;

/// Fraction of the pane the floating detail overlay may occupy before it
/// scrolls internally. The map keeps the rest — the overlay can crowd the
/// canvas but never swallow it.
const _kDetailMaxFraction = 0.45;

/// Top inset applied to a canvas's PANNABLE CONTENT (not to the canvas widget,
/// which stays full-bleed) so map content doesn't start life under the floating
/// chrome bar — a fresh dungeon's entrance sits at the grid origin, i.e.
/// exactly where the bar is. Roughly the collapsed bar's height; the content
/// still pans up under the bar when the reader wants that space back.
///
/// Applied OUTSIDE each canvas's tap target, so hit-test coordinates stay
/// canvas-relative and the painter/[roomIdAt] origin contract is untouched.
const _kChromeInset = 56.0;

/// The shared pannable viewport every map canvas sits in: same zoom limits
/// everywhere, and one place that applies [_kChromeInset].
Widget _mapViewport({required Widget child, double boundary = 400}) =>
    InteractiveViewer(
      constrained: false,
      boundaryMargin: EdgeInsets.all(boundary),
      minScale: 0.5,
      maxScale: 3,
      child: Padding(
        padding: const EdgeInsets.only(top: _kChromeInset),
        child: child,
      ),
    );

/// Full-bleed map scaffold: the canvas owns the whole pane and the chrome
/// floats over it.
///
/// Both map panes used to stack their controls, chips, level headers and
/// detail cards as siblings in a `Column` around `Expanded(canvas)` — so the
/// map, the actual content, only ever got what was left over from both ends.
/// On a phone that was well under half the pane and the maps were unreadable.
///
/// Here [canvas] fills the pane. Over it float a compact bar carrying the
/// pane's [primary] verbs (one tap, never buried) plus a Tools toggle that
/// folds away the [tools] — the secondary controls that used to be permanent —
/// and an optional [detail] overlay pinned to the bottom, height-capped and
/// internally scrollable.
class MapChrome extends StatefulWidget {
  const MapChrome({
    super.key,
    required this.canvas,
    required this.primary,
    this.tools = const [],
    this.detail,
  });

  final Widget canvas;

  /// Always-visible actions — the pane's main verbs (Travel, New room, …).
  final List<Widget> primary;

  /// Secondary controls, hidden behind the Tools toggle. Omit the toggle
  /// entirely when empty.
  final List<Widget> tools;

  /// Selection/result card floating over the bottom of the canvas.
  final Widget? detail;

  @override
  State<MapChrome> createState() => _MapChromeState();
}

class _MapChromeState extends State<MapChrome> {
  bool _toolsOpen = false;

  @override
  Widget build(BuildContext context) {
    final hasTools = widget.tools.isNotEmpty;
    return LayoutBuilder(
      builder: (context, constraints) {
        final detailCap = constraints.maxHeight.isFinite
            ? constraints.maxHeight * _kDetailMaxFraction
            : double.infinity;
        return Stack(
          children: [
            Positioned.fill(child: widget.canvas),
            Positioned(
              top: 8,
              left: 8,
              right: 8,
              child: _floating(
                // The bar is bottom-unbounded in this Stack, so a wide tool set
                // (hexcrawl's climate chips + generation controls wrap several
                // rows deep) would overflow and be silently clipped — i.e.
                // unreachable. Cap it and let it scroll instead.
                maxHeight: detailCap,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Expanded (not Flexible + Spacer): both of those
                        // default to flex: 1, so the Row would split its width
                        // 50/50 and strand the toggle mid-bar. Expanded also
                        // bounds the Wrap — a bare FilledButton as a non-flex
                        // Row child is measured against an unbounded main axis
                        // and throws "BoxConstraints forces an infinite
                        // width", aborting the whole tab's layout. Callers pin
                        // a finite minimumSize so buttons sit side by side.
                        Expanded(
                          child: Wrap(
                            spacing: 8,
                            runSpacing: 4,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: widget.primary,
                          ),
                        ),
                        if (hasTools)
                          IconButton(
                            key: const Key('map-tools-toggle'),
                            visualDensity: VisualDensity.compact,
                            icon: Icon(_toolsOpen
                                ? Icons.expand_less
                                : Icons.tune_outlined),
                            tooltip: _toolsOpen ? 'Hide tools' : 'Tools',
                            onPressed: () =>
                                setState(() => _toolsOpen = !_toolsOpen),
                          ),
                      ],
                    ),
                    if (hasTools && _toolsOpen)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 4,
                          crossAxisAlignment: WrapCrossAlignment.center,
                          children: widget.tools,
                        ),
                      ),
                  ],
                ),
              ),
            ),
            // No _floating wrapper here: the detail/result cards are already
            // Cards, i.e. they bring their own opaque surface. Wrapping them
            // would nest a card in a card and frame it in an empty bar.
            if (widget.detail case final d?)
              Positioned(
                left: 8,
                right: 8,
                bottom: 8,
                child: ConstrainedBox(
                  constraints: BoxConstraints(maxHeight: detailCap),
                  child: SingleChildScrollView(child: d),
                ),
              ),
          ],
        );
      },
    );
  }

  /// Chrome floats over a painted canvas, so it needs its own opaque surface
  /// to stay legible against whatever it covers. [maxHeight] caps it against
  /// the pane and scrolls the overflow — chrome may crowd the map, never
  /// swallow it, and never silently clip itself out of reach.
  Widget _floating({
    required Widget child,
    required double maxHeight,
    EdgeInsets padding = const EdgeInsets.fromLTRB(8, 4, 4, 4),
  }) =>
      Material(
        elevation: 2,
        borderRadius: BorderRadius.circular(12),
        clipBehavior: Clip.antiAlias,
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: maxHeight),
          child: SingleChildScrollView(
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
}

/// Inset of a room's rounded rect inside its cell.
const _roomInset = 6.0;

/// Pixel rect of a room's cell content. The canvas origin is offset so the
/// minimum grid coordinates land at pad = cell/2 from the top-left; painter
/// and [roomIdAt] share this so they can't drift.
Rect roomRectFor(DungeonRoom r, int minX, int minY, double cell) =>
    cellRectFor(r, (0, 0), minX, minY, cell);

/// Pixel rect of one footprint cell of [r] (offset [c] from the room anchor)
/// in canvas space. Same origin contract as [roomRectFor].
Rect cellRectFor(DungeonRoom r, (int, int) c, int minX, int minY, double cell) {
  final pad = cell / 2;
  final left = (r.x + c.$1 - minX) * cell + pad;
  final top = (r.y + c.$2 - minY) * cell + pad;
  return Rect.fromLTWH(left + _roomInset, top + _roomInset,
      cell - 2 * _roomInset, cell - 2 * _roomInset);
}

/// Center of one footprint cell of [r], in canvas space.
Offset cellCenterFor(
        DungeonRoom r, (int, int) c, int minX, int minY, double cell) =>
    cellRectFor(r, c, minX, minY, cell).center;

/// Min grid x over every footprint cell (multi-cell rooms extend past r.x).
int roomsMinX(List<DungeonRoom> rooms) =>
    rooms.expand((r) => r.footprint.map((c) => r.x + c.$1)).reduce(math.min);

/// Min grid y over every footprint cell.
int roomsMinY(List<DungeonRoom> rooms) =>
    rooms.expand((r) => r.footprint.map((c) => r.y + c.$2)).reduce(math.min);

/// Pure hit-test: id of the room whose footprint contains [local], else null.
String? roomIdAt(List<DungeonRoom> rooms, Offset local, double cell) {
  if (rooms.isEmpty) return null;
  final minX = roomsMinX(rooms);
  final minY = roomsMinY(rooms);
  for (final r in rooms) {
    for (final c in r.footprint) {
      if (cellRectFor(r, c, minX, minY, cell).contains(local)) return r.id;
    }
  }
  return null;
}

/// Center of a door marker: mid-point of the [door] edge on its cell.
Offset doorMarkerCenter(
    DungeonRoom r, DoorEdge door, int minX, int minY, double cell) {
  final rect = cellRectFor(r, door.cell, minX, minY, cell);
  return switch (door.side) {
    Side.n => rect.topCenter,
    Side.s => rect.bottomCenter,
    Side.e => rect.centerRight,
    Side.w => rect.centerLeft,
  };
}

/// A hit on a room's open door marker.
class DoorHit {
  const DoorHit(this.roomId, this.door);
  final String roomId;
  final DoorEdge door;
}

/// Nearest OPEN door edge within a third of a cell of [local], else null.
/// Locked/typed doors are inert (P1 has no key mechanic).
DoorHit? doorEdgeAt(List<DungeonRoom> rooms, Offset local, double cell) {
  if (rooms.isEmpty) return null;
  final minX = roomsMinX(rooms);
  final minY = roomsMinY(rooms);
  for (final r in rooms) {
    for (final d in r.doors) {
      if (d.kind == DoorKind.open &&
          (doorMarkerCenter(r, d, minX, minY, cell) - local).distance <
              cell / 3) {
        return DoorHit(r.id, d);
      }
    }
  }
  return null;
}

/// Stamps the active-encounter marker (a material icon) centered on [center].
/// Used by both the dungeon and hex painters so the pin reads identically.
void paintEncounterPin(Canvas canvas, Offset center, Color color) {
  const icon = Icons.local_fire_department;
  final tp = TextPainter(
    text: TextSpan(
      text: String.fromCharCode(icon.codePoint),
      style: TextStyle(
        fontSize: 18,
        fontFamily: icon.fontFamily,
        package: icon.fontPackage,
        color: color,
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
}

/// Link/unlink toggle for pinning the active encounter to a map cell. Shared by
/// the dungeon room and hex detail cards. Disabled while the encounter is still
/// loading ([enabled] false) so the tap can't null-deref.
Widget encounterToggleButton({
  required Key key,
  required bool linked,
  required bool enabled,
  required VoidCallback onLink,
  required VoidCallback onUnlink,
}) =>
    OutlinedButton.icon(
      key: key,
      onPressed: !enabled ? null : (linked ? onUnlink : onLink),
      icon: Icon(
        linked ? Icons.local_fire_department : Icons.add_location_alt_outlined,
        size: 18,
      ),
      label: Text(linked ? 'Encounter here ✓' : 'Set encounter here'),
    );

/// "Go to encounter" jump shown on the detail card of the cell the active
/// encounter is pinned to ([show]); navigates to Track › Encounter. Renders
/// nothing when this cell isn't the encounter location.
Widget encounterJumpButton({
  required Key key,
  required bool show,
  required VoidCallback onJump,
}) =>
    show
        ? OutlinedButton.icon(
            key: key,
            icon: const Icon(Icons.my_location, size: 18),
            label: const Text('Go to encounter'),
            onPressed: onJump,
          )
        : const SizedBox.shrink();

/// "What happened here" backlink chip: shows a count of journal entries
/// logged at this place, tapping opens a bottom sheet listing them. Renders
/// nothing when there are none. Shared by the hex and dungeon-room detail
/// cards (mirrors the character-card `mentions-` chip in tracker_screen.dart).
Widget locationEntriesChip({
  required BuildContext context,
  required WidgetRef ref,
  required Key key,
  required List<JournalEntry> entries,
  required String placeLabel,
}) {
  if (entries.isEmpty) return const SizedBox.shrink();
  return ActionChip(
    key: key,
    avatar: const Icon(Icons.link, size: 16),
    label: Text('${entries.length} entr${entries.length == 1 ? 'y' : 'ies'}'),
    visualDensity: VisualDensity.compact,
    onPressed: () => _showLocationEntries(context, ref, placeLabel, entries),
  );
}

/// "Places here" chip: the tracked [Place]s pinned to this map cell. Tapping
/// jumps to the Places tracker. Renders nothing when there are none. Shared by
/// the hex + dungeon-room detail cards (companion to [locationEntriesChip]).
Widget placesHereChip({
  required WidgetRef ref,
  required Key key,
  required LocationRef loc,
}) {
  final places = placesAtLocation(
      ref.watch(placesProvider).valueOrNull ?? const <Place>[], loc);
  if (places.isEmpty) return const SizedBox.shrink();
  return ActionChip(
    key: key,
    avatar: const Icon(Icons.place_outlined, size: 16),
    label: Text(places.length == 1
        ? places.first.name.isEmpty
            ? '1 place'
            : places.first.name
        : '${places.length} places'),
    visualDensity: VisualDensity.compact,
    onPressed: () => ref
        .read(shellRouteProvider.notifier)
        .goTo(Destination.track, subtab: 'places'),
  );
}

Future<void> _showLocationEntries(BuildContext context, WidgetRef ref,
    String placeLabel, List<JournalEntry> entries) {
  return showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 8),
        children: [
          ListTile(
            title: Text(
                '$placeLabel — ${entries.length} journal entr'
                '${entries.length == 1 ? 'y' : 'ies'}',
                style: Theme.of(context).textTheme.titleMedium),
          ),
          for (final e in entries)
            ListTile(
              key: Key('loc-entry-row-${e.id}'),
              dense: true,
              leading: const Icon(Icons.notes_outlined),
              title: Text(
                e.title.isEmpty ? e.body : e.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              subtitle: e.title.isEmpty
                  ? null
                  : Text(e.body, maxLines: 2, overflow: TextOverflow.ellipsis),
              onTap: () async {
                final navigated = await showEntryPreview(sheetContext, ref, e);
                // Opening the journal closes the backlink sheet under the
                // now-dismissed preview.
                if (navigated && sheetContext.mounted) {
                  Navigator.of(sheetContext).pop();
                }
              },
            ),
        ],
      ),
    ),
  );
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
  final GlobalKey _dungeonSnapKey = GlobalKey();
  int _hcDungeonCount = 8; // hexcrawl "Generate dungeon" room count

  @override
  void initState() {
    super.initState();
    // Preselect the PlayContext spine's active room (e.g. arriving via a
    // journal place-chip) if it isn't already the map's current room.
    final roomId =
        ref.read(playContextProvider).valueOrNull?.activeLocation?.roomId;
    final current = ref.read(mapProvider).valueOrNull?.currentRoomId;
    if (roomId != null && roomId != current) {
      ref.read(mapProvider.notifier).selectRoom(roomId);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Whenever the active level's current room changes (tap-select,
    // explore-door, new-room, classic-enter/descend all funnel through
    // MapState.currentRoomId), point the PlayContext spine at it — "where
    // the party is" for auto-stamping new journal entries.
    ref.listen(mapProvider, (prev, next) {
      final id = next.valueOrNull?.currentRoomId;
      if (id != null && id != prev?.valueOrNull?.currentRoomId) {
        ref
            .read(playContextProvider.notifier)
            .setActiveLocation(LocationRef(roomId: id));
      }
    });
    final async = ref.watch(mapProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (s) {
        final selected = s.currentRoomId == null
            ? null
            : s.rooms.where((r) => r.id == s.currentRoomId).firstOrNull;
        return MapChrome(
          canvas: s.rooms.isEmpty ? _empty(context) : _canvas(s),
          primary: _primary(context, s),
          tools: _tools(context, s),
          detail: selected == null && _last == null
              ? null
              : Column(
                  mainAxisSize: MainAxisSize.min,
                  // Stretch: a Column centers by default, which would float
                  // the cards at intrinsic width in the middle of the pane.
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (selected != null) _detailCard(context, selected),
                    if (_last != null)
                      Padding(
                        padding: const EdgeInsets.all(8),
                        child: ResultCard(
                          result: _last!,
                          onInspire: ref.watch(interpretReadyProvider)
                              ? () => inspireGenResult(context, ref, _last!)
                              : null,
                          onLog: () => _log(_last!.title, _last!.asText),
                        ),
                      ),
                  ],
                ),
        );
      },
    );
  }

  /// Always-visible: the pane's main verb.
  List<Widget> _primary(BuildContext context, MapState s) {
    final classic = _classicOn();
    // A themed FilledButton's minimumSize width is infinity, so it must pin a
    // finite one to sit in the chrome's Wrap.
    final style = FilledButton.styleFrom(minimumSize: const Size(0, 40));
    if (classic && s.rooms.isEmpty) {
      return [
        FilledButton.tonal(
          key: const Key('classic-enter'),
          style: style,
          onPressed: _enterDungeon,
          child: const Text('Enter the dungeon'),
        ),
        FilledButton.tonalIcon(
          key: const Key('classic-enter-cave'),
          style: style,
          onPressed: _enterCave,
          icon: const Icon(Icons.landscape_outlined),
          label: const Text('Enter a cave'),
        ),
      ];
    }
    if (!classic) {
      return [
        FilledButton.tonal(
          key: const Key('new-room'),
          style: style,
          onPressed: _newRoom,
          child: const Text('New room'),
        ),
      ];
    }
    // A classic dungeon in progress has no button here (rooms grow by tapping
    // doors), so the always-visible slot goes to "which level am I on" — depth
    // is identity and navigation, not a tool to fold away.
    if (s.levels.isNotEmpty) return [_levelHeader(context, s)];
    return const [];
  }

  /// Folded behind the Tools toggle: everything that used to sit permanently
  /// between the top of the pane and the canvas.
  List<Widget> _tools(BuildContext context, MapState s) => [
        // Several dungeons can live on one world map — switch or add.
        for (final d in s.dungeons)
          ChoiceChip(
            key: Key('dungeon-site-chip-${d.id}'),
            label: Text(d.name),
            selected: d.id == s.activeDungeon?.id,
            onSelected: (_) =>
                ref.read(mapProvider.notifier).switchDungeon(d.id),
          ),
        if (s.dungeons.isNotEmpty)
          ActionChip(
            key: const Key('dungeon-new-site'),
            avatar: const Icon(Icons.add, size: 16),
            label: const Text('New dungeon'),
            onPressed: () => ref.read(mapProvider.notifier).addDungeon(),
          ),
        // Map-layer hierarchy: when the dungeon is anchored to a world hex,
        // offer the "up" hop back to it.
        if (s.hasAnchor)
          ActionChip(
            key: const Key('dungeon-up-world'),
            avatar: const Icon(Icons.arrow_upward, size: 16),
            label: Text('World: Hex (${s.anchorHexCol}, ${s.anchorHexRow})'),
            onPressed: () async {
              await ref.read(playContextProvider.notifier).setActiveLocation(
                  LocationRef(hexCol: s.anchorHexCol, hexRow: s.anchorHexRow));
              ref
                  .read(shellRouteProvider.notifier)
                  .goTo(Destination.map, subtab: 'world');
            },
          ),
        if (_hexcrawlOn()) _hexcrawlDungeonControls(context),
        IconButton(
          key: const Key('dungeon-journal'),
          icon: const Icon(Icons.bookmark_add_outlined),
          tooltip: 'Add map to journal',
          onPressed: s.rooms.isEmpty
              ? null
              : () => _log('Dungeon map', _dungeonSummary(s)),
        ),
        if (ref.watch(blobStoreAvailableProvider))
          IconButton(
            key: const Key('dungeon-snapshot'),
            icon: const Icon(Icons.draw_outlined),
            tooltip: 'Annotate in journal',
            onPressed: () =>
                snapshotMapToJournal(context, ref, _dungeonSnapKey),
          ),
        IconButton(
          key: const Key('dungeon-reset'),
          icon: const Icon(Icons.delete_sweep_outlined),
          tooltip: 'Reset dungeon',
          onPressed: () => _reset(context),
        ),
      ];

  Widget _empty(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          _classicOn()
              ? 'No dungeon yet. Enter the dungeon rolls the entrance, then '
                  'tap an opening to explore room by room.'
              : 'No rooms yet. New room rolls the dungeon oracle and maps it.',
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyLarge
              ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ),
    );
  }

  Widget _canvas(MapState s) {
    final scheme = Theme.of(context).colorScheme;
    // Bounds range over every footprint cell (multi-cell rooms extend past
    // their anchor), so classic shapes never paint outside the canvas.
    final cellsX =
        s.rooms.expand((r) => r.footprint.map((c) => r.x + c.$1)).toList();
    final cellsY =
        s.rooms.expand((r) => r.footprint.map((c) => r.y + c.$2)).toList();
    final minX = cellsX.reduce(math.min);
    final minY = cellsY.reduce(math.min);
    final maxX = cellsX.reduce(math.max);
    final maxY = cellsY.reduce(math.max);
    final width = math.max((maxX - minX + 1) * _cell + _cell, 360.0);
    final height = math.max((maxY - minY + 1) * _cell + _cell, 360.0);
    return _mapViewport(
      child: SizedBox(
        width: width,
        height: height,
        child: GestureDetector(
          // InteractiveViewer delivers tap positions in child coordinates
          // (already inverse-transformed) — no manual matrix math.
          onTapUp: (d) {
            // Classic mode: an open-door tap explores through that door;
            // it wins over room selection (markers sit on room edges).
            if (_classicOn()) {
              final hit = doorEdgeAt(s.rooms, d.localPosition, _cell);
              if (hit != null) {
                _exploreDoor(s, hit);
                return;
              }
            }
            final id = roomIdAt(s.rooms, d.localPosition, _cell);
            if (id != null) ref.read(mapProvider.notifier).selectRoom(id);
          },
          child: RepaintBoundary(
            key: _dungeonSnapKey,
            child: CustomPaint(
              key: const Key('dungeon-canvas'),
              size: Size(width, height),
              painter: _DungeonPainter(
                rooms: s.rooms,
                corridors: s.corridors,
                currentRoomId: s.currentRoomId,
                scheme: scheme,
                encounterRoomId: ref
                    .watch(encounterProvider)
                    .valueOrNull
                    ?.locationRef
                    ?.roomId,
              ),
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

  bool _classicOn() =>
      (ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
              kAllSystems)
          .contains('classic-dungeon');

  /// Enter a fresh classic dungeon: the notifier rolls the entrance
  /// surroundings + level type and places the entrance room.
  Future<void> _enterDungeon() async {
    // Await the asset (a cold read of an unwatched FutureProvider is
    // AsyncLoading on first tap — the repo's Run-screen gotcha).
    final tables = await ref.read(dungeonDataProvider.future);
    await ref.read(mapProvider.notifier).enterClassicDungeon(
        branch: DungeonBranch.dungeon,
        tables: tables,
        dice: widget.oracle.dice);
  }

  /// Enter a fresh classic cave (D-branch) the same way.
  Future<void> _enterCave() async {
    final tables = await ref.read(dungeonDataProvider.future);
    await ref.read(mapProvider.notifier).enterClassicDungeon(
        branch: DungeonBranch.cave, tables: tables, dice: widget.oracle.dice);
  }

  /// Follow the selected level-transition room down/up a level.
  Future<void> _descend(DungeonRoom room) async {
    final tables = await ref.read(dungeonDataProvider.future);
    await ref
        .read(mapProvider.notifier)
        .descendFrom(room.id, tables: tables, dice: widget.oracle.dice);
  }

  /// Active-level readout (depth · type · stone) + a level switcher once
  /// more than one level exists.
  Widget _levelHeader(BuildContext context, MapState s) {
    final theme = Theme.of(context);
    final lvl = s.levels[s.activeLevel.clamp(0, s.levels.length - 1)];
    // Join only the non-empty parts — a legacy-lifted level has no typeName,
    // and "Depth 1 ·" with a dangling separator reads broken.
    final label = [
      'Depth ${lvl.depth}',
      if (lvl.typeName.isNotEmpty) lvl.typeName,
      if (lvl.stone.isNotEmpty) lvl.stone,
    ].join(' · ');
    // Layout (padding/alignment) belongs to the chrome bar that hosts this.
    return Column(
      key: const Key('classic-level-header'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: theme.textTheme.labelLarge
                ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
        if (s.levels.length > 1)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Wrap(
              spacing: 6,
              runSpacing: 4,
              children: [
                for (final l in s.levels)
                  ChoiceChip(
                    key: Key('classic-level-chip-${l.depth}'),
                    label: Text('D${l.depth}'),
                    visualDensity: VisualDensity.compact,
                    selected: l.depth == lvl.depth,
                    onSelected: (_) =>
                        ref.read(mapProvider.notifier).switchLevel(l.depth),
                  ),
              ],
            ),
          ),
      ],
    );
  }

  /// Explore through an open door: generate + place the next room mated there.
  Future<void> _exploreDoor(MapState s, DoorHit hit) async {
    final tables = await ref.read(dungeonDataProvider.future);
    final room = s.rooms.firstWhere((r) => r.id == hit.roomId);
    final world = (
      cell: (room.x + hit.door.cell.$1, room.y + hit.door.cell.$2),
      side: hit.door.side,
    );
    final ok = await ref.read(mapProvider.notifier).addClassicRoom(
        fromRoomId: hit.roomId,
        doorEdge: world,
        tables: tables,
        dice: widget.oracle.dice);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('No room fits that way — try another exit')));
    }
  }

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
            if (room.crossTo != null) ...[
              const SizedBox(height: 4),
              Text(
                'Openings lead to the '
                '${room.crossTo == 'cave' ? 'caves' : 'dungeon'}',
                style:
                    const TextStyle(fontSize: 12, fontStyle: FontStyle.italic),
              ),
            ],
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
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                OutlinedButton(
                  key: const Key('linger'),
                  onPressed: () => _linger(room),
                  child: const Text('Linger'),
                ),
                if (room.levelDelta != 0)
                  FilledButton.tonalIcon(
                    key: const Key('classic-descend'),
                    // Finite minimumSize: the theme's full-width default would
                    // put this on its own Wrap line (loop_bar pattern).
                    style:
                        FilledButton.styleFrom(minimumSize: const Size(0, 40)),
                    onPressed: () => _descend(room),
                    icon: const Icon(Icons.stairs_outlined),
                    label: Text(room.levelDelta < 0 ? 'Descend' : 'Ascend'),
                  ),
                if (ref.watch(aiReadyProvider))
                  OutlinedButton.icon(
                    key: const Key('flesh-out-room'),
                    onPressed: () => _fleshOutRoom(room),
                    icon: const AiBadge(),
                    label: const Text('Flesh out'),
                  ),
                Builder(builder: (context) {
                  final enc = ref.watch(encounterProvider);
                  return encounterToggleButton(
                    key: const Key('dungeon-encounter-toggle'),
                    linked: enc.valueOrNull?.locationRef?.roomId == room.id,
                    enabled: enc.hasValue,
                    onLink: () => ref
                        .read(encounterProvider.notifier)
                        .setLocation(LocationRef(roomId: room.id)),
                    onUnlink: () =>
                        ref.read(encounterProvider.notifier).setLocation(null),
                  );
                }),
                Builder(builder: (context) {
                  final enc = ref.watch(encounterProvider);
                  return encounterJumpButton(
                    key: const Key('dungeon-encounter-goto'),
                    show: enc.valueOrNull?.locationRef?.roomId == room.id,
                    onJump: () => ref
                        .read(shellRouteProvider.notifier)
                        .goTo(Destination.track, subtab: 'encounter'),
                  );
                }),
                Builder(builder: (context) {
                  final all = ref.watch(journalProvider).valueOrNull ??
                      const <JournalEntry>[];
                  final entries =
                      entriesAtLocation(all, LocationRef(roomId: room.id));
                  return locationEntriesChip(
                    context: context,
                    ref: ref,
                    key: Key('loc-entries-${room.id}'),
                    entries: entries,
                    placeLabel: room.title,
                  );
                }),
                Builder(builder: (context) {
                  return placesHereChip(
                    ref: ref,
                    key: Key('loc-places-${room.id}'),
                    loc: LocationRef(roomId: room.id),
                  );
                }),
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

  Future<void> _fleshOutRoom(DungeonRoom room) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: 'location', name: room.title, existingDetail: room.detail);
    final String detail;
    try {
      detail = await ref.read(interpreterServiceProvider).fleshOut(seed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Flesh out failed: $e')));
      }
      return;
    }
    if (!mounted) return;
    if (await showFleshOutReview(context, detail) != true) return;
    await ref.read(mapProvider.notifier).appendRoomDetail(room.id, detail);
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
    // A classic dungeon's factions belong to the mapped dungeon — clear them
    // with it (harmless no-op for the base pane).
    await ref.read(dungeonFactionsProvider.notifier).reset();
    if (mounted) setState(() => _last = null);
  }
}

class _DungeonPainter extends CustomPainter {
  _DungeonPainter({
    required this.rooms,
    required this.corridors,
    required this.currentRoomId,
    required this.scheme,
    this.encounterRoomId,
  })  : _minX = rooms.isEmpty ? 0 : roomsMinX(rooms),
        _minY = rooms.isEmpty ? 0 : roomsMinY(rooms);

  final List<DungeonRoom> rooms;
  final List<List<String>> corridors;
  final String? currentRoomId;
  final ColorScheme scheme;
  final String? encounterRoomId;
  final int _minX;
  final int _minY;

  @override
  void paint(Canvas canvas, Size size) {
    if (rooms.isEmpty) return;
    final byId = {for (final r in rooms) r.id: r};

    // Corridors first, under the rooms.
    final line = Paint()
      ..color = scheme.outlineVariant
      ..strokeWidth = 2;
    for (final c in corridors) {
      final a = byId[c[0]];
      final b = byId[c[1]];
      if (a == null || b == null) continue;
      canvas.drawLine(roomRectFor(a, _minX, _minY, _cell).center,
          roomRectFor(b, _minX, _minY, _cell).center, line);
    }

    for (final r in rooms) {
      final rect = roomRectFor(r, _minX, _minY, _cell);
      final isCurrent = r.id == currentRoomId;
      final fill = Paint()
        ..color = isCurrent
            ? scheme.primaryContainer
            : scheme.surfaceContainerHighest;
      // Cave/tunnel rooms paint as an organic wobbly blob around the fused
      // footprint instead of the P1 rounded-rect look; dungeon rooms
      // (corridor/chamber/legacy null) keep the P1 code path verbatim.
      if (r.roomType == 'tunnel' || r.roomType == 'cave') {
        final pts = organicPerimeter(r.footprint,
            seed: r.id.hashCode, cellSize: _cell, jitter: _cell * 0.12);
        final origin = Offset((r.x - _minX) * _cell + _cell / 2,
            (r.y - _minY) * _cell + _cell / 2);
        final path = Path()
          ..moveTo(pts.first.$1 + origin.dx, pts.first.$2 + origin.dy);
        for (final p in pts.skip(1)) {
          path.lineTo(p.$1 + origin.dx, p.$2 + origin.dy);
        }
        path.close();
        final caveFill = Paint()
          ..color = Color.lerp(scheme.surfaceContainerHighest,
              scheme.tertiaryContainer, isCurrent ? 0.9 : 0.5)!;
        canvas.drawPath(path, caveFill);
        if (isCurrent) {
          canvas.drawPath(
              path,
              Paint()
                ..color = scheme.primary
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
        } else {
          canvas.drawPath(
              path,
              Paint()
                ..color = scheme.outlineVariant
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
        }
      } else if (r.footprint.length == 1) {
        // Multi-cell footprints draw as the union of their cell rects
        // (slightly over-inset seams bridged by a full-bleed body per cell);
        // a legacy single-cell room keeps its rounded-square look exactly.
        final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(8));
        canvas.drawRRect(rrect, fill);
        if (isCurrent) {
          canvas.drawRRect(
              rrect,
              Paint()
                ..color = scheme.primary
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
        }
      } else {
        final stroke = Paint()
          ..color = isCurrent ? scheme.primary : scheme.outlineVariant
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2;
        for (final c in r.footprint) {
          final cr = cellRectFor(r, c, _minX, _minY, _cell);
          // bleed each cell to the grid line so adjacent cells fuse
          canvas.drawRect(cr.inflate(_roomInset - 1), fill);
        }
        for (final c in r.footprint) {
          final cr = cellRectFor(r, c, _minX, _minY, _cell).inflate(
            _roomInset - 1,
          );
          // draw only the outline edges that face out of the footprint
          final cells = {for (final fc in r.footprint) fc};
          void edge(bool exposed, Offset a, Offset b) {
            if (exposed) canvas.drawLine(a, b, stroke);
          }

          edge(!cells.contains((c.$1, c.$2 - 1)), cr.topLeft, cr.topRight);
          edge(
              !cells.contains((c.$1, c.$2 + 1)), cr.bottomLeft, cr.bottomRight);
          edge(!cells.contains((c.$1 + 1, c.$2)), cr.topRight, cr.bottomRight);
          edge(!cells.contains((c.$1 - 1, c.$2)), cr.topLeft, cr.bottomLeft);
        }
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
      // Door glyphs: open = filled triangle pointing out, door = short bar,
      // locked = heavier crossed bar. Drawn on every DoorEdge.
      for (final d in r.doors) {
        _paintDoor(canvas, doorMarkerCenter(r, d, _minX, _minY, _cell), d,
            isCurrent ? scheme.primary : scheme.onSurfaceVariant);
      }
      if (r.id == encounterRoomId) {
        paintEncounterPin(
            canvas, Offset(rect.right - 7, rect.top + 7), scheme.error);
      }
    }
  }

  /// One door marker at [center]: open = outward triangle, door = bar across
  /// the edge, locked = bar + cross-tick.
  void _paintDoor(Canvas canvas, Offset center, DoorEdge d, Color color) {
    final horizontal = d.side == Side.n || d.side == Side.s;
    switch (d.kind) {
      case DoorKind.open:
        final dir = switch (d.side) {
          Side.n => const Offset(0, -1),
          Side.s => const Offset(0, 1),
          Side.e => const Offset(1, 0),
          Side.w => const Offset(-1, 0),
        };
        final tip = center + dir * 6;
        final left =
            center + (horizontal ? const Offset(-5, 0) : const Offset(0, -5));
        final right =
            center + (horizontal ? const Offset(5, 0) : const Offset(0, 5));
        final path = Path()
          ..moveTo(tip.dx, tip.dy)
          ..lineTo(left.dx, left.dy)
          ..lineTo(right.dx, right.dy)
          ..close();
        canvas.drawPath(path, Paint()..color = color);
      case DoorKind.door:
      case DoorKind.locked:
        final along = horizontal ? const Offset(6, 0) : const Offset(0, 6);
        final bar = Paint()
          ..color = color
          ..strokeWidth = d.kind == DoorKind.locked ? 4 : 3
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(center - along, center + along, bar);
        if (d.kind == DoorKind.locked) {
          final across = horizontal ? const Offset(0, 4) : const Offset(4, 0);
          canvas.drawLine(center - across, center + across, bar);
        }
    }
  }

  @override
  bool shouldRepaint(_DungeonPainter old) =>
      old.rooms != rooms ||
      old.corridors != corridors ||
      old.currentRoomId != currentRoomId ||
      old.encounterRoomId != encounterRoomId ||
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

enum _HexZoom { region, flower, interior }

class HexMapPaneState extends ConsumerState<HexMapPane> {
  GenResult? _last; // latest travel result
  final GlobalKey _hexSnapKey = GlobalKey();
  String _hcClimate = 'temperate';
  int _hcCount = 10;
  int _hcInteriorCount = 6; // site interior "Generate" area count
  int? _selCol, _selRow; // selected revealed hex (null = none)
  _HexZoom _zoom = _HexZoom.region;

  @override
  void initState() {
    super.initState();
    // Preselect the PlayContext spine's active location if it's a hex, so
    // arriving at this pane (e.g. via a journal place-chip) shows its card.
    final loc = ref.read(playContextProvider).valueOrNull?.activeLocation;
    if (loc?.hexCol != null) {
      _selCol = loc!.hexCol;
      _selRow = loc.hexRow;
    }
  }

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

  List<Widget> _hexcrawlTools(BuildContext context) {
    final data = ref.watch(hexcrawlDataProvider).valueOrNull;
    if (data == null) return const [];
    // Pinned finite so these can share a row in the chrome's Wrap.
    final style = FilledButton.styleFrom(minimumSize: const Size(0, 40));
    return [
      for (final c in data.climates)
        ChoiceChip(
          label: Text(c),
          selected: _hcClimate == c,
          onSelected: (_) => setState(() => _hcClimate = c),
        ),
      FilledButton.tonal(
        key: const Key('hexcrawl-reveal'),
        style: style,
        onPressed: _hcCrawl,
        child: const Text('Reveal next (hexcrawl)'),
      ),
      FilledButton.tonal(
        key: const Key('hexcrawl-generate-region'),
        style: style,
        onPressed: _hcRegion,
        child: Text('Generate region ($_hcCount)'),
      ),
      IconButton(
        icon: const Icon(Icons.remove),
        onPressed: () => setState(() => _hcCount = (_hcCount - 5).clamp(5, 60)),
      ),
      IconButton(
        icon: const Icon(Icons.add),
        onPressed: () => setState(() => _hcCount = (_hcCount + 5).clamp(5, 60)),
      ),
    ];
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
        final zoomed = sel != null && _zoom != _HexZoom.region;
        return MapChrome(
          canvas: sel != null && _zoom == _HexZoom.flower
              ? _flowerCanvas(context, sel)
              : sel != null && _zoom == _HexZoom.interior
                  ? _interiorCanvas(context, sel)
                  : (s.hexes.isEmpty ? _empty(context) : _canvas(s)),
          // Each zoom level has its own verbs — a zoomed-in view must not
          // stack the region's controls on top of its own.
          primary: switch (_zoom) {
            _ when !zoomed => _regionPrimary(),
            _HexZoom.flower => _flowerPrimary(sel),
            _HexZoom.interior => _interiorPrimary(sel),
            _ => _regionPrimary(),
          },
          tools: zoomed
              ? _sharedTools(context, s)
              : _regionTools(context, s, crawl),
          detail: _detailOverlay(context, sel),
        );
      },
    );
  }

  /// The bottom overlay: whichever cards apply to the current zoom.
  Widget? _detailOverlay(BuildContext context, HexCell? sel) {
    final cards = <Widget>[
      if (_hexcrawlOn() && sel != null && _zoom == _HexZoom.region)
        _hexDetailCard(context, sel),
      if (sel != null && _zoom == _HexZoom.flower && sel.local.isNotEmpty)
        _flowerLegend(context, sel),
      if (_last != null)
        Padding(
          padding: const EdgeInsets.all(8),
          child: ResultCard(
            result: _last!,
            onInspire: ref.watch(interpretReadyProvider)
                ? () => inspireGenResult(context, ref, _last!)
                : null,
            onLog: () => _log(_last!.title, _last!.asText),
          ),
        ),
    ];
    if (cards.isEmpty) return null;
    // Stretch: a Column centers by default, which would float the cards at
    // intrinsic width in the middle of the pane.
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: cards,
    );
  }

  /// Current crawl environment + Lost flag, mirroring the Exploration tool.
  Widget _envChip(BuildContext context, CrawlState crawl) => Chip(
        key: const Key('hex-env-chip'),
        visualDensity: VisualDensity.compact,
        avatar: const Icon(Icons.terrain_outlined, size: 16),
        label: Text(
          '${_envNames[crawl.envRow! - 1]}'
          '${crawl.lost ? ' — LOST (d6 encounters)' : ''}',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      );

  List<Widget> _regionPrimary() => [
        FilledButton.tonal(
          key: const Key('travel'),
          // A themed FilledButton's minimumSize width is infinity, so it must
          // pin a finite one to sit in the chrome's Wrap.
          style: FilledButton.styleFrom(minimumSize: const Size(0, 40)),
          onPressed: _travel,
          child: const Text('Travel'),
        ),
      ];

  /// Tools available at every zoom level.
  List<Widget> _sharedTools(BuildContext context, MapState s) => [
        IconButton(
          key: const Key('hex-journal'),
          icon: const Icon(Icons.bookmark_add_outlined),
          tooltip: 'Add map to journal',
          onPressed: s.hexes.isEmpty
              ? null
              : () => _log('Wilderness map', _hexSummary(s)),
        ),
        // Only in the full-map (region) view — the snapshot boundary isn't in
        // the tree during flower/interior zoom.
        if (_zoom == _HexZoom.region && ref.watch(blobStoreAvailableProvider))
          IconButton(
            key: const Key('map-snapshot'),
            icon: const Icon(Icons.draw_outlined),
            tooltip: 'Annotate in journal',
            onPressed: () => snapshotMapToJournal(context, ref, _hexSnapKey),
          ),
        IconButton(
          key: const Key('hex-reset'),
          icon: const Icon(Icons.delete_sweep_outlined),
          tooltip: 'Reset hex map',
          onPressed: () => _reset(context),
        ),
      ];

  List<Widget> _regionTools(
          BuildContext context, MapState s, CrawlState crawl) =>
      [
        if (crawl.envRow != null) _envChip(context, crawl),
        if (_hexcrawlOn()) ..._hexcrawlTools(context),
        ..._sharedTools(context, s),
      ];

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
    final encounterRef = ref.watch(encounterProvider).valueOrNull?.locationRef;
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
    return _mapViewport(
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
              ref.read(playContextProvider.notifier).setActiveLocation(
                  LocationRef(hexCol: hit.col, hexRow: hit.row));
              return;
            }
            _manualReveal(hit.col, hit.row);
          },
          child: RepaintBoundary(
            key: _hexSnapKey,
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
                encounterCol: encounterRef?.hexCol,
                encounterRow: encounterRef?.hexRow,
              ),
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
            if (h.site != null) ...[
              Text('Site: ${h.site}', style: theme.textTheme.bodyMedium),
              for (final line in h.siteLines)
                Text('• $line', style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 8),
            Wrap(spacing: 8, runSpacing: 8, children: [
              if (h.terrain != null)
                FilledButton.tonal(
                  key: const Key('local-zoom-in'),
                  onPressed: () => setState(() => _zoom = _HexZoom.flower),
                  child: const Text('Zoom in'),
                ),
              if (h.site != null) ...[
                FilledButton.tonal(
                  key: const Key('site-crawl'),
                  onPressed: () => _siteCrawl(h),
                  child: const Text('Crawl site'),
                ),
                if (ref.watch(aiReadyProvider))
                  FilledButton.tonalIcon(
                    key: const Key('flesh-out-site'),
                    onPressed: () => _fleshOutSite(h),
                    icon: const AiBadge(),
                    label: const Text('Flesh out'),
                  ),
                FilledButton.tonal(
                  key: const Key('site-full'),
                  onPressed: () => _siteFull(h),
                  child: const Text('Full site'),
                ),
                FilledButton.tonal(
                  key: const Key('site-enter'),
                  onPressed: () => setState(() => _zoom = _HexZoom.interior),
                  child: const Text('Enter'),
                ),
                if (h.siteLines.isNotEmpty)
                  OutlinedButton(
                    key: const Key('site-log'),
                    onPressed: () =>
                        _log('Site: ${h.site}', h.siteLines.join('\n')),
                    child: const Text('Log'),
                  ),
              ],
              Builder(builder: (context) {
                final enc = ref.watch(encounterProvider);
                final ref0 = enc.valueOrNull?.locationRef;
                return encounterToggleButton(
                  key: const Key('hex-encounter-toggle'),
                  linked: ref0?.hexCol == h.col && ref0?.hexRow == h.row,
                  enabled: enc.hasValue,
                  onLink: () => ref
                      .read(encounterProvider.notifier)
                      .setLocation(LocationRef(hexCol: h.col, hexRow: h.row)),
                  onUnlink: () =>
                      ref.read(encounterProvider.notifier).setLocation(null),
                );
              }),
              Builder(builder: (context) {
                final ref0 =
                    ref.watch(encounterProvider).valueOrNull?.locationRef;
                return encounterJumpButton(
                  key: const Key('hex-encounter-goto'),
                  show: ref0?.hexCol == h.col && ref0?.hexRow == h.row,
                  onJump: () => ref
                      .read(shellRouteProvider.notifier)
                      .goTo(Destination.track, subtab: 'encounter'),
                );
              }),
              Builder(builder: (context) {
                final all = ref.watch(journalProvider).valueOrNull ??
                    const <JournalEntry>[];
                final entries = entriesAtLocation(
                    all, LocationRef(hexCol: h.col, hexRow: h.row));
                return locationEntriesChip(
                  context: context,
                  ref: ref,
                  key: Key('loc-entries-${h.col}-${h.row}'),
                  entries: entries,
                  placeLabel: 'Hex (${h.col}, ${h.row})',
                );
              }),
              placesHereChip(
                ref: ref,
                key: Key('loc-places-${h.col}-${h.row}'),
                loc: LocationRef(hexCol: h.col, hexRow: h.row),
              ),
              // Map-layer hierarchy: dungeons anchor to hexes — "Enter"
              // switches to the anchored dungeon, the link-off chip
              // un-anchors, "Dungeon here" anchors the active dungeon or
              // creates a new one (many dungeons per world).
              Builder(builder: (context) {
                final m = ref.watch(mapProvider).valueOrNull;
                final site = m?.dungeonAnchoredAt(h.col, h.row);
                if (site != null) {
                  return Wrap(spacing: 4, children: [
                    ActionChip(
                      key: const Key('hex-enter-dungeon'),
                      avatar: const Icon(Icons.stairs_outlined, size: 16),
                      label: Text('Enter ${site.name}'),
                      onPressed: () async {
                        await ref
                            .read(mapProvider.notifier)
                            .switchDungeon(site.id);
                        ref
                            .read(shellRouteProvider.notifier)
                            .goTo(Destination.map, subtab: 'dungeon');
                      },
                    ),
                    ActionChip(
                      key: const Key('hex-unlink-dungeon'),
                      avatar: const Icon(Icons.link_off, size: 16),
                      label: const Text('Unlink'),
                      onPressed: () => ref
                          .read(mapProvider.notifier)
                          .unanchorDungeon(site.id),
                    ),
                  ]);
                }
                return ActionChip(
                  key: const Key('hex-place-dungeon'),
                  avatar: const Icon(Icons.stairs_outlined, size: 16),
                  label: const Text('Dungeon here'),
                  onPressed: () => ref
                      .read(mapProvider.notifier)
                      .anchorDungeonHere(h.col, h.row),
                );
              }),
              // Map-layer hierarchy: a hand-drawn/PDF sketch map (a
              // JournalKind.sketch entry) can anchor to this hex.
              Builder(builder: (context) {
                final entries = ref.watch(journalProvider).valueOrNull ??
                    const <JournalEntry>[];
                if (h.sketchEntryId != null) {
                  final e =
                      entries.where((x) => x.id == h.sketchEntryId).firstOrNull;
                  final title = e?.title.trim();
                  return Wrap(spacing: 4, children: [
                    ActionChip(
                      key: const Key('hex-open-sketch'),
                      avatar: const Icon(Icons.brush_outlined, size: 16),
                      label: Text((title == null || title.isEmpty)
                          ? 'Map'
                          : 'Map: $title'),
                      // Linked sketch deleted -> chip stays to Unlink only.
                      onPressed: e == null
                          ? null
                          : () => openSketchEntry(context, ref, e),
                    ),
                    ActionChip(
                      key: const Key('hex-unlink-sketch'),
                      avatar: const Icon(Icons.link_off, size: 16),
                      label: const Text('Unlink map'),
                      onPressed: () => ref
                          .read(mapProvider.notifier)
                          .setHexSketch(h.col, h.row, null),
                    ),
                  ]);
                }
                final sketches =
                    entries.where((x) => x.kind == JournalKind.sketch).toList();
                if (sketches.isEmpty) return const SizedBox.shrink();
                return ActionChip(
                  key: const Key('hex-link-sketch'),
                  avatar: const Icon(Icons.brush_outlined, size: 16),
                  label: const Text('Link map…'),
                  onPressed: () => _pickHexSketch(context, h, sketches),
                );
              }),
            ]),
          ],
        ),
      ),
    );
  }

  /// Picker over the campaign's sketch entries; the chosen one anchors to [h].
  Future<void> _pickHexSketch(
      BuildContext context, HexCell h, List<JournalEntry> sketches) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Link a sketch map'),
        children: [
          for (final e in sketches)
            SimpleDialogOption(
              key: Key('sketch-pick-${e.id}'),
              onPressed: () => Navigator.of(dialogContext).pop(e.id),
              child: Text(e.title.trim().isEmpty
                  ? 'Sketch · ${e.timestamp.toLocal().toString().split(' ').first}'
                  : e.title),
            ),
        ],
      ),
    );
    if (picked == null) return;
    await ref.read(mapProvider.notifier).setHexSketch(h.col, h.row, picked);
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

  Future<void> _siteCrawl(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .crawlSite(h.col, h.row, data, widget.oracle.dice);
  }

  Future<void> _siteFull(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .generateSite(h.col, h.row, data, widget.oracle.dice);
  }

  Future<void> _fleshOutSite(HexCell h) async {
    final seed = buildFleshOutSeed(ref,
        entityKind: 'location',
        name: h.site ?? 'site',
        existingDetail: h.siteLines.join('\n'));
    final String detail;
    try {
      detail = await ref.read(interpreterServiceProvider).fleshOut(seed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Flesh out failed: $e')));
      }
      return;
    }
    if (!mounted) return;
    if (await showFleshOutReview(context, detail) != true) return;
    await ref.read(mapProvider.notifier).appendSiteLine(h.col, h.row, detail);
  }

  Future<void> _interiorCrawl(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref
        .read(mapProvider.notifier)
        .crawlSiteArea(h.col, h.row, data, widget.oracle.dice);
  }

  Future<void> _interiorFull(HexCell h) async {
    final data = ref.read(hexcrawlDataProvider).valueOrNull;
    if (data == null) return;
    await ref.read(mapProvider.notifier).generateSiteInterior(
        h.col, h.row, _hcInteriorCount, data, widget.oracle.dice);
  }

  List<Widget> _interiorPrimary(HexCell h) {
    // Pinned finite so these can share a row in the chrome's Wrap.
    final style = FilledButton.styleFrom(minimumSize: const Size(0, 40));
    return [
      OutlinedButton(
        key: const Key('interior-back'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
        onPressed: () => setState(() => _zoom = _HexZoom.region),
        child: const Text('Back'),
      ),
      FilledButton.tonal(
        key: const Key('interior-reveal'),
        style: style,
        onPressed: () => _interiorCrawl(h),
        child: const Text('Reveal area'),
      ),
      FilledButton.tonal(
        key: const Key('interior-generate'),
        style: style,
        onPressed: () => _interiorFull(h),
        child: Text('Generate interior ($_hcInteriorCount)'),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.remove),
        onPressed: () => setState(
            () => _hcInteriorCount = (_hcInteriorCount - 1).clamp(3, 12)),
      ),
      IconButton(
        visualDensity: VisualDensity.compact,
        icon: const Icon(Icons.add),
        onPressed: () => setState(
            () => _hcInteriorCount = (_hcInteriorCount + 1).clamp(3, 12)),
      ),
    ];
  }

  Widget _interiorCanvas(BuildContext context, HexCell h) {
    final scheme = Theme.of(context).colorScheme;
    // Render site areas through the existing dungeon painter (no corridors).
    final rooms = [
      for (var i = 0; i < h.siteAreas.length; i++)
        DungeonRoom(
            id: '$i',
            x: h.siteAreas[i].x,
            y: h.siteAreas[i].y,
            title: h.siteAreas[i].name),
    ];
    if (rooms.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text('No areas yet. Reveal or generate the interior.',
              textAlign: TextAlign.center,
              style: Theme.of(context).textTheme.bodyMedium),
        ),
      );
    }
    final minX = rooms.map((r) => r.x).reduce(math.min);
    final minY = rooms.map((r) => r.y).reduce(math.min);
    final maxX = rooms.map((r) => r.x).reduce(math.max);
    final maxY = rooms.map((r) => r.y).reduce(math.max);
    final width = math.max((maxX - minX + 1) * _cell + _cell, 360.0);
    final height = math.max((maxY - minY + 1) * _cell + _cell, 360.0);
    return _mapViewport(
      child: SizedBox(
        width: width,
        height: height,
        child: CustomPaint(
          key: const Key('interior-canvas'),
          size: Size(width, height),
          painter: _DungeonPainter(
              rooms: rooms,
              corridors: const [],
              currentRoomId: null,
              scheme: scheme),
        ),
      ),
    );
  }

  List<Widget> _flowerPrimary(HexCell h) {
    // Pinned finite so these can share a row in the chrome's Wrap.
    final style = FilledButton.styleFrom(minimumSize: const Size(0, 40));
    return [
      OutlinedButton(
        key: const Key('local-back'),
        style: OutlinedButton.styleFrom(minimumSize: const Size(0, 40)),
        onPressed: () => setState(() => _zoom = _HexZoom.region),
        child: const Text('Back'),
      ),
      FilledButton.tonal(
        key: const Key('local-reveal'),
        style: style,
        onPressed: () => _localCrawl(h),
        child: const Text('Reveal sub-hex'),
      ),
      FilledButton.tonal(
        key: const Key('local-fill'),
        style: style,
        onPressed: () => _localFull(h),
        child: const Text('Fill hex'),
      ),
    ];
  }

  Widget _flowerCanvas(BuildContext context, HexCell h) {
    final scheme = Theme.of(context).colorScheme;
    return _mapViewport(
      boundary: 200,
      child: SizedBox(
        width: 360,
        height: 360,
        child: CustomPaint(
          key: const Key('flower-canvas'),
          size: const Size(360, 360),
          painter: _FlowerPainter(
              centerTerrain: h.terrain ?? '', ring: h.local, scheme: scheme),
        ),
      ),
    );
  }

  /// The revealed sub-hex ring, read out over the flower canvas. Carries its
  /// own Card surface — it floats over paint and must stay legible.
  Widget _flowerLegend(BuildContext context, HexCell h) => Card(
        key: const Key('flower-legend'),
        margin: const EdgeInsets.symmetric(vertical: 4),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final lc in h.local)
                Text('• ${lc.terrain}: ${lc.feature}',
                    style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
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
    this.encounterCol,
    this.encounterRow,
  });

  final List<HexCell> hexes;
  final List<({int col, int row})> ghosts;
  final int? currentCol;
  final int? currentRow;
  final int minCol;
  final int minRow;
  final List<String> envNames;
  final ColorScheme scheme;
  final int? encounterCol;
  final int? encounterRow;

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
      if (h.col == encounterCol && h.row == encounterRow) {
        paintEncounterPin(
            canvas, c + const Offset(0, -_hexSize * 0.5), scheme.error);
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
      old.encounterCol != encounterCol ||
      old.encounterRow != encounterRow ||
      old.scheme != scheme;
}
