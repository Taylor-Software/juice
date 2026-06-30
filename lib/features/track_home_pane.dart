import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../engine/models.dart';
import '../shared/design_tokens.dart';
import '../shared/destination.dart';
import '../shared/shell_route.dart';
import '../state/play_context.dart';
import '../state/providers.dart';

/// Track → Home: a "Where am I?" dashboard. Summary cards for the campaign's
/// live state (scene / threads / tracks / party / encounter) that double as
/// navigation into the matching subtab (or the Sheet verb for the roster).
///
/// Every card is defensive against empty/loading provider states — it shows a
/// neutral placeholder ("None yet" / "—") rather than crashing.
class TrackHomePane extends ConsumerWidget {
  const TrackHomePane({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final journal =
        ref.watch(journalProvider).valueOrNull ?? const <JournalEntry>[];
    final activeSceneId =
        ref.watch(playContextProvider).valueOrNull?.activeSceneId;
    final scene = activeSceneEntry(journal, activeSceneId);

    final threads = ref.watch(threadsProvider).valueOrNull ?? const <Thread>[];
    final tracks = ref.watch(tracksProvider).valueOrNull ?? const <Track>[];
    final chars =
        ref.watch(charactersProvider).valueOrNull ?? const <Character>[];
    final encounter =
        ref.watch(encounterProvider).valueOrNull ?? const EncounterState();
    final live = encounter.combatants.isNotEmpty;

    final encounterCard = _encounterCard(context, ref, encounter, live);
    final otherCards = [
      _nowCard(context, ref, scene),
      _threadsCard(context, ref, threads),
      _tracksCard(context, ref, tracks),
      _partyCard(context, ref, chars),
    ];

    // A live fight jumps to the top so it isn't buried under quiet sections.
    final cards =
        live ? [encounterCard, ...otherCards] : [...otherCards, encounterCard];

    final helpSeen = ref.watch(trackHelpSeenProvider).valueOrNull ?? true;

    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 24),
      children: [
        if (!helpSeen)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: _helpCard(context, ref),
          ),
        for (final c in cards)
          Padding(
            padding: const EdgeInsets.only(bottom: 12),
            child: c,
          ),
      ],
    );
  }

  // -- Orientation card ----------------------------------------------------

  /// A dismissible "what each Track subtab is for" card, shown once per device
  /// until dismissed (persisted via [trackHelpSeenProvider]).
  Widget _helpCard(BuildContext context, WidgetRef ref) {
    final tk = context.juice;
    const radius = BorderRadius.all(Radius.circular(14));
    const lines = <(String, String)>[
      ('Loop', 'guided solo play'),
      ('Tasks', 'tally-tracked goals'),
      ('Scenes', 'story beats'),
      ('Threads', 'open storylines'),
      ('Encounter', 'combat'),
      ('Rumors', 'leads'),
      ('Tracks', 'clocks'),
    ];
    return Material(
      key: const Key('track-help-card'),
      color: tk.raised,
      borderRadius: radius,
      child: Container(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 14),
        decoration: BoxDecoration(
          borderRadius: radius,
          border: Border.all(color: tk.hairline),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Text(
                  "WHAT'S HERE",
                  style: tk.uiLabel.copyWith(
                    fontSize: 11,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 1.2,
                    color: tk.inkMuted,
                  ),
                ),
                const Spacer(),
                IconButton(
                  key: const Key('track-help-dismiss'),
                  visualDensity: VisualDensity.compact,
                  icon: const Icon(Icons.close, size: 18),
                  tooltip: 'Dismiss',
                  onPressed: () =>
                      ref.read(trackHelpSeenProvider.notifier).markSeen(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            for (final (label, desc) in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 3, right: 8),
                child: RichText(
                  text: TextSpan(
                    style: TextStyle(color: tk.inkBody, height: 1.4),
                    children: [
                      TextSpan(
                        text: '$label ',
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      ),
                      TextSpan(text: '— $desc', style: TextStyle(color: tk.inkMuted)),
                    ],
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  // -- Cards ---------------------------------------------------------------

  Widget _nowCard(BuildContext context, WidgetRef ref, JournalEntry? scene) {
    final tk = context.juice;
    final title = (scene != null && scene.title.trim().isNotEmpty)
        ? scene.title.trim()
        : 'No scene yet';
    return _card(
      context,
      cardKey: const Key('track-home-now'),
      eyebrow: 'NOW',
      onTap: () => ref
          .read(shellRouteProvider.notifier)
          .goTo(Destination.track, subtab: 'scenes'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: tk.narrative.copyWith(
              fontSize: 18,
              height: 1.3,
              color: tk.ink,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (scene != null && scene.body.trim().isNotEmpty) ...[
            const SizedBox(height: 4),
            Text(
              scene.body.trim(),
              style: TextStyle(color: tk.inkBody, height: 1.4),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ],
      ),
    );
  }

  Widget _threadsCard(
      BuildContext context, WidgetRef ref, List<Thread> threads) {
    final tk = context.juice;
    final open = threads.where((t) => t.open).toList();
    final shown = open.isNotEmpty ? open : threads;
    return _card(
      context,
      cardKey: const Key('track-home-threads'),
      eyebrow: 'THREADS',
      headline: threads.isEmpty
          ? 'None yet'
          : '${open.length} open'
              '${open.length == threads.length ? '' : ' · ${threads.length} total'}',
      onTap: () => ref
          .read(shellRouteProvider.notifier)
          .goTo(Destination.track, subtab: 'threads'),
      child: threads.isEmpty
          ? Text('Track quests, vows, mysteries.',
              style: TextStyle(color: tk.inkMuted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in shown.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            Icon(
                              t.pinned ? Icons.push_pin : Icons.circle,
                              size: t.pinned ? 13 : 7,
                              color: t.open ? tk.terracotta : tk.inkMuted,
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                t.title,
                                style: TextStyle(
                                  color: t.open ? tk.inkBody : tk.inkMuted,
                                  decoration: t.open
                                      ? null
                                      : TextDecoration.lineThrough,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text(
                              '${t.progress}/${t.progressMax}',
                              style: tk.uiLabel.copyWith(
                                fontSize: 11,
                                color: tk.inkMuted,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: t.progressMax <= 0
                                ? 0.0
                                : (t.progress / t.progressMax).clamp(0.0, 1.0),
                            minHeight: 5,
                            backgroundColor: tk.hairline,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(tk.terracotta),
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
    );
  }

  Widget _tracksCard(BuildContext context, WidgetRef ref, List<Track> tracks) {
    final tk = context.juice;
    return _card(
      context,
      cardKey: const Key('track-home-tracks'),
      eyebrow: 'TRACKS',
      headline: tracks.isEmpty ? 'None yet' : '${tracks.length}',
      onTap: () => ref
          .read(shellRouteProvider.notifier)
          .goTo(Destination.track, subtab: 'tracks'),
      child: tracks.isEmpty
          ? Text('Clocks for tension and time.',
              style: TextStyle(color: tk.inkMuted))
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                for (final t in tracks.take(3))
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: Text(
                                t.name,
                                style: TextStyle(color: tk.inkBody),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            Text('${t.filled} / ${t.max}',
                                style: tk.uiLabel.copyWith(
                                    fontSize: 12, color: tk.inkMuted)),
                          ],
                        ),
                        const SizedBox(height: 3),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(4),
                          child: LinearProgressIndicator(
                            value: t.max == 0 ? 0 : (t.filled / t.max),
                            minHeight: 5,
                            backgroundColor: tk.hairline,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(tk.terracotta),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (tracks.length > 3)
                  Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text('+${tracks.length - 3} more',
                        style: TextStyle(color: tk.inkMuted, fontSize: 12)),
                  ),
              ],
            ),
    );
  }

  Widget _partyCard(
      BuildContext context, WidgetRef ref, List<Character> chars) {
    final tk = context.juice;
    // Party = PCs + companions (the people you direct), NPCs excluded.
    final party = chars
        .where((c) =>
            c.role == CharacterRole.pc || c.role == CharacterRole.companion)
        .toList();
    return _card(
      context,
      cardKey: const Key('track-home-party'),
      eyebrow: 'PARTY',
      headline: party.isEmpty ? 'None yet' : '${party.length}',
      // The roster lives on the Sheet verb.
      onTap: () =>
          ref.read(shellRouteProvider.notifier).goTo(Destination.sheet),
      child: party.isEmpty
          ? Text('Create your first character.',
              style: TextStyle(color: tk.inkMuted))
          : Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final c in party.take(6)) _partyChip(context, c),
              ],
            ),
    );
  }

  Widget _partyChip(BuildContext context, Character c) {
    final tk = context.juice;
    final hp = _hpOf(c);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: tk.raised,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: tk.hairline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(c.name,
              style: TextStyle(color: tk.ink, fontWeight: FontWeight.w600)),
          if (hp != null) ...[
            const SizedBox(width: 8),
            Icon(Icons.favorite, size: 12, color: tk.terracotta),
            const SizedBox(width: 3),
            Text('${hp.$1}/${hp.$2}',
                style: tk.uiLabel.copyWith(fontSize: 12, color: tk.inkBody)),
          ],
          if (c.conditions.isNotEmpty) ...[
            const SizedBox(width: 8),
            Icon(Icons.bolt, size: 12, color: tk.chaos),
            const SizedBox(width: 2),
            Text('${c.conditions.length}',
                style: tk.uiLabel.copyWith(fontSize: 12, color: tk.inkMuted)),
          ],
        ],
      ),
    );
  }

  Widget _encounterCard(BuildContext context, WidgetRef ref,
      EncounterState encounter, bool live) {
    final tk = context.juice;
    final alive = encounter.combatants.where((c) => !c.defeated).length;
    return _card(
      context,
      cardKey: const Key('track-home-encounter'),
      eyebrow: 'ENCOUNTER',
      headline: live ? 'Round ${encounter.round}' : 'Idle',
      emphasized: live,
      onTap: () => ref
          .read(shellRouteProvider.notifier)
          .goTo(Destination.track, subtab: 'encounter'),
      child: live
          ? Row(
              children: [
                Icon(Icons.local_fire_department, size: 16, color: tk.chaos),
                const SizedBox(width: 6),
                Text(
                  '$alive in the fight'
                  '${alive == encounter.combatants.length ? '' : ' · ${encounter.combatants.length} total'}',
                  style:
                      TextStyle(color: tk.inkBody, fontWeight: FontWeight.w600),
                ),
              ],
            )
          : Text('No active fight.', style: TextStyle(color: tk.inkMuted)),
    );
  }

  // -- Shared card shell ---------------------------------------------------

  Widget _card(
    BuildContext context, {
    required Key cardKey,
    required String eyebrow,
    required VoidCallback onTap,
    required Widget child,
    String? headline,
    bool emphasized = false,
  }) {
    final tk = context.juice;
    const radius = BorderRadius.all(Radius.circular(14));
    final bg = emphasized ? const Color(0xFFFFF6F0) : tk.card;
    final border = emphasized ? const Color(0xFFF0CDB8) : tk.hairline;
    return Material(
      color: bg,
      borderRadius: radius,
      child: InkWell(
        key: cardKey,
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.fromLTRB(16, 14, 14, 16),
          decoration: BoxDecoration(
            borderRadius: radius,
            border: Border.all(color: border),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Text(
                    eyebrow,
                    style: tk.uiLabel.copyWith(
                      fontSize: 11,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 1.2,
                      color: emphasized ? tk.chaos : tk.inkMuted,
                    ),
                  ),
                  if (headline != null) ...[
                    const Spacer(),
                    Text(
                      headline,
                      style: tk.uiLabel.copyWith(
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: emphasized ? tk.chaos : tk.inkBody,
                      ),
                    ),
                  ],
                  const SizedBox(width: 8),
                  Text('Open ↗',
                      style: tk.uiLabel
                          .copyWith(fontSize: 12, color: tk.terracotta)),
                ],
              ),
              const SizedBox(height: 8),
              child,
            ],
          ),
        ),
      ),
    );
  }

  // -- Helpers -------------------------------------------------------------

  /// Resolves a character's HP pool the same way the encounter tracker does
  /// (Character.withHpDelta's order). Delegates to the shared [characterHpPool].
  (int, int)? _hpOf(Character c) => characterHpPool(c);
}
