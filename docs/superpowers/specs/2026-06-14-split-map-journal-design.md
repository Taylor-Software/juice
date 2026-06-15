# Side-by-Side Map + Journal — Design

**Date:** 2026-06-14
**Status:** Approved (brainstorm) — ready for implementation plan
**Depends on:** the existing `HomeShell` responsive shell (`_shellBody`, `Destination` enum,
`shellRouteProvider`), the global-persisted-notifier pattern (`rulesetsProvider`).

## Goal

On a wide screen, let the player view the **Maps tab and the Journal at the same time**, toggled on
demand. The journal becomes a pinned right-hand panel beside the selected destination; the default
left pane is Maps, so the immediate result is **Maps (with its subtabs) | Journal**.

## Decisions (settled in brainstorm)

- **Toggle button**, off by default, shown only on wide screens. Not automatic.
- The map pane is the **full Maps tab** (World/Dungeon/Journey/Hexcrawl subtabs).
- Journal pinned on the **right**, with a **draggable divider**; phones (narrow) keep today's tabs.

## State

A global (not session-scoped) persisted bool, mirroring `rulesetsProvider`:

```dart
class SplitViewNotifier extends AsyncNotifier<bool> {
  static const _key = 'juice.splitview.v1';
  @override
  Future<bool> build() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_key) ?? false;
  }
  Future<void> toggle() async {
    final next = !(state.valueOrNull ?? false);
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_key, next);
    state = AsyncData(next);
  }
}
final splitViewProvider =
    AsyncNotifierProvider<SplitViewNotifier, bool>(SplitViewNotifier.new);
```

The draggable journal width is transient shell state: `double _journalWidth = 400` in
`_HomeShellState`, clamped on drag to `[320, maxWidth * 0.6]`.

## Layout (`_shellBody`)

Thresholds: `wide = maxWidth >= 840` (existing rail breakpoint); **`canSplit = maxWidth >= 1000`**
(needs room for two panes). Split renders only when `split && canSplit`.

When `split && canSplit` (wide):

```
Row[
  NavigationRail(  // non-journal destinations only — journal is always visible at right
     destinations: leftDestinations, selectedIndex: leftIndex,
     onSelect: (i) => goTo(leftDestinations[i]) ),
  VerticalDivider(width: 1),
  Expanded(child: Row[
     Expanded(child: leftBody),                 // IndexedStack over leftDestinations
     _DragHandle(onDrag: ...),                   // draggable vertical divider
     SizedBox(width: _journalWidth, child: JournalScreen()),
  ]),
]
```

- `leftDestinations = destinations.where((d) => d != Destination.journal)`.
- `leftIndex = leftDestinations.indexOf(route.destination).clamp(0, len-1)` — when the route is
  Journal (or anything not in the left set), this clamps to index 0 = **Maps** (Maps is first in
  `_visibleDestinations` after Journal), so the split opens on Maps.
- `leftBody = IndexedStack(index: leftIndex, children: leftDestinations.map(_root))` — reuses the
  existing per-destination roots; every non-journal destination stays reachable via the rail.
- `JournalScreen()` mounts in the right panel (self-contained; watches its own providers).

Otherwise (not split, or narrow): **unchanged** — today's `wide` rail layout or narrow bottom-bar
layout over the full `destinations` IndexedStack.

## Toggle button (`HomeShell.build` app bar)

A new action, shown only when wide enough (`MediaQuery.sizeOf(context).width >= 1000`):

```dart
if (MediaQuery.sizeOf(context).width >= 1000)
  IconButton(
    key: const Key('split-toggle'),
    icon: Icon(split ? Icons.view_sidebar : Icons.view_sidebar_outlined),
    tooltip: split ? 'Single pane' : 'Split with journal',
    onPressed: () => ref.read(splitViewProvider.notifier).toggle(),
  ),
```
where `split = ref.watch(splitViewProvider).valueOrNull ?? false`. (Placed before the Campaigns
action.)

## Draggable divider

`_DragHandle` = a `MouseRegion(cursor: resizeColumn)` + `GestureDetector(onHorizontalDragUpdate)`
around a thin `VerticalDivider`, calling back with `details.delta.dx`; `_HomeShellState` updates
`_journalWidth = (_journalWidth - delta).clamp(320, maxWidth * 0.6)` (drag-left widens the journal).

## Testing

- `split_view_test.dart` (provider, mock prefs): defaults false; `toggle()` flips it and persists
  (`prefs.getBool('juice.splitview.v1') == true`); a second container reads back true.
- HomeShell widget test (reuses the `home_shell_test` override harness — verdant/emulator overrides,
  mock prefs; per the rootBundle-hang rule): at a **wide** surface (`tester.view.physicalSize`) with
  split **on**, both `MapsTab` and `JournalScreen` mount (`findsOneWidget` each) and the
  `split-toggle` is present; at a **narrow** surface, no `split-toggle` and only the selected
  destination mounts (journal not duplicated). Reset `tester.view` in tearDown.

## Files

**New:** `test/split_view_test.dart`. **Edit:** `lib/state/providers.dart` (`splitViewProvider`),
`lib/shared/home_shell.dart` (split branch in `_shellBody`, the toggle action, `_journalWidth` +
`_DragHandle`), `test/home_shell_test.dart` (add the split widget test, or a new file).

## Asserted calls (veto)

- **Journal as a pinned side-panel** (left pane follows the rail) over a hardcoded Map|Journal — it
  delivers map+journal by default *and* keeps other destinations reachable, with less special-casing.
- **Persisted toggle** (a layout preference should stick across launches).
- **Wide-only** (`>= 1000`); phones unchanged. Split silently falls back to single-pane if the window
  shrinks below the threshold while the toggle is on.

## Out of scope

- Splitting on narrow/phone screens (top/bottom stack).
- Choosing a different right-panel pane (always the journal).
- Persisting the dragged journal width (transient per session is fine for v1).
- A three-pane / arbitrary-pane layout system.
