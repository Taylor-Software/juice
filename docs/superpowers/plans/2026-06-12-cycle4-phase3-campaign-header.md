# Cycle 4 Phase 3: Campaign Header + Default Oracle Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: superpowers:subagent-driven-development or superpowers:executing-plans. Steps use checkbox (`- [ ]`) syntax.

**Goal:** A collapsible campaign band atop the journal showing current scene, pinned threads, starred party, chaos (Mythic), and crawl state — each tapping into its tool — plus a per-campaign default-oracle setting.

**Architecture:** Three additive model flags (`Thread.pinned`, `Character.starred`, `CampaignSettings.defaultOracle` + `headerCollapsed`); notifier toggles; a `_CampaignHeader` widget at the top of `JournalScreen`'s column (so the tool scrim covers it) that watches existing providers read-only and opens tools via `ToolHost.openToolIfKnown`. The chaos dial shows only when the campaign has used Mythic (any scene entry carries a `chaosFactor`); phase 4 will swap that heuristic for the system profile.

**Tech Stack:** Flutter + flutter_riverpod. House rules: TDD; format hook; analyze baseline exactly 1 info; never construct GemmaInterpreterService in tests; commits exact, no co-author. Lost-update rule: any read-modify-write toggle reads fresh at press time.

**Branch:** `cycle4-phase3-campaign-header` off main (after phase 2 merges). Plan committed first.

**Spec:** docs/superpowers/specs/2026-06-12-cycle4-living-journal-design.md §5.

---

### Task 1: Model flags — Thread.pinned, Character.starred, CampaignSettings.defaultOracle + headerCollapsed

**Files:**
- Modify: `lib/engine/models.dart` (Thread ~139, Character ~copyWith/toJson/fromJson, CampaignSettings)
- Test: `test/journal_test.dart` or `test/character_sheet_test.dart` for model round-trips — create `test/campaign_header_model_test.dart` to keep them together

- [ ] **Step 1: Write failing tests** (`test/campaign_header_model_test.dart`):

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:juice_oracle/engine/models.dart';

void main() {
  test('Thread.pinned round-trips and defaults false', () {
    expect(const Thread(id: 't', title: 'T').pinned, isFalse);
    final p = Thread.fromJson(
        const Thread(id: 't', title: 'T', pinned: true).toJson());
    expect(p.pinned, isTrue);
    // legacy JSON without the key
    expect(Thread.fromJson({'id': 't', 'title': 'T'}).pinned, isFalse);
    // copyWith toggles
    expect(const Thread(id: 't', title: 'T').copyWith(pinned: true).pinned,
        isTrue);
  });

  test('Character.starred round-trips and defaults false', () {
    expect(const Character(id: 'c', name: 'N').starred, isFalse);
    final s = Character.fromJson(
        const Character(id: 'c', name: 'N', starred: true).toJson());
    expect(s.starred, isTrue);
    expect(Character.fromJson({'id': 'c', 'name': 'N'}).starred, isFalse);
    expect(const Character(id: 'c', name: 'N').copyWith(starred: true).starred,
        isTrue);
  });

  test('Thread.toJson omits pinned when false (byte-stable legacy)', () {
    expect(const Thread(id: 't', title: 'T').toJson().containsKey('pinned'),
        isFalse);
  });

  test('Character.toJson omits starred when false', () {
    expect(const Character(id: 'c', name: 'N').toJson().containsKey('starred'),
        isFalse);
  });

  test('CampaignSettings.defaultOracle defaults juice and round-trips', () {
    expect(const CampaignSettings().defaultOracle, 'juice');
    final s = CampaignSettings.fromJson(
        const CampaignSettings(defaultOracle: 'mythic').toJson());
    expect(s.defaultOracle, 'mythic');
    expect(CampaignSettings.fromJson({}).defaultOracle, 'juice');
  });

  test('CampaignSettings.headerCollapsed defaults false and round-trips', () {
    expect(const CampaignSettings().headerCollapsed, isFalse);
    final s = CampaignSettings.fromJson(
        const CampaignSettings(headerCollapsed: true).toJson());
    expect(s.headerCollapsed, isTrue);
  });

  test('CampaignSettings keeps genre/tone alongside new fields', () {
    const s = CampaignSettings(
        genre: 'noir', tone: 'grim', defaultOracle: 'roll-high',
        headerCollapsed: true);
    final back = CampaignSettings.fromJson(s.toJson());
    expect(back.genre, 'noir');
    expect(back.tone, 'grim');
    expect(back.defaultOracle, 'roll-high');
    expect(back.headerCollapsed, isTrue);
  });
}
```

- [ ] **Step 2: Run, see fail.** `flutter test test/campaign_header_model_test.dart`

- [ ] **Step 3: Implement.**

`Thread`: add `this.pinned = false` to ctor; `final bool pinned;`; copyWith gains `bool? pinned` → `pinned: pinned ?? this.pinned`; toJson add `if (pinned) 'pinned': true`; fromJson add `pinned: (j['pinned'] as bool?) ?? false`.

`Character`: add `this.starred = false`; `final bool starred;`; copyWith `bool? starred` → `starred: starred ?? this.starred`; toJson `if (starred) 'starred': true`; fromJson `starred: (j['starred'] as bool?) ?? false`.

`CampaignSettings`: ctor `this.defaultOracle = 'juice', this.headerCollapsed = false`; two finals; copyWith adds both params; toJson add `'defaultOracle': defaultOracle, if (headerCollapsed) 'headerCollapsed': true`; fromJson `defaultOracle: j['defaultOracle'] as String? ?? 'juice', headerCollapsed: (j['headerCollapsed'] as bool?) ?? false`.

- [ ] **Step 4: Run, see pass.**

- [ ] **Step 5: Commit.** `git add lib/engine/models.dart test/campaign_header_model_test.dart && git commit -m "feat: Thread.pinned, Character.starred, CampaignSettings.defaultOracle/headerCollapsed (additive)"`

---

### Task 2: Notifier toggles + settings setters

**Files:**
- Modify: `lib/state/providers.dart` (ThreadNotifier, CharacterNotifier, SettingsNotifier)
- Test: `test/journal_test.dart` group or a new `test/campaign_header_state_test.dart`

- [ ] **Step 1: Failing tests** (`test/campaign_header_state_test.dart`) — mirror existing provider tests (SharedPreferences.setMockInitialValues, ProviderContainer). Cover:
  - `ThreadNotifier.togglePinned(id)` flips and persists; reads fresh (add thread, toggle, expect pinned true; toggle again false).
  - `CharacterNotifier.toggleStarred(id)` flips and persists.
  - `SettingsNotifier.setDefaultOracle('mythic')` persists; `setHeaderCollapsed(true)` persists; both preserve genre/tone.

```dart
  test('togglePinned flips fresh and persists', () async {
    SharedPreferences.setMockInitialValues({});
    final c = ProviderContainer();
    addTearDown(c.dispose);
    final n = c.read(threadsProvider.notifier);
    await c.read(threadsProvider.future);
    await n.add('Vow');
    final id = (await c.read(threadsProvider.future)).first.id;
    await n.togglePinned(id);
    expect((await c.read(threadsProvider.future)).first.pinned, isTrue);
    await n.togglePinned(id);
    expect((await c.read(threadsProvider.future)).first.pinned, isFalse);
  });
```
(Write the analogous starred + settings tests.)

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

ThreadNotifier:
```dart
  Future<void> togglePinned(String id) async {
    await _persist([
      for (final t in await _ready)
        if (t.id == id) t.copyWith(pinned: !t.pinned) else t,
    ]);
  }
```
CharacterNotifier (read the file: it has a `replace` like ThreadNotifier; mirror it):
```dart
  Future<void> toggleStarred(String id) async {
    await _persist([
      for (final ch in await _ready)
        if (ch.id == id) ch.copyWith(starred: !ch.starred) else ch,
    ]);
  }
```
(If CharacterNotifier's persist/ready members differ, match its actual API — read it first.)

SettingsNotifier:
```dart
  Future<void> setDefaultOracle(String oracle) async {
    final cur = state.valueOrNull ?? await future;
    await save(cur.copyWith(defaultOracle: oracle));
  }

  Future<void> setHeaderCollapsed(bool collapsed) async {
    final cur = state.valueOrNull ?? await future;
    await save(cur.copyWith(headerCollapsed: collapsed));
  }
```

CrawlNotifier — add a fresh-read chaos setter (the header's +/- uses it;
honors the lost-update rule unlike the fate screen's build-captured save):
```dart
  Future<void> setChaos(int n) async {
    final cur = state.valueOrNull ?? await future;
    await save(cur.copyWith(chaosFactor: n.clamp(1, 9)));
  }
```
Test it in Task 2: set 7 → chaosFactor 7; setChaos(0) clamps to 1; setChaos(12) clamps to 9.

- [ ] **Step 4: Run, see pass.**

- [ ] **Step 5: Commit.** `git commit -m "feat: pin/star/default-oracle/header-collapse notifier toggles"`

---

### Task 3: Pin + star toggles in the Threads & Characters tool

**Files:**
- Modify: `lib/features/tracker_screen.dart`
- Test: extend `test/character_sheet_ui_test.dart` and/or the tracker test (read which file drives the tracker)

- [ ] **Step 1: Failing tests** — in the tracker's test file, assert: a thread row has a pin IconButton (`Key('pin-thread-<id>')`) that toggles `threadsProvider` pinned; a character row/sheet has a star IconButton (`Key('star-char-<id>')`) toggling `charactersProvider` starred. (Mirror the file's existing pump + interaction pattern.)

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement** — add an `IconButton` (Icons.push_pin_outlined / push_pin for pinned; Icons.star_border / star for starred) to each thread and character row in tracker_screen.dart, calling the Task-2 toggles. Keys `pin-thread-<id>` / `star-char-<id>`. Keep within existing row layout (use IconButton with `visualDensity: VisualDensity.compact` to avoid overflow).

- [ ] **Step 4: Run, see pass.** Also run `flutter test test/tracker*` and any character sheet tests.

- [ ] **Step 5: Commit.** `git commit -m "feat: pin threads and star characters from the tracker"`

---

### Task 4: _CampaignHeader widget + journal integration

**Files:**
- Modify: `lib/features/journal_screen.dart` (insert header at top of the data Column; new `_CampaignHeader` widget)
- Test: `test/campaign_header_test.dart` (create)

- [ ] **Step 1: Failing widget tests** — pump JournalScreen under a ProviderScope with a real Oracle override + FakeInterpreter (mirror slash_palette_test's pump) and seed via prefs:
  - Seed a scene entry (kind scene, chaosFactor 6), a pinned thread, a starred character.
  - Header present (`Key('campaign-header')`); shows the scene title; shows a chaos chip reading `Chaos 6`; shows the pinned thread title chip (`Key('hdr-thread-<id>')`); shows the starred character chip (`Key('hdr-char-<id>')`).
  - Tapping the chaos `+`/`-` (`Key('hdr-chaos-inc')`/`dec`) changes the displayed value and persists via crawlProvider.
  - Collapse toggle (`Key('hdr-collapse')`) hides the detail row and persists `headerCollapsed` (re-pump reads collapsed).
  - No scene + no Mythic usage: chaos chip absent (seed a journal with only a text entry → `find.textContaining('Chaos')` findsNothing).
  - Default-oracle chip (`Key('hdr-oracle')`) shows 'Juice' and opens a picker; choosing 'Mythic' persists `defaultOracle`.

  Write each as a full test with assertions.

- [ ] **Step 2: Run, see fail.**

- [ ] **Step 3: Implement.**

Add `_CampaignHeader()` as the first child of the journal's data `Column` (above the filter-chips `SizedBox`). It is a `ConsumerWidget`-style block but JournalScreen is already a ConsumerState, so build it as a private method `_campaignHeader(...)` or a small `ConsumerWidget`. Prefer a separate `ConsumerWidget` `_CampaignHeader` for isolation:

```dart
class _CampaignHeader extends ConsumerWidget {
  const _CampaignHeader();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final settings = ref.watch(settingsProvider).valueOrNull ??
        const CampaignSettings();
    final entries = ref.watch(journalProvider).valueOrNull ?? const [];
    final threads = (ref.watch(threadsProvider).valueOrNull ?? const <Thread>[])
        .where((t) => t.open && t.pinned).toList();
    final stars = (ref.watch(charactersProvider).valueOrNull ??
            const <Character>[])
        .where((c) => c.starred).toList();
    final crawl = ref.watch(crawlProvider).valueOrNull;
    // Current scene: latest scene entry (storage newest-first).
    final scene = entries.where((e) => e.kind == JournalKind.scene).firstOrNull;
    // Mythic usage signal (phase 4 swaps for the profile flag): any scene
    // entry carries a chaos snapshot.
    final usesMythic =
        entries.any((e) => e.kind == JournalKind.scene && e.chaosFactor != null);
    final theme = Theme.of(context);
    final collapsed = settings.headerCollapsed;
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
              child: Text(
                scene?.title ?? 'No scene yet',
                style: theme.textTheme.labelLarge,
                overflow: TextOverflow.ellipsis,
              ),
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
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [
                  if (usesMythic && crawl != null) ...[
                    InputChip(
                      label: Text('Chaos ${crawl.chaosFactor}'),
                      onPressed: null,
                    ),
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
                  // NOTE: CrawlState has no `mode` — the only persistent
                  // "in a crawl" signal is wilderness travel (envRow != null).
                  ActionChip(
                    key: const Key('hdr-oracle'),
                    avatar: const Icon(Icons.casino_outlined, size: 16),
                    label: Text(_oracleLabel(settings.defaultOracle)),
                    onPressed: () => _pickOracle(context, ref, settings),
                  ),
                  for (final t in threads)
                    ActionChip(
                      key: Key('hdr-thread-${t.id}'),
                      avatar: const Icon(Icons.push_pin, size: 14),
                      label: Text(t.title),
                      onPressed: () =>
                          ToolHost.openToolIfKnown(context, 'threads-characters'),
                    ),
                  for (final c in stars)
                    ActionChip(
                      key: Key('hdr-char-${c.id}'),
                      avatar: const Icon(Icons.star, size: 14),
                      label: Text(c.name),
                      onPressed: () =>
                          ToolHost.openToolIfKnown(context, 'threads-characters'),
                    ),
                  if (crawl != null && crawl.envRow != null)
                    ActionChip(
                      key: const Key('hdr-crawl'),
                      avatar: const Icon(Icons.explore, size: 14),
                      label: Text(crawl.lost ? 'Wilderness (lost)' : 'Wilderness'),
                      onPressed: () =>
                          ToolHost.openToolIfKnown(context, 'gen-exploration'),
                    ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _oracleLabel(String id) => switch (id) {
        'mythic' => 'Mythic',
        'roll-high' => 'Roll High',
        _ => 'Juice',
      };

  Future<void> _pickOracle(
      BuildContext context, WidgetRef ref, CampaignSettings s) async {
    final picked = await showDialog<String>(
      context: context,
      builder: (_) => SimpleDialog(
        title: const Text('Default oracle'),
        children: [
          for (final o in const ['juice', 'mythic', 'roll-high'])
            SimpleDialogOption(
              onPressed: () => Navigator.pop(context, o),
              child: Text(_oracleLabel(o)),
            ),
        ],
      ),
    );
    if (picked != null) {
      await ref.read(settingsProvider.notifier).setDefaultOracle(picked);
    }
  }
}
```

VERIFIED (controller, against the real source): `CrawlState` fields are
envRow/lost/dialogRow/dialogCol/chaosFactor — there is NO `mode`/`CrawlMode`
(crawl chip gates on `envRow != null`). The crawl notifier has `save`/`reset`
only; the header uses the new `setChaos(int)` added in Task 2 (do not call a
non-existent setter). The fate screen adjusts chaos via
`save(crawl.copyWith(chaosFactor: ...))` — the header uses `setChaos` instead
for a fresh-read.

Insert into the journal data column (in `build`, the `data:` branch's `Column(children: [ ... ])`), as the FIRST child:
```dart
                children: [
                  const _CampaignHeader(),
                  if (threads.isNotEmpty || tags.isNotEmpty) ...
```

Imports: `../shared/tool_host.dart` (present from phase 1).

- [ ] **Step 4: Run until green.** `flutter test test/campaign_header_test.dart`

- [ ] **Step 5: Full gates.** `flutter analyze` (1 info), `flutter test` (full green — watch for journal_screen tests that counted Column children or expected no header; update them to tolerate the header).

- [ ] **Step 6: Commit.** `git commit -m "feat: collapsible campaign header (scene, chaos, pins, stars, crawl, oracle)"`

---

### Task 5: Docs

- [ ] **Step 1:** README note:
```markdown
- Campaign header: a collapsible band over the journal shows the current scene, Mythic chaos, pinned threads, starred characters, and crawl state — each opens its tool. Set the campaign's default oracle here.
```
- [ ] **Step 2:** `flutter analyze` + `flutter test` green.
- [ ] **Step 3: Commit.** `git commit -m "docs: README note for the campaign header"`

---

## Self-review notes

- Spec §5 coverage: collapsible band (Task 4 collapse toggle + persisted flag), chaos dial gated on Mythic usage (heuristic; phase-4 swaps for profile), current scene, pinned threads (Task 1+3 flag+toggle, Task 4 chips), starred party, crawl badge, defaultOracle setting (Task 1 field + Task 4 picker). Quick-ask that USES defaultOracle is phase 6 — explicit.
- Read-modify-write toggles all read fresh (`await _ready` inside the notifier) — lost-update rule honored.
- Verify-against-source flags: CrawlState mode/active signal + crawl chaos setter name (Task 4 note); CharacterNotifier persist/ready members (Task 2 note).
- Type names consistent: togglePinned, toggleStarred, setDefaultOracle, setHeaderCollapsed, _CampaignHeader, keys campaign-header/hdr-collapse/hdr-chaos-inc/dec/hdr-oracle/hdr-thread-<id>/hdr-char-<id>/hdr-crawl, pin-thread-<id>/star-char-<id>.
- Deferred: quick-ask wiring (phase 6), profile-based chaos gating (phase 4).
