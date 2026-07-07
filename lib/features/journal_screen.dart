import 'dart:async';
import 'dart:convert';
import 'dart:ui' as ui;

import 'package:file_picker/file_picker.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/command_registry.dart';
import '../engine/dice_notation.dart';
import '../engine/entity_suggestions.dart';
import '../engine/journal_export.dart';
import '../engine/journal_search.dart';
import '../engine/mention_parser.dart';
import '../engine/models.dart';
import '../engine/oracle_interpreter.dart';
import '../engine/sketch.dart';
import '../engine/tarot_spreads.dart';
import '../shared/ai_badge.dart';
import '../shared/ai_nudge_card.dart';
import '../shared/design_tokens.dart';
import '../shared/destination.dart';
import '../shared/dice_sheet.dart';
import '../shared/empty_state.dart';
import '../shared/help_nav.dart';
import '../shared/mention_text.dart';
import '../shared/shell_route.dart';
import '../state/blob_store.dart';
import '../state/interpreter.dart';
import '../state/pdf_rasterizer.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'ask_oracle_dialog.dart';
import 'assistant_rail.dart';
import 'generate_sheet.dart';
import 'inline_roll_dock.dart';
import 'journal_entry_tile.dart';
import 'oracle_interpretation_sheet.dart';
import 'reference_view.dart';
import '../engine/content_registry.dart';
import 'sketch_editor.dart';

/// The campaign journal: a forward-reading stream of entries (oldest at top)
/// with a composer pinned at the bottom for free-text and scene entries.
class JournalScreen extends ConsumerStatefulWidget {
  const JournalScreen({super.key});

  /// Save seam: tests swap this to capture (fileName, bytes) instead of
  /// opening the platform save dialog ([FilePicker.saveFile] is static).
  @visibleForTesting
  static Future<void> Function(String fileName, List<int> bytes) saveFile =
      defaultSaveFile;

  @visibleForTesting
  static Future<void> defaultSaveFile(String fileName, List<int> bytes) =>
      FilePicker.saveFile(
        dialogTitle: 'Export journal',
        fileName: fileName,
        type: FileType.custom,
        allowedExtensions: [fileName.split('.').last],
        bytes: Uint8List.fromList(bytes),
      );

  @override
  ConsumerState<JournalScreen> createState() => _JournalScreenState();
}

class _JournalScreenState extends ConsumerState<JournalScreen> {
  String? _filterThreadId;
  String? _filterTag;
  String? _filterCharId;
  bool _searching = false;
  final TextEditingController _composer = TextEditingController();
  final FocusNode _composerFocus = FocusNode();
  final TextEditingController _search = TextEditingController();
  Timer? _searchDebounce;
  // Drives the entry ListView so a dock roll can reveal the new newest entry.
  final ScrollController _entryScroll = ScrollController();
  final ScrollController _headerScroll = ScrollController();
  bool _slashActive = false;

  // Active @-mention query (text from the last '@' to the caret), or null.
  String? _mentionQuery;

  // True when the composer text is a question (trailing ?) and slash/mention
  // are not active.
  bool _askActive = false;

  // Recap "Returning to this campaign?" offer. Decided ONCE per campaign visit
  // (null until the journal first resolves) from the history present at entry,
  // so adding entries mid-session never re-triggers it; _recapDismissed hides
  // it for the rest of this visit. Both reset on a campaign switch.
  bool? _recapEligible;
  bool _recapDismissed = false;

  /// Minimum journal entries present at entry for the recap offer to appear —
  /// below this there's nothing worth recapping (a fresh/just-started game).
  static const _kRecapMinEntries = 5;

  // Built-in (non-registry) slash commands handled inline.
  static const _builtinScene = 'scene';
  static const _builtinHelp = 'help';
  static const _builtinAsk = 'ask';
  static const _builtinRecap = 'recap';
  static const _builtinCard = 'card';
  static const _builtinTarot = 'tarot';
  static const _builtinSpread = 'spread';
  static const _builtinRoll = 'roll';
  static const _builtinInspire = 'inspire';
  static const _builtinThread = 'thread';
  static const _builtinLookup = 'lookup';
  static const _builtinSpell = 'spell';
  static const _builtinMonster = 'monster';
  static const _builtinRules = 'rules';

  @override
  void initState() {
    super.initState();
    _composer.addListener(_onComposerChanged);
  }

  void _onComposerChanged() {
    final st =
        parseComposerState(_composer.text, _composer.selection.baseOffset);
    setState(() {
      _slashActive = st.slash;
      _mentionQuery = st.mention;
      _askActive = st.question;
    });
  }

  // -- Ask-anything helpers --------------------------------------------------

  String _fateCommandId(String oracle) => switch (oracle) {
        'mythic' => 'fate-mythic',
        'roll-high' => 'fate-roll-high',
        _ => 'fate-juice',
      };

  String _oddsLabel(String o) =>
      o.isEmpty ? o : '${o[0].toUpperCase()}${o.substring(1)}';

  Widget _askChip() => Align(
        alignment: Alignment.centerLeft,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
          child: ActionChip(
            key: const Key('ask-chip'),
            avatar: const Icon(Icons.psychology_alt_outlined, size: 18),
            label: const Text('Ask the oracle'),
            onPressed: () => _ask(_composer.text.trim()),
          ),
        ),
      );

  /// "Track this?" chips for recurring people the journal isn't tracking yet.
  Widget _suggestionRow() {
    final entries =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    if (entries.isEmpty) return const SizedBox.shrink();
    final existingChars = {
      for (final c
          in (ref.watch(charactersProvider).valueOrNull ?? const <Character>[]))
        c.name.toLowerCase()
    };
    final existingThreads = {
      for (final t
          in (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[]))
        t.title.toLowerCase()
    };
    final dismissed =
        ref.watch(dismissedSuggestionsProvider).valueOrNull ?? const <String>{};
    final suggestions = suggestEntities(entries,
            existingCharNames: existingChars,
            existingThreadTitles: existingThreads,
            dismissed: dismissed)
        .take(3)
        .toList();
    if (suggestions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 0, 12, 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 4,
        children: [
          for (final s in suggestions)
            InputChip(
              key: Key(
                  'suggest-${s.kind == SuggestionKind.character ? 'character' : 'thread'}-${s.name.toLowerCase()}'),
              avatar: Icon(
                  s.kind == SuggestionKind.character
                      ? Icons.person_add_alt
                      : Icons.bookmark_add_outlined,
                  size: 16),
              label: Text('Track ${s.name}?'),
              onPressed: () => _acceptSuggestion(s),
              onDeleted: () => ref
                  .read(dismissedSuggestionsProvider.notifier)
                  .dismiss(suggestionKey(s.kind, s.name)),
              deleteIcon: Icon(Icons.close,
                  key: Key('suggest-dismiss-${suggestionKey(s.kind, s.name)}'),
                  size: 16),
            ),
        ],
      ),
    );
  }

  Future<void> _acceptSuggestion(EntitySuggestion s) async {
    if (s.kind == SuggestionKind.character) {
      await ref.read(charactersProvider.notifier).addReturningId(s.name);
    } else {
      await ref.read(threadsProvider.notifier).addReturningId(s.name);
    }
  }

  /// Entries since the last scene divider (oldest first). Storage is
  /// newest-first; with no scene, the most recent ten entries are used.
  List<JournalEntry> _entriesSinceLastScene(List<JournalEntry> entries) {
    final since = <JournalEntry>[];
    for (final e in entries) {
      if (e.kind == JournalKind.scene) break;
      since.add(e);
    }
    final slice = since.isEmpty ? entries.take(10).toList() : since;
    return slice.reversed.toList(); // oldest first
  }

  Future<void> _recap() async {
    if (!_canVoice) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enable AI in Settings to recap.')));
      return;
    }
    final entries = ref.read(journalProvider).valueOrNull ?? const [];
    if (entries.isEmpty) return;
    final since = _entriesSinceLastScene(entries);
    final texts = [
      for (final e in since) e.title.isEmpty ? e.body : '${e.title}: ${e.body}',
    ];
    String summary;
    try {
      summary = await ref.read(interpreterServiceProvider).summarize(texts);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Recap failed: $e')));
      }
      return;
    }
    // Cache against the newest entry so the banner can reuse it, and mark seen.
    await ref
        .read(recapCacheProvider.notifier)
        .cacheSummary(entries.first.id, summary);
    if (!mounted) return;
    setState(() => _recapDismissed = true); // recapped — hide for this visit
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Previously…'),
        content: Text(summary),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            key: const Key('recap-save'),
            onPressed: () async {
              // Persist the recap so it's referenceable mid-session, then
              // re-mark the new newest entry seen so the banner doesn't re-nag.
              await ref.read(journalProvider.notifier).add('Recap', summary);
              final first = ref.read(journalProvider).valueOrNull?.firstOrNull;
              if (first != null) {
                await ref
                    .read(recapCacheProvider.notifier)
                    .cacheSummary(first.id, summary);
              }
              if (mounted) Navigator.pop(context);
            },
            child: const Text('Add to journal'),
          ),
        ],
      ),
    );
  }

  Future<void> _narrate(NarrateMode mode) async {
    if (!_canVoice) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Enable AI in Settings to narrate.')));
      return;
    }
    final journal = ref.read(journalProvider).valueOrNull ?? const [];
    // Recall ranks against the active scene (the pinned one, else newest) so it
    // matches the `sceneTitle` _sceneContext() sends; else the newest entry.
    final target = activeSceneEntry(journal,
            ref.read(playContextProvider).valueOrNull?.activeSceneId) ??
        journal.firstOrNull;
    final seed = NarrateSeed(
      mode: mode,
      sceneTitle: _sceneContext(),
      systemPrimer: ref.read(systemPrimerProvider),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journalContext: target == null ? const [] : recallLines(journal, target),
    );
    final String text;
    try {
      text = await ref.read(interpreterServiceProvider).narrate(seed);
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Narration failed: $e')));
      }
      return;
    }
    await ref.read(journalProvider.notifier).addResult(
          mode == NarrateMode.continueScene ? 'Narration' : 'Complication',
          text,
          sourceTool: 'narrate',
        );
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Added to journal')));
    }
  }

  /// /card and /tarot: draw from the persisted deck and log it (with the tarot
  /// meaning folded in), from the composer on any verb.
  Future<void> _drawCardCmd({required bool tarot}) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final g =
        await ref.read(decksProvider.notifier).drawAndLog(oracle, tarot: tarot);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Drew ${g.summary}')));
    }
  }

  /// Draws + logs a tarot spread from the composer; [arg] selects the spread
  /// (id/name; empty → 3-card default) via resolveSpread.
  Future<void> _drawSpreadCmd(String arg) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final spread = resolveSpread(arg);
    await ref.read(decksProvider.notifier).drawSpreadAndLog(oracle, spread);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Drew ${spread.name}')));
    }
  }

  /// /roll <expr>: parse [arg] as dice notation, roll it, and log a rerollable
  /// `dice` result entry (same pipeline as the inline-dice tap). An empty arg
  /// opens the full dice sheet instead.
  Future<void> _rollCmd(String arg) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final notation = arg.trim();
    if (notation.isEmpty) {
      unawaited(showDiceSheet(context, oracle.dice));
      return;
    }
    final DiceRollResult r;
    try {
      r = parseDice(notation).roll(oracle.dice);
    } on FormatException {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Bad dice notation, e.g. /roll 2d6+1')));
      }
      return;
    }
    final g = diceRollGenResult(r);
    await ref.read(journalProvider.notifier).addResult(
      g.title,
      g.asText,
      sourceTool: 'dice',
      payload: {...g.toPayload(), 'expression': r.expression},
    );
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${r.expression} = ${r.total}')));
    }
  }

  /// /inspire: opens the generators sheet (the same surface as composer-inspire).
  /// [arg] is accepted for forward-compat but the sheet has no preselect hook,
  /// so it just opens.
  void _inspireCmd(String arg) => showGenerateSheet(context);

  /// /thread <title>: creates a story thread with that title via the existing
  /// ThreadNotifier.add pipeline. An empty title navigates to the Track verb's
  /// threads pane so the normal new-thread flow is at hand.
  Future<void> _threadCmd(String arg) async {
    final title = arg.trim();
    if (title.isEmpty) {
      ref
          .read(shellRouteProvider.notifier)
          .goTo(Destination.track, subtab: 'threads');
      return;
    }
    await ref.read(threadsProvider.notifier).add(title);
    if (mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Tracking "$title"')));
    }
  }

  void _openReference(String query, ContentType type) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => Scaffold(
        appBar: AppBar(title: const Text('Reference')),
        body: ReferenceView(initialQuery: query, initialType: type),
      ),
    ));
  }

  /// One-shot contextual nudge to turn on the on-device AI: shown only while AI
  /// is supported on this platform, not yet ready (downloaded + enabled), and
  /// the player hasn't dismissed it. Loading states of all three gates count as
  /// "don't show".
  Widget _aiNudge() {
    final supported = ref.watch(aiSupportedProvider);
    final ready = ref.watch(aiReadyProvider);
    final seen = ref.watch(aiNudgeSeenProvider).valueOrNull ?? true;
    if (!supported || ready || seen) return const SizedBox.shrink();
    return const Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AiNudgeCard(),
        _AiFootnote(),
      ],
    );
  }

  /// "Previously on…" nudge shown when there are entries the player hasn't
  /// recapped since last visit (and the model is available to do it).
  Widget _recapBanner(List<JournalEntry> entries) {
    if (!_canVoice) return const SizedBox.shrink();
    // Permanently opted out via the banner's "Never" action.
    if (ref.watch(recapSuppressedProvider).valueOrNull ?? false) {
      return const SizedBox.shrink();
    }
    // Decide once per visit (first time the journal resolves): offer a recap
    // only when you ARRIVED with real history and haven't already seen the
    // newest entry. Captured so later entries don't re-trigger the banner.
    if (_recapEligible == null) {
      final cache = ref.read(recapCacheProvider).valueOrNull;
      _recapEligible = entries.length >= _kRecapMinEntries &&
          cache?.lastSeenId != entries.first.id;
    }
    if (_recapEligible != true || _recapDismissed) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    return Container(
      key: const Key('recap-banner'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(
        color: theme.colorScheme.secondaryContainer,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Icon(Icons.history_edu_outlined,
              size: 18, color: theme.colorScheme.onSecondaryContainer),
          const SizedBox(width: 8),
          const AiBadge(),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Returning to this campaign?',
                style: theme.textTheme.bodyMedium
                    ?.copyWith(color: theme.colorScheme.onSecondaryContainer)),
          ),
          TextButton(
            key: const Key('recap-action'),
            onPressed: _recap,
            child: const Text('Recap'),
          ),
          TextButton(
            key: const Key('recap-never'),
            onPressed: () {
              setState(() => _recapDismissed = true);
              ref.read(recapSuppressedProvider.notifier).markSeen();
            },
            child: const Text('Never'),
          ),
          IconButton(
            key: const Key('recap-dismiss'),
            visualDensity: VisualDensity.compact,
            icon: const Icon(Icons.close, size: 18),
            tooltip: 'Dismiss',
            onPressed: () {
              setState(() => _recapDismissed = true);
              ref.read(recapCacheProvider.notifier).markSeen(entries.first.id);
            },
          ),
        ],
      ),
    );
  }

  Future<void> _ask(String question) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null || question.isEmpty) return;
    // Await settings so defaultOracle is available even when called early.
    final CampaignSettings settings;
    if (ref.read(settingsProvider).hasValue) {
      settings = ref.read(settingsProvider).requireValue;
    } else {
      settings = await ref.read(settingsProvider.future);
    }
    if (!mounted) return;
    final ora = settings.defaultOracle;
    final opts = oddsForOracle(ora);
    // ignore: use_build_context_synchronously — mounted checked above
    final picked = await showDialog<String>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('How likely?'),
        children: [
          for (final o in opts)
            SimpleDialogOption(
              key: Key('ask-odds-$o'),
              onPressed: () => Navigator.pop(ctx, o),
              child: Text(_oddsLabel(o)),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final cmd = commandById(buildCommandRegistry(), _fateCommandId(ora));
    if (cmd == null) return;
    final args = <String, String>{'odds': picked};
    if (cmd.id == 'fate-mythic') {
      args['chaos'] =
          '${ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5}';
    }
    final r = cmd.run(oracle, args);
    _composer.clear();
    await ref.read(journalProvider.notifier).addResult(question, r.body,
        sourceTool: cmd.toolId, payload: r.payload);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _composer.removeListener(_onComposerChanged);
    _composer.dispose();
    _composerFocus.dispose();
    _search.dispose();
    _entryScroll.dispose();
    _headerScroll.dispose();
    super.dispose();
  }

  /// Reveals the newest entry after an inline dock roll. The entry ListView is
  /// `reverse: true` (newest anchored at the bottom = offset 0), so we animate
  /// to its minScrollExtent. Runs post-frame so the just-appended entry is laid
  /// out first.
  void _revealNewest() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_entryScroll.hasClients) return;
      _entryScroll.animateTo(
        _entryScroll.position.minScrollExtent,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOut,
      );
    });
  }

  // (The old empty-state blind-roll path + its fallback Suggestion were
  // retired by the stranger-test audit S1/S2 — the primary now opens the
  // ask-first oracle dialog; the dock keeps its own roll-oracle chip through
  // rollInlineSuggestion.)

  /// Opens a tool by id: dice gets its sheet, everything else navigates to its
  /// tab home (snackbar when the tool has no tab).
  void _openTool(String id) {
    if (id == 'dice') {
      final o = ref.read(oracleProvider).valueOrNull;
      if (o != null) showDiceSheet(context, o.dice);
      return;
    }
    if (!ref.read(shellRouteProvider.notifier).openTool(id)) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Tool not available')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(journalProvider);
    // Re-render AI affordances (Interpret / Voice / recap) as the AI-ready
    // state flips (download completes, toggle changes). _canVoice reads
    // aiReadyProvider; canInterpret reads interpretReadyProvider — both
    // watched here so either flip triggers a rebuild.
    ref.watch(aiReadyProvider);
    ref.watch(interpretReadyProvider);
    // Switching campaigns is a fresh "visit": re-decide the recap offer.
    ref.listen(sessionsProvider.select((s) => s.valueOrNull?.active),
        (prev, next) {
      if (prev != next) {
        setState(() {
          _recapEligible = null;
          _recapDismissed = false;
        });
      }
    });
    // Watch the oracle so payload entries gain their re-roll affordance once
    // it finishes loading (re-roll runs a command against it).
    ref.watch(oracleProvider);
    // Pre-subscribe so _mentionPanel() sees loaded data on first render.
    ref.watch(charactersProvider);
    // Lonelog notation highlighting in entry bodies, when the system is on.
    final lonelog =
        (ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
                kAllSystems)
            .contains('lonelog');
    final threads = (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        .where((t) => t.open)
        .toList();
    String threadTitle(String id) => threads
        .firstWhere((t) => t.id == id,
            orElse: () => Thread(id: id, title: '(closed thread)'))
        .title;
    // The fixed chrome above/below the entry list — the assistant rail, the
    // (conditional) slash/mention/ask panel, the suggestion row, the inline
    // roll dock, and the composer. At comfortable heights these take their
    // natural size and the entry list fills the gap via an Expanded. At very
    // short heights their sum alone can exceed the viewport; an Expanded would
    // then collapse to 0 and the fixed siblings overflow (the OUTER body case).
    // Below a threshold we instead scroll the WHOLE body and give the entry
    // list a bounded height, so nothing overflows and the composer stays
    // reachable at the bottom of the scroll.
    final entryRegion = async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (e, _) => Center(child: Text('Error: $e')),
      data: (entries) {
        if (entries.isEmpty) {
          // Directive orientation, not a takeover: the dock + composer
          // below the Expanded stay visible and usable. EmptyState is a
          // Center (bounded by the enclosing Expanded). Wrap it in a
          // scroll view sized to the region so it centers when there's
          // room but scrolls instead of overflowing when squeezed (the
          // shell's journal region can be short on small viewports).
          return LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: constraints.maxHeight),
                child: EmptyState(
                  icon: Icons.menu_book_outlined,
                  title: 'A blank page.',
                  // The premise, stated once, where a newcomer actually looks
                  // (stranger-test audit S5): no DM, you narrate, the oracle
                  // answers your questions.
                  body: "There's no DM here — you narrate. Ask a yes/no "
                      'question, roll, then write what happens.',
                  primaryLabel: 'Ask the oracle',
                  onPrimary: () => showAskOracleDialog(context, ref),
                  secondaryLabel: 'Write a line',
                  onSecondary: () => _composerFocus.requestFocus(),
                ),
              ),
            ),
          );
        }
        // Storage is newest-first; a reversed ListView reads forward
        // (oldest at top) while anchoring the viewport at the newest
        // entry, chat-style.
        final tags = ref.watch(allTagsProvider);
        // Characters referenced by mentions anywhere in the journal.
        // Cached by mentionedCharIdsProvider — one parse per entry per journal tick.
        final charMentions = ref.watch(mentionedCharIdsProvider);
        final mentionedChars = <String>{
          for (final s in charMentions.values) ...s,
        };
        final chars =
            (ref.watch(charactersProvider).valueOrNull ?? const <Character>[])
                .where((c) => mentionedChars.contains(c.id))
                .toList();
        var visible = _filterThreadId == null
            ? entries
            : entries.where((e) => e.threadId == _filterThreadId).toList();
        if (_filterTag != null) {
          visible = visible.where((e) => e.tags.contains(_filterTag)).toList();
        }
        if (_filterCharId != null) {
          visible = visible
              .where(
                  (e) => charMentions[e.id]?.contains(_filterCharId) ?? false)
              .toList();
        }
        if (_searching) {
          visible = searchEntries(visible, _search.text);
        }
        // The fixed top group (nudge / recap / filters / actions /
        // search) sits above the entry list. At comfortable heights it
        // takes its natural size and the entry ListView fills the rest.
        // When the region is short the group is capped at the available
        // height and scrolls internally (rather than squeezing the entry
        // Expanded below zero and overflowing). The ListView keeps its
        // own Expanded + reverse-anchoring + _entryScroll either way.
        return LayoutBuilder(
          builder: (context, constraints) => Column(
            children: [
              ConstrainedBox(
                constraints: BoxConstraints(maxHeight: constraints.maxHeight),
                // The visible thumb is what tells a first-time user the header
                // group (Solo Loop steps etc.) continues past the fold — the
                // expanded Steps panel used to clip with no affordance at all
                // (stranger-test audit S3).
                child: Scrollbar(
                  controller: _headerScroll,
                  thumbVisibility: true,
                  child: SingleChildScrollView(
                    controller: _headerScroll,
                    child: Column(
                      children: [
                        _aiNudge(),
                        _recapBanner(entries),
                        if (threads.isNotEmpty ||
                            tags.isNotEmpty ||
                            chars.isNotEmpty)
                          _filterChips(threads, tags, chars),
                        _journalActions(),
                        if (_searching) _searchField(),
                      ],
                    ),
                  ),
                ),
              ),
              Expanded(
                child: ListView.builder(
                  controller: _entryScroll,
                  reverse: true,
                  padding: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  itemCount: visible.length,
                  itemBuilder: (context, i) =>
                      _entry(visible[i], threads, threadTitle, lonelog),
                ),
              ),
            ],
          ),
        );
      },
    );

    // The chrome that sits below the entry region — order preserved exactly.
    final belowEntry = <Widget>[
      if (_slashActive)
        _slashPalette()
      else if (_mentionQuery != null)
        _mentionPanel()
      else if (_askActive)
        _askChip(),
      _suggestionRow(),
      InlineRollDock(onRolled: _revealNewest),
      _composerBar(),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        // Below this height the fixed chrome (rail + panel + suggestion row +
        // dock + composer) can sum taller than the viewport, so an Expanded
        // entry region would collapse to 0 and the chrome would overflow. The
        // observed max fixed chrome (collapsed rail, full suggestion row, dock,
        // multi-line composer affordances) is ~290px; below `kJournalScrollFallback`
        // we scroll the whole body and give the entry list a bounded minimum so
        // nothing overflows and the composer stays reachable. Above it, the
        // current Expanded-fills layout (with reverse-anchoring + _entryScroll)
        // is used unchanged.
        const kJournalScrollFallback = 360.0;
        const kJournalEntryRegionMin = 120.0;
        if (constraints.maxHeight.isFinite &&
            constraints.maxHeight < kJournalScrollFallback) {
          return SingleChildScrollView(
            child: Column(
              children: [
                const AssistantRail(),
                SizedBox(height: kJournalEntryRegionMin, child: entryRegion),
                ...belowEntry,
              ],
            ),
          );
        }
        return Column(
          children: [
            const AssistantRail(),
            Expanded(child: entryRegion),
            ...belowEntry,
          ],
        );
      },
    );
  }

  /// Horizontal filter strip: All + open threads + tags + mentioned characters.
  Widget _filterChips(
          List<Thread> threads, List<String> tags, List<Character> chars) =>
      SizedBox(
        height: 48,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
          children: [
            Padding(
              padding: const EdgeInsets.only(right: 8),
              child: FilterChip(
                label: const Text('All'),
                selected: _filterThreadId == null &&
                    _filterTag == null &&
                    _filterCharId == null,
                onSelected: (_) => setState(() {
                  _filterThreadId = null;
                  _filterTag = null;
                  _filterCharId = null;
                }),
              ),
            ),
            for (final t in threads)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  label: Text(t.title),
                  selected: _filterThreadId == t.id,
                  onSelected: (_) => setState(() => _filterThreadId = t.id),
                ),
              ),
            for (final tag in tags)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  key: Key('tag-chip-$tag'),
                  label: Text('#$tag'),
                  selected: _filterTag == tag,
                  onSelected: (_) => setState(
                      () => _filterTag = _filterTag == tag ? null : tag),
                ),
              ),
            for (final c in chars)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: FilterChip(
                  key: Key('char-filter-${c.id}'),
                  avatar: const Icon(Icons.person, size: 16),
                  label: Text(c.name),
                  selected: _filterCharId == c.id,
                  onSelected: (_) => setState(() =>
                      _filterCharId = _filterCharId == c.id ? null : c.id),
                ),
              ),
          ],
        ),
      );

  /// Search / export / clear actions above the entry list.
  Widget _journalActions() => Padding(
        padding: const EdgeInsets.fromLTRB(0, 0, 8, 0),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            IconButton(
              key: const Key('journal-new-session'),
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Start a new session',
              onPressed: _newSession,
            ),
            IconButton(
              key: const Key('journal-search'),
              icon: const Icon(Icons.search),
              tooltip: 'Search journal',
              onPressed: () => setState(() {
                _searching = !_searching;
                if (!_searching) _search.clear();
              }),
            ),
            IconButton(
              key: const Key('journal-export'),
              icon: const Icon(Icons.ios_share),
              tooltip: 'Export journal…',
              onPressed: _export,
            ),
            TextButton.icon(
              icon: const Icon(Icons.clear_all),
              label: const Text('Clear'),
              onPressed: _confirmClear,
            ),
          ],
        ),
      );

  /// The expandable journal search field (shown while [_searching]).
  Widget _searchField() => Padding(
        padding: const EdgeInsets.fromLTRB(12, 0, 12, 8),
        child: TextField(
          key: const Key('journal-search-field'),
          controller: _search,
          autofocus: true,
          decoration: InputDecoration(
            hintText: 'Search journal…',
            border: const OutlineInputBorder(),
            isDense: true,
            suffixIcon: IconButton(
              icon: const Icon(Icons.close),
              tooltip: 'Close search',
              onPressed: () => setState(() {
                _search.clear();
                _searching = false;
              }),
            ),
          ),
          onChanged: (_) {
            // Debounced: searchEntries re-scans the journal in build(), so
            // don't rebuild on every keystroke.
            _searchDebounce?.cancel();
            _searchDebounce = Timer(const Duration(milliseconds: 250), () {
              if (mounted) setState(() {});
            });
          },
        ),
      );

  // -- Entry rendering ------------------------------------------------------

  bool _isDialogShaped(JournalEntry e) =>
      e.body.contains('"') ||
      e.sourceTool == 'gen-npcs' ||
      e.sourceTool == 'sidekick-dialogue';

  // AI affordances stay hidden until the model is downloaded AND enabled in
  // Settings. build() watches aiReadyProvider so these reads rebuild on flip.
  bool get _canVoice => ref.read(aiReadyProvider);

  /// The per-entry overflow menu. [onCard] is set for the result hero card,
  /// whose Interpret/Voice actions live on an inline action row instead — so
  /// those two items are suppressed there to avoid duplicate affordances.
  PopupMenuButton<String> _entryMenu(JournalEntry e, List<Thread> threads,
      {bool onCard = false}) {
    final canInterpret =
        e.kind == JournalKind.result && ref.read(interpretReadyProvider);
    final saveAs = _saveAsKind(e);
    return PopupMenuButton<String>(
      onSelected: (action) => _onAction(action, e, threads),
      itemBuilder: (_) => [
        if (!onCard && canInterpret)
          const PopupMenuItem(value: 'interpret', child: Text('Interpret…')),
        if (!onCard && _canVoice && _isDialogShaped(e))
          const PopupMenuItem(value: 'voice', child: Text('Voice…')),
        if (saveAs != null)
          PopupMenuItem(
              value: 'save-entity',
              child: Text(saveAs == MentionKind.character
                  ? 'Save as character'
                  : 'Save as thread')),
        const PopupMenuItem(value: 'link', child: Text('Link to thread…')),
        const PopupMenuItem(value: 'tags', child: Text('Tags…')),
        // Sketches edit in place via tap on the thumbnail, not the text editor.
        if (e.kind != JournalKind.sketch)
          const PopupMenuItem(value: 'edit', child: Text('Edit note…')),
        const PopupMenuItem(value: 'delete', child: Text('Delete')),
      ],
    );
  }

  Widget _entry(JournalEntry e, List<Thread> threads,
      String Function(String) threadTitle, bool lonelog) {
    // Interpret/Voice move onto the result hero card's inline action row, so the
    // hero card's menu suppresses them (`onCard: true`); every other weight
    // (prose, fallback result, scene) keeps them reachable via the menu.
    final menu = _entryMenu(e, threads);
    switch (e.kind) {
      case JournalKind.scene:
        final theme = Theme.of(context);
        final tk = context.juice;
        final num = _sceneNumber(e);
        // Eyebrow: "SCENE 3 · The gatehouse · CHAOS 5" with chaos tinted.
        final eyebrow = tk.uiLabel.copyWith(
          fontSize: 11,
          fontWeight: FontWeight.w700,
          letterSpacing: 1.2,
          color: tk.inkMuted,
        );
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                children: [
                  Expanded(child: Divider(color: tk.hairline)),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Text.rich(
                      TextSpan(
                        style: eyebrow,
                        children: [
                          TextSpan(
                              text: num != null
                                  ? 'SCENE $num · ${e.title.toUpperCase()}'
                                  : e.title.toUpperCase()),
                          if (e.chaosFactor != null) ...[
                            const TextSpan(text: ' · '),
                            TextSpan(
                                text: 'CHAOS ${e.chaosFactor}',
                                style: eyebrow.copyWith(color: tk.chaos)),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Expanded(child: Divider(color: tk.hairline)),
                  menu,
                ],
              ),
              if (e.body.trim().isNotEmpty)
                Padding(
                  key: Key('scene-body-${e.id}'),
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 0),
                  child: Text(e.body, style: theme.textTheme.bodyMedium),
                ),
            ],
          ),
        );
      case JournalKind.session:
        final theme = Theme.of(context);
        return Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: Row(
            children: [
              const Expanded(child: Divider(thickness: 2)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.flag_outlined,
                      size: 16, color: theme.colorScheme.primary),
                  const SizedBox(width: 4),
                  Text(e.title,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.bold)),
                ]),
              ),
              const Expanded(child: Divider(thickness: 2)),
              menu,
            ],
          ),
        );
      case JournalKind.text:
        final extras = _suffixLines(e, threadTitle);
        final tk = context.juice;
        // Prose weight: quiet italic narrative, no card — plain notes sit back
        // so result heroes carry the visual weight. The overflow menu stays
        // reachable via a compact trailing button.
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    MentionText(
                      e.body,
                      style: tk.narrative.copyWith(
                        fontSize: 14.5,
                        fontStyle: FontStyle.italic,
                        color: tk.inkBody,
                      ),
                      onCharacterTap: _openCharacter,
                      onThreadTap: _openThread,
                      onDiceTap: _rollDice,
                      lonelog: lonelog,
                    ),
                    if (extras.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 4),
                        child: Text(
                          extras.join('\n'),
                          style: tk.uiLabel
                              .copyWith(fontSize: 11, color: tk.inkMuted),
                        ),
                      ),
                  ],
                ),
              ),
              menu,
            ],
          ),
        );
      case JournalKind.result:
        final extras = _suffixLines(e, threadTitle);
        final p = e.payload;
        // Compact dice/log weight: a slim raised row instead of a hero card so
        // mechanical rolls don't shout. Branch before the hero card.
        if (e.sourceTool == 'dice') {
          return DiceLogRow(
            entry: e,
            menu: menu,
            onReroll: _canReroll(e) ? () => _reroll(e) : null,
          );
        }
        if (p != null && p['v'] == 1 && p['rolls'] is List) {
          final canInterpret = ref.read(interpretReadyProvider);
          return PayloadCard(
            entry: e,
            extras: extras,
            // Hero card menu drops Interpret/Voice — those ride the inline row.
            menu: _entryMenu(e, threads, onCard: true),
            onReroll: _canReroll(e) ? () => _reroll(e) : null,
            onOpenTool:
                (e.sourceTool != null && toolLocation.containsKey(e.sourceTool))
                    ? () => _openTool(e.sourceTool!)
                    : null,
            onInterpret: canInterpret ? () => _interpret(e) : null,
            onVoice:
                (_canVoice && _isDialogShaped(e)) ? () => _voiceEntry(e) : null,
            onTogglePin: () =>
                ref.read(journalProvider.notifier).togglePin(e.id),
            onCharacterTap: _openCharacter,
            onThreadTap: _openThread,
            onDiceTap: _rollDice,
            lonelog: lonelog,
          );
        }
        return Card(
          child: ListTile(
            title: Text(e.title),
            subtitle: MentionText(
              [e.body, ...extras].join('\n'),
              onCharacterTap: _openCharacter,
              onThreadTap: _openThread,
              onDiceTap: _rollDice,
              lonelog: lonelog,
            ),
            trailing: menu,
            isThreeLine: e.body.contains('\n') || extras.isNotEmpty,
          ),
        );
      case JournalKind.sketch:
        final data = SketchData.fromJson(
            (e.payload?['sketch'] as Map?)?.cast<String, dynamic>() ??
                const {});
        return Card(
          child: InkWell(
            onTap: () => _openSketch(e, data),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SizedBox(
                  key: Key('sketch-thumb-${e.id}'),
                  height: 180,
                  child: SketchThumbnail(data),
                ),
                Row(
                  children: [
                    const Padding(
                      padding: EdgeInsets.only(left: 12),
                      child: Text('Sketch'),
                    ),
                    const Spacer(),
                    menu,
                  ],
                ),
              ],
            ),
          ),
        );
    }
  }

  bool _canReroll(JournalEntry e) {
    final p = e.payload;
    if (p == null || ref.read(oracleProvider).valueOrNull == null) return false;
    // Registry-command rolls replay the command; dice-roller rolls replay their
    // notation (the `expression` payload).
    return (p['rerollable'] == true && p['command'] is String) ||
        p['expression'] is String;
  }

  Future<void> _reroll(JournalEntry e) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    final p = e.payload;
    if (oracle == null || p == null) return;
    // Dice-roller entries carry a dice `expression` (no command): re-parse + roll.
    if (p['command'] is! String && p['expression'] is String) {
      final DiceRollResult r;
      try {
        r = parseDice(p['expression'] as String).roll(oracle.dice);
      } on FormatException {
        return;
      }
      final g = diceRollGenResult(r);
      await ref.read(journalProvider.notifier).addResult(g.title, g.asText,
          sourceTool: e.sourceTool,
          payload: {...g.toPayload(), 'expression': r.expression});
      return;
    }
    final cmd = commandById(buildCommandRegistry(), p['command'] as String);
    if (cmd == null) return;
    final args = <String, String>{
      for (final entry in ((p['args'] as Map?) ?? const {}).entries)
        '${entry.key}': '${entry.value}',
    };
    if (cmd.id == 'fate-mythic') {
      args['chaos'] =
          '${ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5}';
    }
    final r = cmd.run(oracle, args);
    await ref.read(journalProvider.notifier).addResult(r.title, r.body,
        sourceTool: e.sourceTool, payload: r.payload);
  }

  /// Runs a registry command from the palette: rolls against the loaded
  /// oracle and drops a structured entry. Mythic pulls live chaos.
  Future<void> _runCommand(CommandDef cmd,
      {String? odds, String? notation}) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final args = <String, String>{};
    if (odds != null) args['odds'] = odds;
    if (notation != null) args['notation'] = notation;
    if (cmd.id == 'fate-mythic') {
      args['chaos'] =
          '${ref.read(crawlProvider).valueOrNull?.chaosFactor ?? 5}';
    }
    try {
      final r = cmd.run(oracle, args);
      await ref.read(journalProvider.notifier).addResult(r.title, r.body,
          sourceTool: cmd.toolId, payload: r.payload);
    } on FormatException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(e.message)));
    }
  }

  /// Card-subtitle suffix lines: the `⤷ thread` link, then the `#a #b` tags.
  List<String> _suffixLines(
          JournalEntry e, String Function(String) threadTitle) =>
      [
        if (e.threadId != null) '⤷ ${threadTitle(e.threadId!)}',
        if (e.tags.isNotEmpty) e.tags.map((t) => '#$t').join(' '),
      ];

  /// 1-based index of a scene entry among all scene entries, in chronological
  /// (oldest-first) order — drives the "SCENE 3" eyebrow. Null if not found.
  int? _sceneNumber(JournalEntry scene) {
    final entries = ref.read(journalProvider).valueOrNull;
    if (entries == null) return null;
    // Storage is newest-first; reverse to chronological then enumerate scenes.
    final scenes = entries.reversed
        .where((e) => e.kind == JournalKind.scene)
        .toList(growable: false);
    final idx = scenes.indexWhere((e) => e.id == scene.id);
    return idx < 0 ? null : idx + 1;
  }

  // -- Slash palette ----------------------------------------------------------

  Widget _slashPalette() {
    final parsed = parseSlash(_composer.text);
    if (parsed == null) return const SizedBox.shrink();
    final systems =
        ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
            kAllSystems;
    final registry = commandsForSystems(buildCommandRegistry(), systems);
    // Built-ins surface when their name prefixes the token.
    final tok = parsed.token.toLowerCase();
    final cardsOn = systems.contains('cards');
    final showScene = _builtinScene.startsWith(tok);
    final showHelp = _builtinHelp.startsWith(tok);
    final showAsk = _builtinAsk.startsWith(tok);
    final showRecap = _builtinRecap.startsWith(tok) && _canVoice;
    final showCard = _builtinCard.startsWith(tok) && cardsOn;
    final showTarot = _builtinTarot.startsWith(tok) && cardsOn;
    final showSpread = _builtinSpread.startsWith(tok) && cardsOn;
    final showRoll = _builtinRoll.startsWith(tok);
    final showInspire = _builtinInspire.startsWith(tok);
    final showThread = _builtinThread.startsWith(tok);
    final showLookup = _builtinLookup.startsWith(tok);
    final showSpell = _builtinSpell.startsWith(tok);
    final showMonster = _builtinMonster.startsWith(tok);
    final showRules = _builtinRules.startsWith(tok);
    final matches = matchCommands(registry, parsed.token);
    final theme = Theme.of(context);
    final tk = context.juice;
    return Material(
      key: const Key('slash-palette'),
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            for (final c in matches)
              _SlashRow(
                command: c,
                notation: parsed.rest,
                onRun: ({String? odds}) => _selectCommand(c, odds: odds),
              ),
            if (showScene)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-scene'),
                icon: Icons.movie_outlined,
                command: '/scene',
                description: 'Start a new scene',
                onTap: () {
                  _composer.clear();
                  _newScene();
                },
              ),
            if (showRoll)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-roll'),
                icon: Icons.casino_outlined,
                command: '/roll',
                description: parsed.rest.trim().isEmpty
                    ? 'Roll dice — add notation, e.g. /roll 2d6+1'
                    : 'Roll ${parsed.rest.trim()}',
                onTap: () {
                  final rest = parsed.rest;
                  _composer.clear();
                  _rollCmd(rest);
                },
              ),
            if (showInspire)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-inspire'),
                icon: Icons.auto_awesome,
                command: '/inspire',
                description: 'Open the generators',
                onTap: () {
                  _composer.clear();
                  _inspireCmd(parsed.rest);
                },
              ),
            if (showThread)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-thread'),
                icon: Icons.bookmark_add_outlined,
                command: '/thread',
                description: parsed.rest.trim().isEmpty
                    ? 'Track a thread — add a title, e.g. /thread The heist'
                    : 'Track "${parsed.rest.trim()}"',
                onTap: () {
                  final rest = parsed.rest;
                  _composer.clear();
                  _threadCmd(rest);
                },
              ),
            if (showHelp)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-help'),
                icon: Icons.help_outline,
                command: '/help',
                description: 'Open Help',
                onTap: () {
                  _composer.clear();
                  openHelp(context, ref);
                },
              ),
            if (showAsk)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-ask'),
                icon: Icons.psychology_alt_outlined,
                command: '/ask',
                description: 'Ask the oracle — type your question after /ask',
                onTap: () {
                  final question = parsed.rest.trim();
                  if (question.isNotEmpty) {
                    _ask(question);
                  }
                  // If no question typed yet, leave the composer so user can
                  // type their question.
                },
              ),
            if (showRecap)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-recap'),
                icon: Icons.history_edu_outlined,
                command: '/recap',
                description: 'Recap recent play',
                onTap: () {
                  _composer.clear();
                  _recap();
                },
              ),
            if (showCard)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-card'),
                icon: Icons.style_outlined,
                command: '/card',
                description: 'Draw a card',
                onTap: () {
                  _composer.clear();
                  _drawCardCmd(tarot: false);
                },
              ),
            if (showTarot)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-tarot'),
                icon: Icons.auto_awesome,
                command: '/tarot',
                description: 'Draw a tarot card',
                onTap: () {
                  _composer.clear();
                  _drawCardCmd(tarot: true);
                },
              ),
            if (showSpread)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-spread'),
                icon: Icons.dashboard_outlined,
                command: '/spread',
                description:
                    'Draw a tarot spread — add a name, e.g. /spread celtic',
                onTap: () {
                  _composer.clear();
                  _drawSpreadCmd('');
                },
              ),
            if (showLookup)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-lookup'),
                icon: Icons.menu_book_outlined,
                command: '/lookup',
                description: 'Look up any spell or monster',
                onTap: () {
                  _composer.clear();
                  _openReference('', ContentType.all);
                },
              ),
            if (showSpell)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-spell'),
                icon: Icons.auto_fix_high_outlined,
                command: '/spell',
                description: 'Look up a spell',
                onTap: () {
                  _composer.clear();
                  _openReference('', ContentType.spells);
                },
              ),
            if (showMonster)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-monster'),
                icon: Icons.pest_control_outlined,
                command: '/monster',
                description: 'Look up a monster',
                onTap: () {
                  _composer.clear();
                  _openReference('', ContentType.monsters);
                },
              ),
            if (showRules)
              _BuiltinSlashRow(
                rowKey: const Key('slash-cmd-rules'),
                icon: Icons.menu_book,
                command: '/rules',
                description: 'Rules quick reference for this system',
                onTap: () {
                  _composer.clear();
                  _openReference('', ContentType.rules);
                },
              ),
            if (matches.isEmpty &&
                !showScene &&
                !showHelp &&
                !showAsk &&
                !showRecap &&
                !showCard &&
                !showTarot &&
                !showSpread &&
                !showRoll &&
                !showInspire &&
                !showThread &&
                !showLookup &&
                !showSpell &&
                !showMonster &&
                !showRules)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Text('No matching command',
                    style: tk.uiLabel.copyWith(color: tk.inkMuted)),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _selectCommand(CommandDef c, {String? odds}) async {
    final parsed = parseSlash(_composer.text);
    _composer.clear(); // also flips _slashActive off via the listener
    await _runCommand(c,
        odds: odds,
        notation: c.arg == CommandArg.notation ? (parsed?.rest ?? '') : null);
  }

  // -- Mention autocomplete ---------------------------------------------------

  void _insertMention(String display, MentionKind kind, String id) {
    final text = _composer.text;
    final rawSel = _composer.selection.baseOffset;
    final sel = rawSel < 0 ? text.length : rawSel;
    final at = text.substring(0, sel).lastIndexOf('@');
    final token = '${mentionToken(display, kind, id)} ';
    final next = text.replaceRange(at, sel, token);
    _composer.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: at + token.length),
    );
    setState(() => _mentionQuery = null);
  }

  Widget _mentionPanel() {
    final query = _mentionQuery ?? '';
    final lower = query.toLowerCase();
    final chars =
        (ref.watch(charactersProvider).valueOrNull ?? const <Character>[])
            .where((c) => c.name.toLowerCase().contains(lower))
            .toList();
    final threads = (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        .where((t) => t.open && t.title.toLowerCase().contains(lower))
        .toList();
    if (chars.isEmpty && threads.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Material(
      key: const Key('mention-panel'),
      color: theme.colorScheme.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Container(
        constraints: const BoxConstraints(maxHeight: 280),
        margin: const EdgeInsets.fromLTRB(12, 0, 12, 4),
        child: ListView(
          shrinkWrap: true,
          padding: const EdgeInsets.symmetric(vertical: 4),
          children: [
            if (chars.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: Text('Characters',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              for (final c in chars)
                ListTile(
                  key: Key('mention-char-${c.id}'),
                  dense: true,
                  leading: const Icon(Icons.person_outline, size: 18),
                  title: Text(c.name),
                  onTap: () =>
                      _insertMention(c.name, MentionKind.character, c.id),
                ),
            ],
            if (threads.isNotEmpty) ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 2),
                child: Text('Threads',
                    style: theme.textTheme.labelSmall
                        ?.copyWith(color: theme.colorScheme.onSurfaceVariant)),
              ),
              for (final t in threads)
                ListTile(
                  key: Key('mention-thread-${t.id}'),
                  dense: true,
                  leading: const Icon(Icons.link, size: 18),
                  title: Text(t.title),
                  onTap: () =>
                      _insertMention(t.title, MentionKind.thread, t.id),
                ),
            ],
          ],
        ),
      ),
    );
  }

  // -- Sketch / image annotation ----------------------------------------------

  /// Opens a sketch, resolving its background image (if any) from the blob store
  /// first so the editor reopens over the same image.
  Future<void> _openSketch(JournalEntry e, SketchData data) async {
    final id = data.backgroundBlobId;
    ui.Image? bg;
    if (id != null && ref.read(blobStoreAvailableProvider)) {
      bg = await decodeSketchBackground(
          await ref.read(blobStoreProvider).get(id));
    }
    try {
      if (!mounted) return;
      final edited = await showSketchEditor(context,
          initial: data,
          background: bg,
          backgroundBlobId: id,
          pdfBlobId: data.pdfBlobId,
          pdfPage: data.pdfPage);
      if (edited != null) {
        await ref
            .read(journalProvider.notifier)
            .replace(e.copyWith(payload: {'v': 1, 'sketch': edited.toJson()}));
      }
    } finally {
      // We own the decoded image; release it after the editor's exit
      // transition (disposing inline races the pop animation).
      disposeSketchBackgroundLater(bg);
    }
  }

  /// Import an image, store it as a blob, and annotate it in the sketch editor.
  Future<void> _annotateImage() async {
    if (!ref.read(blobStoreAvailableProvider)) return;
    final result =
        await FilePicker.pickFiles(type: FileType.image, withData: true);
    final file = result?.files.singleOrNull;
    final bytes = file?.bytes;
    if (bytes == null) return;
    final blobId =
        await ref.read(blobStoreProvider).put(bytes, ext: file?.extension);
    final bg = await decodeSketchBackground(bytes);
    try {
      if (!mounted) return;
      final data = await showSketchEditor(context,
          background: bg, backgroundBlobId: blobId);
      if (data != null && !data.isEmpty) {
        await ref.read(journalProvider.notifier).addSketch(data);
      }
    } finally {
      disposeSketchBackgroundLater(bg); // after the editor's exit transition
    }
    // A cancelled import leaves an orphan blob; blob GC is a later epic step
    // (BlobStore.list() supports it) — kept simple here to avoid deleting a
    // content-addressed blob another sketch may share.
  }

  /// Import a PDF, render a chosen page to a cached raster, and annotate it.
  Future<void> _annotatePdf() async {
    if (!ref.read(blobStoreAvailableProvider) ||
        !ref.read(pdfAvailableProvider)) {
      return;
    }
    final result = await FilePicker.pickFiles(
        type: FileType.custom,
        allowedExtensions: const ['pdf'],
        withData: true);
    final bytes = result?.files.singleOrNull?.bytes;
    if (bytes == null) return;
    final store = ref.read(blobStoreProvider);
    final rasterizer = ref.read(pdfRasterizerProvider);
    final pdfBlobId = await store.put(bytes, ext: 'pdf');
    final pages = await rasterizer.pageCount(bytes);
    if (!mounted) return;
    if (pages <= 0) {
      _snack('Could not read that PDF.');
      return;
    }
    final page = pages == 1 ? 0 : await _pickPdfPage(pages);
    if (page == null) return; // cancelled the page picker
    final png = await rasterizer.renderPage(bytes, page);
    if (png == null) {
      if (mounted) _snack('Could not render that page.');
      return;
    }
    final bgBlobId = await store.put(png, ext: 'png');
    final bg = await decodeSketchBackground(png);
    try {
      if (!mounted) return;
      final data = await showSketchEditor(context,
          background: bg,
          backgroundBlobId: bgBlobId,
          pdfBlobId: pdfBlobId,
          pdfPage: page);
      if (data != null && !data.isEmpty) {
        await ref.read(journalProvider.notifier).addSketch(data);
      }
    } finally {
      disposeSketchBackgroundLater(bg); // after the editor's exit transition
    }
  }

  void _snack(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  /// Simple page chooser for multi-page PDFs; returns a 0-based index or null.
  Future<int?> _pickPdfPage(int pages) => showDialog<int>(
        context: context,
        builder: (context) => SimpleDialog(
          title: const Text('Choose a page'),
          children: [
            for (var i = 0; i < pages; i++)
              SimpleDialogOption(
                key: Key('pdf-page-$i'),
                onPressed: () => Navigator.pop(context, i),
                child: Text('Page ${i + 1}'),
              ),
          ],
        ),
      );

  // -- Composer ---------------------------------------------------------------

  /// Subtle "/" affordance that hints the slash-command palette exists. Tapping
  /// it inserts `/` and opens the palette (same state the keyboard `/` drives).
  Widget _slashHint() {
    final tk = context.juice;
    return Tooltip(
      message: 'Slash commands',
      child: InkWell(
        key: const Key('slash-hint'),
        onTap: _openSlashPalette,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
          decoration: BoxDecoration(
            color: tk.card,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: tk.hairline),
          ),
          child: Text('/',
              style: tk.uiLabel.copyWith(
                  color: tk.terracotta,
                  fontSize: 18,
                  fontWeight: FontWeight.w600,
                  height: 1.0)),
        ),
      ),
    );
  }

  /// Seeds the composer with `/` and places the caret after it, opening the
  /// slash palette via the composer listener.
  void _openSlashPalette() {
    _composer.value = const TextEditingValue(
      text: '/',
      selection: TextSelection.collapsed(offset: 1),
    );
  }

  Widget _composerBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 4, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            _slashHint(),
            const SizedBox(width: 4),
            Expanded(
              child: TextField(
                key: const Key('journal-composer'),
                controller: _composer,
                focusNode: _composerFocus,
                minLines: 1,
                maxLines: 4,
                textCapitalization: TextCapitalization.sentences,
                decoration: const InputDecoration(
                  hintText: 'Write in your journal…',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
                onSubmitted: (_) => _send(),
              ),
            ),
            IconButton(
              key: const Key('composer-dice'),
              icon: const Icon(Icons.casino_outlined),
              tooltip: 'Roll dice',
              onPressed: () {
                final oracle = ref.read(oracleProvider).valueOrNull;
                if (oracle != null) showDiceSheet(context, oracle.dice);
              },
            ),
            IconButton(
              key: const Key('composer-inspire'),
              icon: const Icon(Icons.auto_awesome),
              tooltip: 'Inspire (generators)',
              onPressed: () => showGenerateSheet(context),
            ),
            if (ref.watch(aiReadyProvider))
              PopupMenuButton<NarrateMode>(
                key: const Key('composer-narrate'),
                icon: const AiBadge(),
                tooltip: 'GM narration (AI)',
                onSelected: _narrate,
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    key: Key('narrate-continue'),
                    value: NarrateMode.continueScene,
                    child: Text('Continue the scene'),
                  ),
                  PopupMenuItem(
                    key: Key('narrate-complication'),
                    value: NarrateMode.complication,
                    child: Text('Add a complication'),
                  ),
                ],
              ),
            IconButton(
              key: const Key('composer-draw'),
              icon: const Icon(Icons.draw_outlined),
              tooltip: 'Draw a sketch',
              onPressed: () async {
                final data = await showSketchEditor(context);
                if (data != null && !data.isEmpty) {
                  await ref.read(journalProvider.notifier).addSketch(data);
                }
              },
            ),
            // Annotate-an-image needs the blob store (file-backed); hidden on web
            // until an IndexedDB store lands (blobStoreAvailableProvider).
            if (ref.watch(blobStoreAvailableProvider))
              IconButton(
                key: const Key('composer-annotate-image'),
                icon: const Icon(Icons.image_outlined),
                tooltip: 'Annotate an image',
                onPressed: _annotateImage,
              ),
            // Annotate a PDF page; needs the blob store + a PDF rasterizer
            // (desktop/mobile — hidden on web for now).
            if (ref.watch(blobStoreAvailableProvider) &&
                ref.watch(pdfAvailableProvider))
              IconButton(
                key: const Key('composer-annotate-pdf'),
                icon: const Icon(Icons.picture_as_pdf_outlined),
                tooltip: 'Annotate a PDF',
                onPressed: _annotatePdf,
              ),
            IconButton(
              key: const Key('journal-send'),
              icon: const Icon(Icons.send),
              tooltip: 'Add to journal',
              onPressed: _send,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _send() async {
    final text = _composer.text;
    if (text.startsWith('/')) {
      // Enter runs the first matching command (built-ins win when they
      // exactly head the token); otherwise the palette stays open.
      final parsed = parseSlash(text)!;
      final tok = parsed.token.toLowerCase();
      // A bare '/' with no command typed shouldn't silently fire a roll.
      if (tok.isEmpty) return;
      if (_builtinScene == tok) {
        _composer.clear();
        await _newScene();
        return;
      }
      if (_builtinHelp == tok) {
        _composer.clear();
        if (mounted) openHelp(context, ref);
        return;
      }
      if (_builtinRecap == tok) {
        _composer.clear();
        await _recap();
        return;
      }
      if (_builtinCard == tok) {
        _composer.clear();
        await _drawCardCmd(tarot: false);
        return;
      }
      if (_builtinTarot == tok) {
        _composer.clear();
        await _drawCardCmd(tarot: true);
        return;
      }
      if (_builtinSpread == tok) {
        _composer.clear();
        await _drawSpreadCmd(parsed.rest);
        return;
      }
      if (_builtinAsk == tok) {
        final question = parsed.rest.trim();
        if (question.isNotEmpty) await _ask(question);
        return;
      }
      if (_builtinRoll == tok) {
        _composer.clear();
        await _rollCmd(parsed.rest);
        return;
      }
      if (_builtinInspire == tok) {
        _composer.clear();
        _inspireCmd(parsed.rest);
        return;
      }
      if (_builtinThread == tok) {
        _composer.clear();
        await _threadCmd(parsed.rest);
        return;
      }
      if (_builtinLookup == tok) {
        _composer.clear();
        _openReference(parsed.rest.trim(), ContentType.all);
        return;
      }
      if (_builtinSpell == tok) {
        _composer.clear();
        _openReference(parsed.rest.trim(), ContentType.spells);
        return;
      }
      if (_builtinMonster == tok) {
        _composer.clear();
        _openReference(parsed.rest.trim(), ContentType.monsters);
        return;
      }
      if (_builtinRules == tok) {
        _composer.clear();
        _openReference('', ContentType.rules);
        return;
      }
      final systems =
          ref.read(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
              kAllSystems;
      final matches = matchCommands(
          commandsForSystems(buildCommandRegistry(), systems), parsed.token);
      if (matches.isNotEmpty) await _selectCommand(matches.first);
      return;
    }
    final trimmed = text.trim();
    if (trimmed.isEmpty) return;
    _composer.clear();
    await ref.read(journalProvider.notifier).addText(trimmed);
  }

  Future<void> _export() async {
    final built = await _buildExport();
    if (built == null) return;
    final (fileName, content) = built;
    try {
      await JournalScreen.saveFile(fileName, utf8.encode(content));
    } on PlatformException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Could not access files: ${e.message}')),
      );
    }
  }

  /// Format dialog + document building. Returns the (fileName, content) the
  /// save seam would write, or null when the user cancels.
  Future<(String, String)?> _buildExport() async {
    final format = await showDialog<String>(
      context: context,
      builder: (context) => SimpleDialog(
        title: const Text('Export journal'),
        children: [
          SimpleDialogOption(
            key: const Key('export-markdown'),
            onPressed: () => Navigator.pop(context, 'md'),
            child: const Text('Markdown'),
          ),
          SimpleDialogOption(
            key: const Key('export-html'),
            onPressed: () => Navigator.pop(context, 'html'),
            child: const Text('HTML'),
          ),
        ],
      ),
    );
    if (format == null || !mounted) return null;
    final entries =
        ref.read(journalProvider).valueOrNull ?? const <JournalEntry>[];
    // All threads, open AND closed, so closed-thread links keep their titles.
    final allThreads =
        ref.read(threadsProvider).valueOrNull ?? const <Thread>[];
    final threadTitles = {for (final t in allThreads) t.id: t.title};
    final name =
        ref.read(sessionsProvider).valueOrNull?.activeMeta.name ?? 'campaign';
    final content = format == 'md'
        ? journalToMarkdown(
            campaignName: name,
            entriesNewestFirst: entries,
            threadTitles: threadTitles,
            exportedAt: DateTime.now())
        : journalToHtml(
            campaignName: name,
            entriesNewestFirst: entries,
            threadTitles: threadTitles,
            exportedAt: DateTime.now());
    return ('${slugify(name)}-journal.$format', content);
  }

  Future<void> _confirmClear() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Clear journal?'),
        content:
            const Text("This deletes every entry in this campaign's journal."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
              foregroundColor: Theme.of(context).colorScheme.onError,
            ),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Clear'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    await ref.read(journalProvider.notifier).clear();
  }

  Future<void> _newSession() async {
    final entries = ref.read(journalProvider).valueOrNull ?? const [];
    final n = entries.where((e) => e.kind == JournalKind.session).length + 1;
    await ref.read(journalProvider.notifier).addSessionBreak('Session $n');
  }

  Future<void> _newScene() async {
    final title = await showDialog<String>(
      context: context,
      builder: (context) => const _SceneDialog(),
    );
    if (!mounted) return;
    if (title == null || title.trim().isEmpty) return;
    final id = await ref.read(journalProvider.notifier).addScene(
          title.trim(),
          chaosFactor: ref.read(crawlProvider).valueOrNull?.chaosFactor,
        );
    await ref.read(playContextProvider.notifier).setActiveScene(id);
  }

  // -- Entry actions ----------------------------------------------------------

  /// Which entity a result entry can be saved as, or null. NPC results
  /// become characters; exploration/location results become threads.
  MentionKind? _saveAsKind(JournalEntry e) {
    if (e.kind != JournalKind.result) return null;
    return switch (e.sourceTool) {
      'gen-npcs' => MentionKind.character,
      'gen-exploration' => MentionKind.thread,
      _ => null,
    };
  }

  Future<void> _saveAsEntity(JournalEntry entry) async {
    // Only reached via the gated menu item, but an explicit guard beats a
    // force-unwrap if that gating ever changes.
    final kind = _saveAsKind(entry);
    if (kind == null) return;
    final name = entry.payload?['summary'] as String? ??
        (entry.payload?['rolls'] as List?)
            ?.cast<Map<String, dynamic>>()
            .firstOrNull?['display'] as String? ??
        entry.title;
    final id = kind == MentionKind.character
        ? await ref.read(charactersProvider.notifier).addReturningId(name)
        : await ref.read(threadsProvider.notifier).addReturningId(name);
    // Re-read fresh so the backfill can't clobber a concurrent edit.
    final fresh = (ref.read(journalProvider).valueOrNull ?? const [])
        .where((x) => x.id == entry.id)
        .firstOrNull;
    if (fresh == null) return;
    await ref.read(journalProvider.notifier).replace(
        fresh.copyWith(body: '${fresh.body}\n${mentionToken(name, kind, id)}'));
  }

  Future<void> _onAction(
      String action, JournalEntry entry, List<Thread> threads) async {
    final notifier = ref.read(journalProvider.notifier);
    switch (action) {
      case 'interpret':
        await _interpret(entry);
      case 'voice':
        await _voiceEntry(entry);
      case 'save-entity':
        await _saveAsEntity(entry);
      case 'delete':
        await notifier.remove(entry.id);
      case 'link':
        final picked = await showDialog<String>(
          context: context,
          builder: (context) => SimpleDialog(
            title: const Text('Link to thread'),
            children: [
              SimpleDialogOption(
                onPressed: () => Navigator.of(context).pop('__none__'),
                child: const Text('No thread'),
              ),
              for (final t in threads)
                SimpleDialogOption(
                  onPressed: () => Navigator.of(context).pop(t.id),
                  child: Text(t.title),
                ),
            ],
          ),
        );
        if (picked == null) return;
        await notifier.replace(picked == '__none__'
            ? entry.copyWith(clearThreadId: true)
            : entry.copyWith(threadId: picked));
      case 'tags':
        final updated = await showDialog<List<String>>(
          context: context,
          builder: (_) => _TagsDialog(initial: entry.tags),
        );
        if (updated == null) return;
        await notifier.replace(entry.copyWith(tags: updated));
      case 'edit':
        final result = await showDialog<({String title, String note})>(
          context: context,
          builder: (_) => _EditDialog(
            heading: 'Edit journal entry',
            labelA: 'Title',
            labelB: 'Note',
            initialA: entry.title,
            initialB: entry.body,
          ),
        );
        if (result == null) return;
        // Text entries have no title; a scene's title is required but its
        // description (body) is optional. Require only the content-carrier.
        final relevant =
            entry.kind == JournalKind.text ? result.note : result.title;
        if (relevant.trim().isEmpty) return;
        await notifier.replace(entry.kind == JournalKind.text
            ? entry.copyWith(body: result.note)
            : entry.copyWith(title: result.title.trim(), body: result.note));
    }
  }

  void _openCharacter(String id) {
    ref.read(playContextProvider.notifier).setActiveCharacter(id);
    ref
        .read(shellRouteProvider.notifier)
        .goTo(Destination.sheet, subtab: 'characters');
  }

  void _openThread(String id) => setState(() => _filterThreadId = id);

  /// Rolls an inline dice token tapped in journal prose and logs it as a
  /// rerollable `dice` entry (same pipeline as the dice-roller reroll).
  void _rollDice(String notation) {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final DiceRollResult r;
    try {
      r = parseDice(notation).roll(oracle.dice);
    } on FormatException {
      return; // scanDice already validated; stay defensive
    }
    final g = diceRollGenResult(r);
    ref.read(journalProvider.notifier).addResult(
      g.title,
      g.asText,
      sourceTool: 'dice',
      payload: {...g.toPayload(), 'expression': r.expression},
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('${r.expression} = ${r.total}')),
    );
  }

  /// Current scene as model context — uses the spine's pinned [activeSceneId]
  /// when set (falling back to the newest scene entry via [activeSceneEntry]).
  String _sceneContext() {
    final journal = ref.read(journalProvider).valueOrNull ?? const [];
    final scene = activeSceneEntry(
        journal, ref.read(playContextProvider).valueOrNull?.activeSceneId);
    if (scene == null) return '';
    final chaos =
        scene.chaosFactor != null ? ' (Chaos ${scene.chaosFactor})' : '';
    return 'Scene: ${scene.title}$chaos';
  }

  Future<void> _interpret(JournalEntry entry) async {
    // Recall: the most relevant past entries ride into the prompt so
    // readings can reference established NPCs, places, and threads.
    final journal = ref.read(journalProvider).valueOrNull ?? const [];
    final seed = OracleSeed(
      resultText:
          entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
      sceneContext: _sceneContext(),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journalContext: recallLines(journal, entry),
    );
    final accepted = await showModalBottomSheet<OracleInterpretation>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) => OracleInterpretationSheet(
        seed: seed,
        onAccept: (card) => Navigator.pop(sheetContext, card),
      ),
    );
    if (accepted == null || !mounted) return;
    // The sheet can stay open a long time; re-read the entry so the append
    // can't clobber concurrent edits or resurrect a deleted entry.
    final fresh = (ref.read(journalProvider).valueOrNull ?? const [])
        .where((e) => e.id == entry.id)
        .firstOrNull;
    if (fresh == null) return;
    await ref.read(journalProvider.notifier).replace(fresh.copyWith(
        body:
            '${fresh.body}\n\n— Oracle reading (${accepted.lens}): ${accepted.reading}'));
  }

  Future<void> _voiceEntry(JournalEntry entry) async {
    final settings =
        ref.read(settingsProvider).valueOrNull ?? const CampaignSettings();
    final journal = ref.read(journalProvider).valueOrNull ?? const [];
    final seed = VoiceSeed(
      line: entry.title.isEmpty ? entry.body : '${entry.title}\n${entry.body}',
      mood: 'default',
      genre: settings.genre,
      toneSetting: settings.tone,
      systemPrimer: ref.read(systemPrimerProvider),
      activeCharacter: ref.read(activeCharacterLineProvider),
      journalContext: recallLines(journal, entry),
    );
    String? voiced;
    try {
      voiced = await ref.read(interpreterServiceProvider).voiceLine(seed);
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Could not voice: $e')));
      return;
    }
    if (voiced.trim().isEmpty || !mounted) return;
    // Re-read fresh so the append can't clobber concurrent edits.
    final fresh = (ref.read(journalProvider).valueOrNull ?? const [])
        .where((x) => x.id == entry.id)
        .firstOrNull;
    if (fresh == null) return;
    await ref
        .read(journalProvider.notifier)
        .replace(fresh.copyWith(body: '${fresh.body}\n\n— Voiced: $voiced'));
  }
}

// -- Tags dialog ---------------------------------------------------------------
/// Edits an entry's tag list locally; pops the updated list on Save, null on
/// Cancel. Add-tag flow mirrors the character sheet's (tracker_screen.dart).
class _TagsDialog extends StatefulWidget {
  const _TagsDialog({required this.initial});
  final List<String> initial;

  @override
  State<_TagsDialog> createState() => _TagsDialogState();
}

class _TagsDialogState extends State<_TagsDialog> {
  late final List<String> _tags = [...widget.initial];

  Future<void> _addTag() async {
    final tagCtrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('Add tag'),
          content: TextField(
            key: const Key('tag-input'),
            controller: tagCtrl,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Tag'),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(context, tagCtrl.text),
              child: const Text('Add'),
            ),
          ],
        );
      },
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => tagCtrl.dispose());
    // Preserve case (search compares case-insensitively); dedupe exact.
    final tag = result?.trim() ?? '';
    if (tag.isEmpty || _tags.contains(tag)) return;
    setState(() => _tags.add(tag));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Tags'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_tags.isEmpty)
            const Text('No tags yet.')
          else
            Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final tag in _tags)
                  InputChip(
                    label: Text(tag),
                    onDeleted: () => setState(() => _tags.remove(tag)),
                  ),
              ],
            ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('add-tag'),
            icon: const Icon(Icons.add),
            label: const Text('Add tag'),
            onPressed: _addTag,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _tags),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// -- Scene dialog -------------------------------------------------------------
class _SceneDialog extends StatefulWidget {
  const _SceneDialog();

  @override
  State<_SceneDialog> createState() => _SceneDialogState();
}

class _SceneDialogState extends State<_SceneDialog> {
  final TextEditingController _title = TextEditingController();

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New scene'),
      content: TextField(
        controller: _title,
        autofocus: true,
        decoration: const InputDecoration(labelText: 'Scene title'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, _title.text),
          child: const Text('Start scene'),
        ),
      ],
    );
  }
}

// -- Edit dialog ---------------------------------------------------------------
class _EditDialog extends StatefulWidget {
  const _EditDialog({
    required this.heading,
    required this.labelA,
    required this.labelB,
    required this.initialA,
    required this.initialB,
  });
  final String heading;
  final String labelA;
  final String labelB;
  final String initialA;
  final String initialB;

  @override
  State<_EditDialog> createState() => _EditDialogState();
}

class _EditDialogState extends State<_EditDialog> {
  late final TextEditingController _a =
      TextEditingController(text: widget.initialA);
  late final TextEditingController _b =
      TextEditingController(text: widget.initialB);

  @override
  void dispose() {
    _a.dispose();
    _b.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.heading),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _a,
            autofocus: true,
            decoration: InputDecoration(labelText: widget.labelA),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _b,
            maxLines: 3,
            minLines: 1,
            decoration: InputDecoration(labelText: widget.labelB),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () =>
              Navigator.pop(context, (title: _a.text, note: _b.text)),
          child: const Text('Save'),
        ),
      ],
    );
  }
}

// -- Slash row ----------------------------------------------------------------

class _SlashRow extends StatefulWidget {
  const _SlashRow(
      {required this.command, required this.notation, required this.onRun});
  final CommandDef command;
  final String notation;
  final void Function({String? odds}) onRun;

  @override
  State<_SlashRow> createState() => _SlashRowState();
}

class _SlashRowState extends State<_SlashRow> {
  bool _expanded = false;

  // A fate command's `system` is its oracle name (juice/mythic/roll-high).
  List<String> get _oddsOptions => oddsForOracle(widget.command.system);

  @override
  Widget build(BuildContext context) {
    final c = widget.command;
    final tk = context.juice;
    final hasOdds = c.arg == CommandArg.odds;
    final description = c.arg == CommandArg.notation
        ? (widget.notation.isEmpty
            ? 'Type dice notation, e.g. /dice 3d6+2'
            : 'Roll ${widget.notation}')
        : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        ListTile(
          key: Key('slash-cmd-${c.id}'),
          dense: true,
          // Highlight the row while its odds chips are expanded.
          tileColor: _expanded ? tk.sand : null,
          leading: _SlashIconTile(icon: _commandIcon(c.id)),
          title: Text(c.label, style: tk.uiLabel),
          subtitle: description == null
              ? null
              : Text(description,
                  style: tk.uiLabel.copyWith(fontSize: 12, color: tk.inkMuted)),
          trailing:
              hasOdds ? Icon(Icons.tune, size: 18, color: tk.inkMuted) : null,
          onTap: () {
            if (hasOdds) {
              setState(() => _expanded = !_expanded);
            } else {
              widget.onRun();
            }
          },
        ),
        if (hasOdds && _expanded)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final o in _oddsOptions)
                  ActionChip(
                    key: Key('slash-odds-$o'),
                    label: Text(o == 'normal'
                        ? 'Normal'
                        : (o.isNotEmpty
                            ? '${o[0].toUpperCase()}${o.substring(1)}'
                            : o)),
                    onPressed: () => widget.onRun(odds: o),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Icon for a registry command row, keyed by command id.
IconData _commandIcon(String id) => switch (id) {
      'fate-juice' ||
      'fate-mythic' ||
      'fate-roll-high' =>
        Icons.help_center_outlined,
      'dice' => Icons.casino_outlined,
      'meaning' => Icons.lightbulb_outline,
      'name' => Icons.badge_outlined,
      'detail' => Icons.auto_awesome,
      _ => Icons.bolt_outlined,
    };

/// Small tinted square that holds a palette-row icon, for a uniform leading
/// affordance across registry and built-in slash rows.
class _SlashIconTile extends StatelessWidget {
  const _SlashIconTile({required this.icon});
  final IconData icon;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        color: tk.card,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tk.hairline),
      ),
      alignment: Alignment.center,
      child: Icon(icon, size: 18, color: tk.terracotta),
    );
  }
}

/// A tokened palette row for a built-in slash command: an icon tile, the
/// command text in [JuiceTokens.uiLabel], and a muted description. Highlights
/// in [JuiceTokens.sand] while pressed (parity with the registry row).
class _BuiltinSlashRow extends StatelessWidget {
  const _BuiltinSlashRow({
    required this.rowKey,
    required this.icon,
    required this.command,
    required this.description,
    required this.onTap,
  });

  final Key rowKey;
  final IconData icon;
  final String command;
  final String description;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    return ListTile(
      key: rowKey,
      dense: true,
      leading: _SlashIconTile(icon: icon),
      title: Text(command, style: tk.uiLabel),
      subtitle: Text(description,
          style: tk.uiLabel.copyWith(fontSize: 12, color: tk.inkMuted)),
      onTap: onTap,
    );
  }
}

/// The single legend explaining the ✦ marker, shown under the AI-enable nudge.
class _AiFootnote extends StatelessWidget {
  const _AiFootnote();

  @override
  Widget build(BuildContext context) {
    final tk = context.juice;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
      child: Text(
        '✦ marks an AI-assisted action · all on-device',
        style: tk.uiLabel.copyWith(fontSize: 11, color: tk.inkMuted),
      ),
    );
  }
}
