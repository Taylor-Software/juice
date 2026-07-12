import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/constructed_oracle.dart';
import '../engine/dice.dart';
import '../engine/models.dart';
import '../engine/oracle.dart';
import '../features/generate_sheet.dart';
import '../features/oracle_roll_sheet.dart';
import '../features/scene_jump_sheet.dart';
import '../state/play_context.dart';
import '../state/providers.dart';
import 'design_tokens.dart';
import 'destination.dart';
import 'shell_route.dart';

/// A thin, always-visible play-context bar mounted at the shell level (above
/// the verb body), so the current scene, Chaos factor, default oracle, pinned
/// threads and starred characters stay reachable on every verb — not just the
/// Journal. Reads the [PlayContext] spine: the scene line follows
/// `activeSceneId` when set (falling back to the latest scene entry).
///
/// Was `_CampaignHeader` inside `JournalScreen`; lifted to the shell so it no
/// longer vanishes when switching verbs or when the journal is empty.
class CampaignHeader extends ConsumerWidget {
  const CampaignHeader({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings =
        ref.watch(settingsProvider).valueOrNull ?? const CampaignSettings();
    final entries = ref.watch(journalProvider).valueOrNull ?? const [];
    final threads = (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        .where((t) => t.open && t.pinned)
        .toList();
    final stars =
        (ref.watch(charactersProvider).valueOrNull ?? const <Character>[])
            .where((c) => c.starred)
            .toList();
    final crawl = ref.watch(crawlProvider).valueOrNull;
    final oracle = ref.watch(oracleProvider).valueOrNull;
    final oracles =
        ref.watch(constructedOraclesProvider).valueOrNull ?? const [];
    // Current scene: prefer the spine's active pointer, fall back to the latest
    // scene entry (storage newest-first).
    final scene = activeSceneEntry(
        entries, ref.watch(playContextProvider).valueOrNull?.activeSceneId);
    // Chaos belongs to Mythic — show it only when the campaign's profile
    // enables that system.
    final systems =
        ref.watch(sessionsProvider).valueOrNull?.activeMeta.enabledSystems ??
            kAllSystems;
    final usesMythic = systems.contains('mythic');
    final theme = Theme.of(context);
    final tk = context.juice;
    final light = ref.watch(lightProvider).valueOrNull ?? 0;
    final compact = MediaQuery.sizeOf(context).width < kCompactWidth;
    // While the journal composer has focus on a phone the expanded row yields
    // its space to the keyboard (the collapse is visual only — the persisted
    // setting is untouched and the row returns on blur).
    final typing = compact && ref.watch(journalComposerFocusProvider);
    final collapsed = settings.headerCollapsed || typing;
    return Container(
      key: const Key('campaign-header'),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            Icon(Icons.local_fire_department_outlined,
                size: 16, color: theme.colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              // Tap the scene line to open the scene jump list (scrolls the
              // journal back to any scene divider).
              child: InkWell(
                key: const Key('hdr-scene-jump'),
                onTap: () => showSceneJumpSheet(context),
                child: Text(
                  scene?.title ?? 'No scene yet',
                  style: theme.textTheme.labelLarge,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ),
            // Narrative-state Chaos value — always visible (tier 1), even when
            // the roll-controls (steppers in tier 2) are collapsed. Gated to
            // Mythic campaigns like the steppers below.
            if (usesMythic && crawl != null) ...[
              Chip(
                key: const Key('hdr-chaos'),
                visualDensity: VisualDensity.compact,
                backgroundColor: tk.chaosChipBg,
                side: BorderSide.none,
                label: Text(
                  'Chaos ${crawl.chaosFactor}',
                  style: theme.textTheme.labelMedium
                      ?.copyWith(color: tk.chaosChipText),
                ),
              ),
              const SizedBox(width: 6),
            ],
            // One-tap roll of the default oracle from any verb — the loop's
            // most frequent action, always reachable (even when collapsed).
            IconButton(
              key: const Key('hdr-quick-roll'),
              visualDensity: VisualDensity.compact,
              icon: Icon(_quickRollIcon(settings.defaultOracle)),
              tooltip:
                  'Quick roll (${_oracleLabel(settings.defaultOracle, oracles)})',
              onPressed: oracle == null
                  ? null
                  : () {
                      // Draw-style oracles open a roll sheet (count / deck /
                      // spread + animation); yes/no oracles roll instantly.
                      const drawKinds = {'icons', 'cards', 'tarot'};
                      if (drawKinds.contains(settings.defaultOracle)) {
                        showOracleRollSheet(
                            context, oracle, settings.defaultOracle);
                      } else {
                        _quickRoll(context, ref, oracle,
                            crawl?.chaosFactor ?? 5, settings.defaultOracle);
                      }
                    },
            ),
            IconButton(
              key: const Key('hdr-collapse'),
              visualDensity: VisualDensity.compact,
              icon: Icon(collapsed ? Icons.expand_more : Icons.expand_less),
              tooltip: collapsed ? 'Expand' : 'Collapse',
              onPressed: () => ref
                  .read(settingsProvider.notifier)
                  .setHeaderCollapsed(!collapsed),
            ),
          ]),
          if (!collapsed)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: _expandedRow(
                compact,
                [
                  // Global light timer — a neutral player-controlled countdown,
                  // no duration asserted. De-noised: the chip + steppers show
                  // only while a timer is running; an idle campaign gets a
                  // single muted start chip at the END of the row instead
                  // (most campaigns never track light).
                  if (light > 0) ...[
                    InputChip(
                      backgroundColor: tk.card,
                      side: BorderSide.none,
                      avatar: Icon(Icons.local_fire_department,
                          size: 16, color: theme.colorScheme.primary),
                      label: Text('Light $light',
                          style: TextStyle(color: tk.inkMuted)),
                      onPressed: null,
                    ),
                    IconButton(
                      key: const Key('hdr-light-dec'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: () =>
                          ref.read(lightProvider.notifier).set(light - 1),
                    ),
                    IconButton(
                      key: const Key('hdr-light-inc'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: () =>
                          ref.read(lightProvider.notifier).set(light + 1),
                    ),
                  ],
                  if (usesMythic && crawl != null) ...[
                    // Roll-control: the Chaos steppers (value itself lives in
                    // the always-visible tier-1 chip above — not duplicated).
                    Text('Chaos',
                        style: theme.textTheme.labelMedium
                            ?.copyWith(color: tk.inkMuted)),
                    IconButton(
                      key: const Key('hdr-chaos-dec'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.remove, size: 18),
                      onPressed: crawl.chaosFactor > 1
                          ? () => ref
                              .read(crawlProvider.notifier)
                              .setChaos(crawl.chaosFactor - 1)
                          : null,
                    ),
                    IconButton(
                      key: const Key('hdr-chaos-inc'),
                      visualDensity: VisualDensity.compact,
                      icon: const Icon(Icons.add, size: 18),
                      onPressed: crawl.chaosFactor < 9
                          ? () => ref
                              .read(crawlProvider.notifier)
                              .setChaos(crawl.chaosFactor + 1)
                          : null,
                    ),
                  ],
                  ActionChip(
                    key: const Key('hdr-oracle'),
                    backgroundColor: tk.card,
                    side: BorderSide.none,
                    avatar: Icon(Icons.casino_outlined,
                        size: 16, color: tk.inkMuted),
                    label: Text(_oracleLabel(settings.defaultOracle, oracles),
                        style: TextStyle(color: tk.inkMuted)),
                    onPressed: () => _pickOracle(context, ref, settings),
                  ),
                  for (final t in threads)
                    ActionChip(
                      key: Key('hdr-thread-${t.id}'),
                      avatar: const Icon(Icons.push_pin, size: 14),
                      label: Text(t.title),
                      onPressed: () => ref
                          .read(shellRouteProvider.notifier)
                          .goTo(Destination.track, subtab: 'threads'),
                    ),
                  for (final c in stars)
                    ActionChip(
                      key: Key('hdr-char-${c.id}'),
                      avatar: const Icon(Icons.star, size: 14),
                      label: Text(c.name),
                      onPressed: () => ref
                          .read(shellRouteProvider.notifier)
                          .goTo(Destination.sheet, subtab: 'characters'),
                    ),
                  if (crawl != null && crawl.envRow != null)
                    ActionChip(
                      key: const Key('hdr-crawl'),
                      backgroundColor: tk.card,
                      side: BorderSide.none,
                      avatar: Icon(Icons.explore, size: 14, color: tk.inkMuted),
                      label: Text(
                          crawl.lost ? 'Wilderness (lost)' : 'Wilderness',
                          style: TextStyle(color: tk.inkMuted)),
                      onPressed: () => showGenerateSheet(context),
                    ),
                  if (light == 0)
                    Tooltip(
                      message: 'Start a light timer',
                      child: ActionChip(
                        key: const Key('hdr-light-start'),
                        backgroundColor: tk.card,
                        side: BorderSide.none,
                        avatar: Icon(Icons.local_fire_department_outlined,
                            size: 16, color: tk.inkMuted),
                        label:
                            Text('Light', style: TextStyle(color: tk.inkMuted)),
                        onPressed: () =>
                            ref.read(lightProvider.notifier).set(1),
                      ),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  /// The expanded (tier-2) control row. Wide screens wrap so everything is
  /// visible at once; phones keep it to ONE horizontally-scrolling line so
  /// pinned threads + starred characters can't stack the header several rows
  /// deep on the narrowest screens.
  Widget _expandedRow(bool compact, List<Widget> children) => compact
      ? SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              for (final w in children)
                Padding(padding: const EdgeInsets.only(right: 8), child: w),
            ],
          ),
        )
      : Wrap(
          spacing: 8,
          runSpacing: 4,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: children,
        );

  /// Prefix marking a constructed-oracle id in `settings.defaultOracle`.
  static const _coPrefix = 'co:';

  static String _oracleLabel(String id, List<ConstructedOracle> oracles) {
    if (id.startsWith(_coPrefix)) {
      final oid = id.substring(_coPrefix.length);
      final o = oracles.where((x) => x.id == oid).firstOrNull;
      return o == null ? 'Oracle' : (o.name.isEmpty ? 'Oracle' : o.name);
    }
    return switch (id) {
      'mythic' => 'Mythic',
      'icons' => 'Icons',
      'cards' => 'Cards',
      'tarot' => 'Tarot',
      'roll-high' => 'Roll High', // legacy campaigns; no longer offered
      _ => 'Juice',
    };
  }

  /// Rolls the campaign's default oracle exactly like the HUD quick-roll
  /// button; shared by the desktop Cmd/Ctrl+R shortcut. No-op while the
  /// oracle is still loading.
  static Future<void> quickRollDefault(
      BuildContext context, WidgetRef ref) async {
    final oracle = ref.read(oracleProvider).valueOrNull;
    if (oracle == null) return;
    final CampaignSettings settings = ref.read(settingsProvider).valueOrNull ??
        await ref.read(settingsProvider.future);
    final crawl = ref.read(crawlProvider).valueOrNull;
    if (!context.mounted) return;
    const drawKinds = {'icons', 'cards', 'tarot'};
    if (drawKinds.contains(settings.defaultOracle)) {
      await showOracleRollSheet(context, oracle, settings.defaultOracle);
    } else {
      await const CampaignHeader()._quickRoll(context, ref, oracle,
          crawl?.chaosFactor ?? 5, settings.defaultOracle);
    }
  }

  /// Icon reflecting the current default oracle: a card glyph for cards/tarot,
  /// dice otherwise (icons/juice/mythic/custom/constructed).
  static IconData _quickRollIcon(String defaultOracle) =>
      const {'cards', 'tarot'}.contains(defaultOracle)
          ? Icons.style_outlined
          : Icons.casino_outlined;

  Future<void> _quickRoll(BuildContext context, WidgetRef ref, Oracle oracle,
      int chaos, String defaultOracle) async {
    // Cards + tarot draw-and-log through the deck (which persists the draw
    // itself); a snackbar then confirms.
    if (defaultOracle == 'cards' || defaultOracle == 'tarot') {
      final g = await ref
          .read(decksProvider.notifier)
          .drawAndLog(oracle, tarot: defaultOracle == 'tarot');
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Drew ${g.summary}')));
      }
      return;
    }

    final GenResult g;
    final String tool;
    Map<String, dynamic>? payload;
    if (defaultOracle.startsWith(_coPrefix)) {
      final oid = defaultOracle.substring(_coPrefix.length);
      final oracles =
          ref.read(constructedOraclesProvider).valueOrNull ?? const [];
      final o = oracles.where((x) => x.id == oid).firstOrNull;
      if (o == null) {
        // The default points at a deleted oracle — fall back to Juice.
        g = fateCheckGenResult(oracle.fateCheck(Likelihood.normal));
        tool = 'fate-check';
      } else {
        g = oracleGenResult(o, OracleLikelihood.fiftyFifty, oracle.dice);
        tool = 'constructed-oracle';
      }
    } else {
      switch (defaultOracle) {
        case 'mythic':
          g = oracle.mythicFate(4, chaos); // 50/50 odds
          tool = 'mythic';
        case 'icons':
          final ic = oracle.abstractIcon();
          g = GenResult(title: 'Story Dice', rolls: [
            Roll(label: 'Icon', value: 'd10 ${d10Label(ic.d10)}, d6 ${ic.d6}'),
          ]);
          tool = 'gen-abstract-icon';
          payload = {
            ...g.toPayload(),
            'icons': [ic.asset]
          };
        case 'roll-high':
          g = oracle.rollHigh('d100', 3); // Unknown odds (legacy default)
          tool = 'roll-high';
        default:
          g = fateCheckGenResult(oracle.fateCheck(Likelihood.normal));
          tool = 'fate-check';
      }
    }
    await ref.read(journalProvider.notifier).addResult(g.title, g.asText,
        sourceTool: tool, payload: payload ?? g.toPayload());
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(
              g.summary ?? (g.rolls.isEmpty ? g.title : g.rolls.first.value))));
    }
  }

  Future<void> _pickOracle(
      BuildContext context, WidgetRef ref, CampaignSettings s) async {
    final oracles =
        ref.read(constructedOraclesProvider).valueOrNull ?? const [];
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Default oracle'),
        children: [
          for (final o in const ['juice', 'mythic', 'icons', 'cards', 'tarot'])
            SimpleDialogOption(
              key: Key('hdr-oracle-pick-$o'),
              onPressed: () => Navigator.pop(context, o),
              child: Text(_oracleLabel(o, oracles)),
            ),
          for (final o in oracles)
            SimpleDialogOption(
              key: Key('hdr-oracle-pick-${o.id}'),
              onPressed: () => Navigator.pop(context, '$_coPrefix${o.id}'),
              child: Text(o.name.isEmpty ? '(unnamed oracle)' : o.name),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(settingsProvider.notifier).setDefaultOracle(picked);
    }
  }
}
