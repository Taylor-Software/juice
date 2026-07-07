import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../engine/sketch.dart';
import '../engine/tarot_meanings.dart';
import 'sketch_editor.dart';
import '../shared/ai_badge.dart';
import '../shared/card_image.dart';
import '../shared/design_tokens.dart';
import '../shared/mention_text.dart';
import '../state/blob_store.dart';

/// Humanizes a [JournalEntry.sourceTool] id into an uppercase source label
/// for the hero card's source row, e.g. 'fate-juice' -> 'FATE CHECK',
/// 'dice' -> 'DICE', 'cards' -> 'CARDS'. Falls back to the de-hyphenated id.
String _sourceLabel(String? sourceTool) {
  switch (sourceTool) {
    case null:
      return 'RESULT';
    case 'fate-juice':
    case 'fate-check':
    case 'fate-mythic':
      return 'FATE CHECK';
    case 'cards':
      return 'CARDS';
    case 'dice':
      return 'DICE';
    default:
      return sourceTool.replaceAll('-', ' ').toUpperCase();
  }
}

/// A slim, low-weight row for mechanical dice/log results (sourceTool=='dice').
/// Sits back so oracle hero cards carry the visual weight.
class DiceLogRow extends StatelessWidget {
  const DiceLogRow(
      {super.key, required this.entry, required this.menu, this.onReroll});

  final JournalEntry entry;
  final Widget menu;
  final VoidCallback? onReroll;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    // Prefer the structured summary ("2d6 = 7"); else the title/body.
    final summary = entry.payload?['summary'] as String?;
    final line = (summary != null && summary.trim().isNotEmpty)
        ? summary.trim()
        : (entry.body.trim().isNotEmpty
            ? entry.body.split('\n').first.trim()
            : entry.title);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          color: tk.raised,
          border: Border.all(color: tk.hairline),
          borderRadius: BorderRadius.circular(12),
        ),
        padding: const EdgeInsets.fromLTRB(10, 6, 4, 6),
        child: Row(
          children: [
            Container(
              width: 22,
              height: 22,
              decoration: BoxDecoration(
                color: tk.terracotta,
                borderRadius: BorderRadius.circular(6),
              ),
              child: const Icon(Icons.casino, size: 14, color: Colors.white),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                'Dice · $line',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: tk.uiLabel.copyWith(fontSize: 13, color: tk.inkBody),
              ),
            ),
            if (onReroll != null)
              IconButton(
                key: Key('entry-reroll-${entry.id}'),
                tooltip: 'Roll again',
                icon: const Icon(Icons.replay, size: 18),
                visualDensity: VisualDensity.compact,
                onPressed: onReroll,
              ),
            menu,
          ],
        ),
      ),
    );
  }
}

/// Rich rendering for entries that carry a structured payload: a warm gradient
/// hero with a source row, a big serif answer, roll rows, an appended-notes
/// remainder, and an inline action row (Interpret / Voice / Pin).
class PayloadCard extends StatelessWidget {
  const PayloadCard({
    super.key,
    required this.entry,
    required this.extras,
    required this.menu,
    this.onReroll,
    this.onOpenTool,
    this.onInterpret,
    this.onVoice,
    this.onTogglePin,
    this.onCharacterTap,
    this.onThreadTap,
    this.onDiceTap,
    this.lonelog = false,
    this.placeChip,
  });

  final JournalEntry entry;
  final List<String> extras;
  final Widget menu;
  final VoidCallback? onReroll;
  final VoidCallback? onOpenTool;
  final VoidCallback? onInterpret;
  final VoidCallback? onVoice;
  final VoidCallback? onTogglePin;
  final void Function(String id)? onCharacterTap;
  final void Function(String id)? onThreadTap;
  final void Function(String notation)? onDiceTap;
  final bool lonelog;

  /// Low-chrome tappable "where this happened" suffix (see `PlaceChip` in
  /// journal_screen.dart), rendered alongside the extras line. Null when the
  /// entry has no logged location.
  final Widget? placeChip;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    final p = entry.payload!;
    final summary = p['summary'] as String?;
    final allRolls = [
      for (final r in (p['rolls'] as List))
        if (r is Map) ('${r['label']}', '${r['display']}'),
    ];
    // The Intensity roll becomes a caption beneath the answer (Mythic/Juice);
    // the remaining rolls render as label/value rows.
    final intensity =
        allRolls.where((r) => r.$1 == 'Intensity').map((r) => r.$2).firstOrNull;
    final rolls =
        allRolls.where((r) => r.$1 != 'Intensity').toList(growable: false);
    // Right-aligned sub-label: the odds, humanized (else the title's
    // parenthetical, e.g. "Fate Check (Likely)" -> "Likely").
    final odds = (p['args'] as Map?)?['odds'] as String?;
    String? subLabel;
    if (odds != null && odds.isNotEmpty) {
      subLabel = '${odds[0].toUpperCase()}${odds.substring(1)}';
    } else {
      final m = RegExp(r'\(([^)]+)\)$').firstMatch(entry.title);
      subLabel = m?.group(1);
    }

    // Body content beyond the payload-derived text (e.g. appended oracle
    // readings) still renders; the base text is shown structured instead.
    final rollsText = allRolls.map((r) => '${r.$1}: ${r.$2}').join('\n');
    final baseText = summary == null ? rollsText : '$summary\n$rollsText';
    var remainder = '';
    if (entry.body != baseText) {
      remainder = entry.body.startsWith(baseText)
          ? entry.body.substring(baseText.length).trimLeft()
          : entry.body;
    }

    final showActions =
        onInterpret != null || onVoice != null || onTogglePin != null;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tk.resultHeroGradient,
          ),
          border: Border.all(color: const Color(0xFFEFC9B4)),
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: tk.terracotta.withValues(alpha: 0.16),
              blurRadius: 22,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // SOURCE ROW: icon tile + uppercase source label + reroll/open +
              // right-aligned sub-label + overflow menu.
              Row(
                children: [
                  Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: tk.terracotta,
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: const Icon(Icons.auto_stories,
                        size: 14, color: Colors.white),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      _sourceLabel(entry.sourceTool),
                      style: tk.uiLabel.copyWith(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                        color: tk.inkFaint,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                  if (subLabel != null)
                    Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: Text(
                        subLabel,
                        style: tk.uiLabel
                            .copyWith(fontSize: 11, color: tk.inkMuted),
                      ),
                    ),
                  if (onReroll != null)
                    IconButton(
                      key: Key('entry-reroll-${entry.id}'),
                      tooltip: 'Roll again',
                      icon: const Icon(Icons.replay, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: onReroll,
                    ),
                  if (onOpenTool != null)
                    IconButton(
                      key: Key('entry-open-tool-${entry.id}'),
                      tooltip: 'Open in tool',
                      icon: const Icon(Icons.open_in_new, size: 20),
                      visualDensity: VisualDensity.compact,
                      onPressed: onOpenTool,
                    ),
                  menu,
                ],
              ),
              // BIG SERIF ANSWER.
              if (summary != null) _answer(tk, summary),
              if (intensity != null)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(
                    intensity,
                    style:
                        tk.uiLabel.copyWith(fontSize: 11, color: tk.inkMuted),
                  ),
                ),
              if (entry.sourceTool == 'cards' && summary != null)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Builder(builder: (_) {
                      final r = readTarot(summary);
                      return CardImage(r.name,
                          reversed: r.reversed, height: 120);
                    }),
                  ),
                ),
              const SizedBox(height: 4),
              for (final r in rolls)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      SizedBox(
                        width: 110,
                        child: Text(
                          r.$1,
                          style: tk.uiLabel
                              .copyWith(fontSize: 12, color: tk.inkMuted),
                        ),
                      ),
                      Expanded(
                        child: Text(
                          r.$2,
                          style: tk.narrative
                              .copyWith(fontSize: 14, color: tk.inkBody),
                        ),
                      ),
                    ],
                  ),
                ),
              if (remainder.isNotEmpty) ...[
                const SizedBox(height: 6),
                MentionText(
                  remainder,
                  style: tk.narrative.copyWith(fontSize: 14, color: tk.inkBody),
                  onCharacterTap: onCharacterTap,
                  onThreadTap: onThreadTap,
                  onDiceTap: onDiceTap,
                  lonelog: lonelog,
                ),
              ],
              if (extras.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  extras.join('\n'),
                  style: tk.uiLabel.copyWith(fontSize: 11, color: tk.inkMuted),
                ),
              ],
              if (placeChip != null) ...[
                const SizedBox(height: 4),
                placeChip!,
              ],
              // INLINE ACTION ROW above a hairline divider.
              if (showActions) ...[
                const SizedBox(height: 8),
                Divider(color: tk.hairline, height: 1),
                Row(
                  children: [
                    if (onInterpret != null)
                      TextButton(
                        onPressed: onInterpret,
                        child: const AiBadge(label: 'Interpret'),
                      ),
                    if (onVoice != null)
                      TextButton(
                        onPressed: onVoice,
                        child: const AiBadge(label: 'Voice line'),
                      ),
                    const Spacer(),
                    if (onTogglePin != null)
                      TextButton.icon(
                        key: Key('pin-${entry.id}'),
                        onPressed: onTogglePin,
                        icon: Icon(
                          entry.pinned
                              ? Icons.push_pin
                              : Icons.push_pin_outlined,
                          size: 16,
                          color: entry.pinned ? tk.terracotta : null,
                        ),
                        label: const Text('Pin'),
                      ),
                  ],
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }

  /// The big serif answer. If the summary has a comma, the trailing qualifier
  /// (e.g. "and…", "but…") renders italic in terracotta; otherwise the whole
  /// summary renders normal.
  Widget _answer(JuiceTokens tk, String summary) {
    final base = tk.narrative.copyWith(
      fontSize: 30,
      fontWeight: FontWeight.w500,
      color: tk.ink,
      height: 1.15,
    );
    final comma = summary.indexOf(',');
    if (comma < 0 || comma == summary.length - 1) {
      return Text(summary, style: base);
    }
    final head = summary.substring(0, comma + 1); // includes the comma
    final tail = summary.substring(comma + 1);
    return Text.rich(
      TextSpan(
        style: base,
        children: [
          TextSpan(text: head),
          TextSpan(
            text: tail,
            style: base.copyWith(
              fontStyle: FontStyle.italic,
              color: tk.terracotta,
            ),
          ),
        ],
      ),
    );
  }
}

/// Renders a sketch thumbnail, resolving its background image (if any) from the
/// blob store once and caching the decoded [ui.Image] in state (so the journal
/// list doesn't re-read the file on every rebuild).
class SketchThumbnail extends ConsumerStatefulWidget {
  const SketchThumbnail(this.data, {super.key});
  final SketchData data;

  @override
  ConsumerState<SketchThumbnail> createState() => _SketchThumbnailState();
}

class _SketchThumbnailState extends ConsumerState<SketchThumbnail> {
  ui.Image? _bg;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(SketchThumbnail old) {
    super.didUpdateWidget(old);
    if (old.data.backgroundBlobId != widget.data.backgroundBlobId) _load();
  }

  @override
  void dispose() {
    _bg?.dispose(); // release the cached decoded image's native memory
    super.dispose();
  }

  Future<void> _load() async {
    final id = widget.data.backgroundBlobId;
    if (id == null || !ref.read(blobStoreAvailableProvider)) {
      final old = _bg;
      if (_bg != null) {
        if (mounted) {
          setState(() => _bg = null);
        } else {
          _bg = null;
        }
      }
      old?.dispose();
      return;
    }
    final img =
        await decodeSketchBackground(await ref.read(blobStoreProvider).get(id));
    if (!mounted) {
      img?.dispose();
      return;
    }
    final old = _bg;
    setState(() => _bg = img);
    old?.dispose(); // drop the previously-cached image
  }

  @override
  Widget build(BuildContext context) {
    final bg = _bg;
    final paint =
        CustomPaint(painter: SketchPainter(widget.data, background: bg));
    // Lock the thumbnail to the image aspect so strokes (uniformly scaled) stay
    // aligned to the BoxFit.contain background.
    if (bg == null) return paint;
    return Center(
      child: AspectRatio(aspectRatio: bg.width / bg.height, child: paint),
    );
  }
}
