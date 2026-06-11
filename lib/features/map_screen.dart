import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

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

/// Maps tool: a dungeon map grown room-by-room from the dungeon oracle and
/// a wilderness hex map (Hex tab lands in the next task).
class MapScreen extends StatelessWidget {
  const MapScreen({super.key, required this.oracle});
  final Oracle oracle;

  @override
  Widget build(BuildContext context) {
    return DefaultTabController(
      length: 2,
      child: Column(
        children: [
          const Material(
            child: TabBar(
              tabs: [
                Tab(text: 'Dungeon'),
                Tab(text: 'Hex'),
              ],
            ),
          ),
          Expanded(
            child: TabBarView(
              children: [
                _DungeonTab(oracle: oracle),
                const SizedBox(), // Hex tab: Task 3
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// -- Dungeon ----------------------------------------------------------------
class _DungeonTab extends ConsumerStatefulWidget {
  const _DungeonTab({required this.oracle});
  final Oracle oracle;

  @override
  ConsumerState<_DungeonTab> createState() => _DungeonTabState();
}

class _DungeonTabState extends ConsumerState<_DungeonTab> {
  GenResult? _last; // latest linger result

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
          FilledButton.tonal(
            key: const Key('new-room'),
            onPressed: _newRoom,
            child: const Text('New room'),
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
    await ref.read(mapProvider.notifier).addRoom(
        title: title, detail: g.asText, dice: widget.oracle.dice);
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
            color: isCurrent
                ? scheme.onPrimaryContainer
                : scheme.onSurfaceVariant,
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
