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

/// Rich rendering for entries that carry a structured payload. Collapses by
/// default to a single compact row (source icon + one-line answer + a muted
/// roll summary + reroll + menu) — consistent with [DiceLogRow] — so
/// mechanics stay out of the way of the story. Tapping the row expands it in
/// place to reveal the full hero treatment: the big serif answer, intensity
/// caption, tarot image, roll rows, an appended-notes remainder, extras
/// footer, place chip, and the Interpret / Voice / Pin action row. Pinned
/// entries (`entry.pinned`) start expanded — pinning means "keep this
/// visible."
class PayloadCard extends StatefulWidget {
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
    this.onNpcTap,
    this.onPlaceTap,
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
  final void Function(String id)? onNpcTap;
  final void Function(String id)? onPlaceTap;
  final void Function(String notation)? onDiceTap;
  final bool lonelog;

  /// Low-chrome tappable "where this happened" suffix (see `PlaceChip` in
  /// journal_screen.dart), rendered alongside the extras line. Null when the
  /// entry has no logged location.
  final Widget? placeChip;

  @override
  State<PayloadCard> createState() => _PayloadCardState();
}

class _PayloadCardState extends State<PayloadCard> {
  late bool _expanded = widget.entry.pinned;

  @override
  void didUpdateWidget(PayloadCard old) {
    super.didUpdateWidget(old);
    // A newly-pinned entry (e.g. via the on-card Pin button) snaps open; an
    // unpinned entry keeps whatever expand state the user left it in.
    if (widget.entry.pinned && !old.entry.pinned) _expanded = true;
  }

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    final entry = widget.entry;
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

    final showActions = widget.onInterpret != null ||
        widget.onVoice != null ||
        widget.onTogglePin != null;

    // One-line answer shared by both the collapsed row and the expanded
    // header's absence thereof: prefer the summary, else the first body line,
    // else the title (mirrors DiceLogRow's fallback).
    final oneLiner = (summary != null && summary.trim().isNotEmpty)
        ? summary.trim()
        : (entry.body.trim().isNotEmpty
            ? entry.body.split('\n').first.trim()
            : entry.title);
    // Muted trailing roll summary for the collapsed row, e.g. "Answer: Yes
    // (+04)" — the first non-Intensity roll, truncated to one line.
    final rollSummary =
        rolls.isEmpty ? null : '${rolls.first.$1} ${rolls.first.$2}';

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: tk.resultHeroGradient,
          ),
          border: Border.all(color: const Color(0xFFEFC9B4)),
          borderRadius: BorderRadius.circular(_expanded ? 18 : 12),
          boxShadow: _expanded
              ? [
                  BoxShadow(
                    color: tk.terracotta.withValues(alpha: 0.16),
                    blurRadius: 22,
                    offset: const Offset(0, 8),
                  ),
                ]
              : null,
        ),
        child: _expanded
            ? Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 8, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _expandedHeader(tk, subLabel),
                    // BIG SERIF ANSWER.
                    if (summary != null) _answer(tk, summary),
                    if (intensity != null)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          intensity,
                          style: tk.uiLabel
                              .copyWith(fontSize: 11, color: tk.inkMuted),
                        ),
                      ),
                    if (entry.sourceTool == 'cards' &&
                        p['cards'] is! List &&
                        summary != null)
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
                    // Tarot spread: a labelled strip of card images.
                    if (p['cards'] case final List<dynamic> cards
                        when cards.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 10,
                          runSpacing: 10,
                          children: [
                            for (final c in cards.whereType<Map<dynamic, dynamic>>())
                              Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Builder(builder: (_) {
                                    final r = readTarot('${c['shown'] ?? ''}');
                                    return CardImage(r.name,
                                        reversed: r.reversed, height: 96);
                                  }),
                                  SizedBox(
                                    width: 64,
                                    child: Text('${c['position'] ?? ''}',
                                        textAlign: TextAlign.center,
                                        style: tk.uiLabel.copyWith(
                                            fontSize: 10, color: tk.inkMuted)),
                                  ),
                                ],
                              ),
                          ],
                        ),
                      ),
                    // Story-dice entries carry their icon asset paths in the
                    // payload — render the rolled strip.
                    if (p['icons'] case final List<dynamic> icons
                        when icons.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 8),
                        child: Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: [
                            for (final a in icons.whereType<String>())
                              Image.asset(a, width: 52, height: 52),
                          ],
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
                        style: tk.narrative
                            .copyWith(fontSize: 14, color: tk.inkBody),
                        onCharacterTap: widget.onCharacterTap,
                        onThreadTap: widget.onThreadTap,
                        onNpcTap: widget.onNpcTap,
                        onPlaceTap: widget.onPlaceTap,
                        onDiceTap: widget.onDiceTap,
                        lonelog: widget.lonelog,
                      ),
                    ],
                    if (widget.extras.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Text(
                        widget.extras.join('\n'),
                        style: tk.uiLabel
                            .copyWith(fontSize: 11, color: tk.inkMuted),
                      ),
                    ],
                    if (widget.placeChip != null) ...[
                      const SizedBox(height: 4),
                      widget.placeChip!,
                    ],
                    // INLINE ACTION ROW above a hairline divider.
                    if (showActions) ...[
                      const SizedBox(height: 8),
                      Divider(color: tk.hairline, height: 1),
                      Row(
                        children: [
                          if (widget.onInterpret != null)
                            TextButton(
                              onPressed: widget.onInterpret,
                              child: const AiBadge(label: 'Interpret'),
                            ),
                          if (widget.onVoice != null)
                            TextButton(
                              onPressed: widget.onVoice,
                              child: const AiBadge(label: 'Voice line'),
                            ),
                          const Spacer(),
                          if (widget.onTogglePin != null)
                            TextButton.icon(
                              key: Key('pin-${entry.id}'),
                              onPressed: widget.onTogglePin,
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
              )
            : _collapsedRow(tk, entry, oneLiner, rollSummary),
      ),
    );
  }

  /// The always-visible header row shown while expanded: icon tile + source
  /// label + sub-label + reroll/open-in-tool + menu.
  Widget _expandedHeader(JuiceTokens tk, String? subLabel) {
    final entry = widget.entry;
    return Row(
      children: [
        Container(
          width: 24,
          height: 24,
          decoration: BoxDecoration(
            color: tk.terracotta,
            borderRadius: BorderRadius.circular(7),
          ),
          child: const Icon(Icons.auto_stories, size: 14, color: Colors.white),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: GestureDetector(
            key: Key('payload-expand-${entry.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _expanded = false),
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
        ),
        if (subLabel != null)
          Padding(
            padding: const EdgeInsets.only(right: 4),
            child: Text(
              subLabel,
              style: tk.uiLabel.copyWith(fontSize: 11, color: tk.inkMuted),
            ),
          ),
        if (widget.onReroll != null)
          IconButton(
            key: Key('entry-reroll-${entry.id}'),
            tooltip: 'Roll again',
            icon: const Icon(Icons.replay, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: widget.onReroll,
          ),
        if (widget.onOpenTool != null)
          IconButton(
            key: Key('entry-open-tool-${entry.id}'),
            tooltip: 'Open in tool',
            icon: const Icon(Icons.open_in_new, size: 20),
            visualDensity: VisualDensity.compact,
            onPressed: widget.onOpenTool,
          ),
        widget.menu,
      ],
    );
  }

  /// Collapsed one-line row, visually consistent with [DiceLogRow]: a small
  /// source icon + the one-line answer (serif, ellipsized) + a muted trailing
  /// roll summary + a compact reroll icon (a primary loop action — kept
  /// visible collapsed) + the overflow menu. Tapping the row body expands it.
  /// The collapsed-row body: rolled icons or drawn tarot cards render as image
  /// thumbnails (the result IS the image); everything else is a text one-liner.
  Widget _collapsedContent(JuiceTokens tk, JournalEntry entry, String oneLiner,
      String? rollSummary) {
    final p = entry.payload;
    if (p?['icons'] case final List<dynamic> icons when icons.isNotEmpty) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final a in icons.whereType<String>())
            Image.asset(a, width: 40, height: 40),
        ],
      );
    }
    // Drawn cards: a spread's card list, or a single card's summary.
    final shownStrings = <String>[
      if (p?['cards'] case final List<dynamic> cards)
        for (final c in cards.whereType<Map<dynamic, dynamic>>()) '${c['shown'] ?? ''}'
      else if (entry.sourceTool == 'cards' &&
          (entry.payload?['summary'] as String?)?.isNotEmpty == true)
        entry.payload!['summary'] as String,
    ];
    if (shownStrings.isNotEmpty) {
      return Wrap(
        spacing: 6,
        runSpacing: 6,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          for (final s in shownStrings)
            Builder(builder: (_) {
              final r = readTarot(s);
              return CardImage(r.name, reversed: r.reversed, height: 56);
            }),
        ],
      );
    }
    return Row(
      children: [
        Flexible(
          child: Text(
            oneLiner,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: tk.narrative.copyWith(
              fontSize: 15,
              fontWeight: FontWeight.w500,
              color: tk.ink,
            ),
          ),
        ),
        if (rollSummary != null)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Text(
              rollSummary,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: tk.uiLabel.copyWith(fontSize: 11, color: tk.inkMuted),
            ),
          ),
      ],
    );
  }

  Widget _collapsedRow(JuiceTokens tk, JournalEntry entry, String oneLiner,
      String? rollSummary) {
    return Padding(
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
            child:
                const Icon(Icons.auto_stories, size: 13, color: Colors.white),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: GestureDetector(
              key: Key('payload-expand-${entry.id}'),
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _expanded = true),
              // Icon-oracle / card entries ARE their images — show the rolled
              // icons or drawn cards in the collapsed row instead of text.
              child: _collapsedContent(tk, entry, oneLiner, rollSummary),
            ),
          ),
          if (widget.onReroll != null)
            IconButton(
              key: Key('entry-reroll-${entry.id}'),
              tooltip: 'Roll again',
              icon: const Icon(Icons.replay, size: 18),
              visualDensity: VisualDensity.compact,
              onPressed: widget.onReroll,
            ),
          widget.menu,
        ],
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
